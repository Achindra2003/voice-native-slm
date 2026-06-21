// Thin Dart wrapper around the raw dart:ffi bindings in `cactus.dart`
// (Cactus v2.0 engine, libcactus_engine.so). Replaces the old high-level
// `package:cactus` `CactusLM` API, which no longer exists — the v2.0 Flutter
// binding is pure FFI with no model-download layer.
//
// Inference only. Model files must already exist on-device at a local path
// (see ModelStore); `cactusInit` takes a folder path, not a registry slug.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'cactus.dart';

/// One function call parsed from the model's `function_calls` output.
class CactusToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  CactusToolCall(this.name, this.arguments);
}

/// Parsed result of a `cactus_complete` call.
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

/// Owns one native model handle. Not isolate-safe; use from one isolate.
class CactusEngine {
  Pointer<Void>? _model;

  bool get isLoaded => _model != null && _model != nullptr;

  /// Load a model from an on-device folder path. Throws on failure.
  void init(String modelPath) {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final handle = cactusInit(pathPtr, nullptr, false);
      if (handle == nullptr) {
        throw Exception('cactus_init failed for "$modelPath": ${_lastError()}');
      }
      _model = handle;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Run a chat completion. [messages] and [tools] are plain Dart structures
  /// that are JSON-encoded into the format the engine expects.
  CactusCompletionResult complete({
    required List<Map<String, String>> messages,
    List<Map<String, dynamic>>? tools,
    int maxTokens = 300,
    double temperature = 0.1,
    int bufferSize = 1 << 19, // 512 KB — ample for tool-call responses
  }) {
    final model = _model;
    if (model == null || model == nullptr) {
      return CactusCompletionResult(
        success: false,
        response: '',
        toolCalls: const [],
        error: 'Model not initialized',
      );
    }

    final messagesJson = jsonEncode(messages);
    final optionsJson =
        jsonEncode({'max_tokens': maxTokens, 'temperature': temperature});
    final toolsJson = (tools != null && tools.isNotEmpty) ? jsonEncode(tools) : null;

    final msgsPtr = messagesJson.toNativeUtf8();
    final optsPtr = optionsJson.toNativeUtf8();
    final toolsPtr = (toolsJson ?? '').toNativeUtf8();
    final buf = calloc<Int8>(bufferSize);
    try {
      final rc = cactusComplete(
        model,
        msgsPtr,
        buf.cast(),
        bufferSize,
        optsPtr,
        toolsJson == null ? nullptr : toolsPtr,
        nullptr, // token callback
        nullptr, // userData
        nullptr, // pcm buffer
        0, // pcm size
      );
      final out = buf.cast<Utf8>().toDartString();
      if (out.isEmpty) {
        return CactusCompletionResult(
          success: false,
          response: '',
          toolCalls: const [],
          error: 'cactus_complete returned rc=$rc: ${_lastError()}',
        );
      }
      return _parse(out);
    } finally {
      calloc.free(msgsPtr);
      calloc.free(optsPtr);
      calloc.free(toolsPtr);
      calloc.free(buf);
    }
  }

  CactusCompletionResult _parse(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final calls = <CactusToolCall>[];
      for (final c in (m['function_calls'] as List? ?? const [])) {
        final cm = c as Map<String, dynamic>;
        var args = cm['arguments'];
        // arguments may arrive as a nested object or as a JSON string.
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

  String _lastError() {
    try {
      final p = cactusGetLastError();
      if (p == nullptr) return 'unknown';
      return p.toDartString();
    } catch (_) {
      return 'unknown';
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
