import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'cactus.dart';

class CactusToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  CactusToolCall(this.name, this.arguments);
}

class CactusCompletionResult {
  final bool success;
  final String response;
  final List<CactusToolCall> toolCalls;
  final String? error;
  final double totalTimeMs;

  CactusCompletionResult({
    required this.success,
    required this.response,
    required this.toolCalls,
    this.error,
    this.totalTimeMs = 0,
  });
}

/// Owns one native model handle. Call [init] before [complete]; both are async
/// and run FFI on a background isolate so the UI thread stays responsive.
class CactusEngine {
  Pointer<Void>? _model;

  bool get isLoaded => _model != null && _model != nullptr;

  Future<void> init(String modelPath) async {
    final address = await Isolate.run(() {
      final pathPtr = modelPath.toNativeUtf8();
      try {
        final handle = cactusInit(pathPtr, nullptr, false);
        if (handle == nullptr) {
          final errPtr = cactusGetLastError();
          final err = (errPtr == nullptr) ? 'unknown' : errPtr.toDartString();
          throw Exception('cactus_init failed: $err');
        }
        return handle.address;
      } finally {
        calloc.free(pathPtr);
      }
    });
    _model = Pointer<Void>.fromAddress(address);
  }

  /// Run inference. For audio-native models, supply [pcmBytes] (raw int16 PCM
  /// at 16 kHz mono); for text models leave it null.
  Future<CactusCompletionResult> complete({
    required List<Map<String, String>> messages,
    List<Map<String, dynamic>>? tools,
    int maxTokens = 300,
    double temperature = 0.1,
    int bufferSize = 1 << 19,
    Uint8List? pcmBytes,
  }) async {
    final model = _model;
    if (model == null || model == nullptr) {
      return CactusCompletionResult(
        success: false,
        response: '',
        toolCalls: const [],
        error: 'Model not initialized',
      );
    }

    final modelAddress = model.address;
    final messagesJson = jsonEncode(messages);
    final optionsJson =
        jsonEncode({'max_tokens': maxTokens, 'temperature': temperature});
    final toolsJson =
        (tools != null && tools.isNotEmpty) ? jsonEncode(tools) : null;
    final hasTools = toolsJson != null;
    final pcmCopy = pcmBytes; // captured for the isolate closure

    final (rc, out) = await Isolate.run(() {
      final mdl = Pointer<Void>.fromAddress(modelAddress);
      final msgsPtr = messagesJson.toNativeUtf8();
      final optsPtr = optionsJson.toNativeUtf8();
      final toolsPtr = (toolsJson ?? '').toNativeUtf8();
      final buf = calloc<Int8>(bufferSize);

      Pointer<Uint8> pcmPtr = nullptr;
      if (pcmCopy != null && pcmCopy.isNotEmpty) {
        pcmPtr = calloc<Uint8>(pcmCopy.length);
        pcmPtr.asTypedList(pcmCopy.length).setAll(0, pcmCopy);
      }

      try {
        final rc = cactusComplete(
          mdl,
          msgsPtr,
          buf.cast(),
          bufferSize,
          optsPtr,
          hasTools ? toolsPtr : nullptr,
          nullptr,
          nullptr,
          pcmPtr,
          pcmCopy?.length ?? 0,
        );
        return (rc, buf.cast<Utf8>().toDartString());
      } finally {
        calloc.free(msgsPtr);
        calloc.free(optsPtr);
        calloc.free(toolsPtr);
        calloc.free(buf);
        if (pcmPtr != nullptr) calloc.free(pcmPtr);
      }
    });

    if (out.isEmpty) {
      return CactusCompletionResult(
        success: false,
        response: '',
        toolCalls: const [],
        error: 'cactus_complete returned rc=$rc',
      );
    }
    return _parse(out);
  }

  /// Transcribe an audio file using a Whisper/audio model loaded via [init].
  /// Returns the raw transcript string. Throws on failure.
  ///
  /// Surfaces native failures instead of silently returning "": a failed
  /// transcribe would otherwise yield an empty transcript and score WER 1.0 on
  /// every clip, corrupting a whole benchmark run with no visible error.
  Future<String> transcribe(String audioFilePath) async {
    final model = _model;
    if (model == null || model == nullptr) {
      throw Exception('Model not initialized');
    }
    final modelAddress = model.address;
    final (rc, text, err) = await Isolate.run(() {
      final mdl = Pointer<Void>.fromAddress(modelAddress);
      final pathPtr = audioFilePath.toNativeUtf8();
      final promptPtr = ''.toNativeUtf8();
      const bufSize = 1 << 16; // 64 KB
      final buf = calloc<Int8>(bufSize);
      try {
        final rc = cactusTranscribe(mdl, pathPtr, promptPtr, buf.cast(),
            bufSize, nullptr, nullptr, nullptr, nullptr, 0);
        final text = buf.cast<Utf8>().toDartString();
        String? err;
        if (rc < 0 || text.trim().isEmpty) {
          final ePtr = cactusGetLastError();
          err = (ePtr == nullptr) ? null : ePtr.toDartString();
        }
        return (rc, text, err);
      } finally {
        calloc.free(pathPtr);
        calloc.free(promptPtr);
        calloc.free(buf);
      }
    });
    if (rc < 0) {
      throw Exception('cactus_transcribe failed (rc=$rc): ${err ?? 'unknown'}');
    }
    if (text.trim().isEmpty) {
      throw Exception(
        'cactus_transcribe produced no text for "$audioFilePath" (rc=$rc): '
        '${err ?? 'is the Whisper bundle loaded and the clip non-empty?'}',
      );
    }
    // The native layer fills the buffer with the same JSON envelope as
    // cactus_complete ({"success":..,"response":"<transcript>",..}) — the
    // transcript is its "response" field. Returning the raw buffer would feed
    // the whole envelope to every pipeline model and score WER against it.
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) {
      try {
        final m = jsonDecode(trimmed) as Map<String, dynamic>;
        final r = m['response'];
        if (r is String && r.trim().isNotEmpty) return r.trim();
      } catch (_) {
        // Not the JSON envelope after all — fall through to the raw text.
      }
    }
    return text;
  }

  CactusCompletionResult _parse(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final calls = <CactusToolCall>[];
      for (final c in (m['function_calls'] as List? ?? const [])) {
        final cm = c as Map<String, dynamic>;
        var args = cm['arguments'];
        if (args is String) {
          try {
            args = jsonDecode(args);
          } catch (_) {
            args = <String, dynamic>{};
          }
        }
        calls.add(CactusToolCall(
          (cm['name'] ?? '').toString(),
          args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{},
        ));
      }
      return CactusCompletionResult(
        success: (m['success'] as bool?) ?? false,
        response: (m['response'] as String?) ?? '',
        toolCalls: calls,
        error: m['error'] as String?,
        totalTimeMs: (m['total_time_ms'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      return CactusCompletionResult(
        success: false,
        response: jsonStr,
        toolCalls: const [],
        error: 'Failed to parse engine response: $e',
      );
    }
  }

  void dispose() {
    final m = _model;
    if (m != null && m != nullptr) {
      cactusDestroy(m);
    }
    _model = null;
  }
}
