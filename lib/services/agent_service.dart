// Owns the on-device language model (Cactus) and turns a natural-language
// command into structured tool calls. Pure logic — no Flutter dependencies.

import '../models/agent_model.dart';
import '../native/cactus_engine.dart';
import '../native/model_store.dart';
import '../tools/agent_tools.dart';

/// One function call extracted from the model's response.
class AgentToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  AgentToolCall(this.name, this.arguments);
}

/// Result of running one command through the model.
class AgentResult {
  final bool success;
  final List<AgentToolCall> toolCalls;
  final int latencyMs;
  final String? error;

  AgentResult({
    required this.success,
    required this.toolCalls,
    required this.latencyMs,
    this.error,
  });
}

class AgentService {
  CactusEngine? _engine;
  String currentModelId;

  AgentService({this.currentModelId = kDefaultModelId});

  bool get isLoaded => _engine?.isLoaded ?? false;

  /// Initialize the current model from its staged on-device folder.
  ///
  /// Models are no longer downloaded by the engine (the v2.0 FFI binding has no
  /// download layer). Stage them once with `adb push` into the ModelStore path
  /// (see [ModelStore.modelDir]).
  Future<void> initialize({void Function(String)? onStatus}) async {
    final path = await ModelStore.modelDir(currentModelId);
    if (!await ModelStore.isStaged(currentModelId)) {
      throw Exception(
        'Model "$currentModelId" not found at $path. '
        'Stage it with: adb push <model_dir> $path',
      );
    }
    onStatus?.call('Initializing $currentModelId…');
    final engine = CactusEngine()..init(path);
    _engine = engine;
    onStatus?.call('Model ready: $currentModelId');
  }

  /// Unload the current model and load a different one.
  Future<void> switchModel(String newModelId,
      {void Function(String)? onStatus}) async {
    if (newModelId == currentModelId && isLoaded) return;
    _unload();
    currentModelId = newModelId;
    await initialize(onStatus: onStatus);
  }

  /// Run one command through the model and return any tool calls.
  Future<AgentResult> send(String userMessage) async {
    if (!isLoaded) {
      return AgentResult(
        success: false,
        toolCalls: const [],
        latencyMs: 0,
        error: 'Model not initialized',
      );
    }

    final modelType = agentModelById(currentModelId).type;
    final sw = Stopwatch()..start();
    try {
      final result = _engine!.complete(
        messages: [
          {'role': 'system', 'content': systemPromptFor(modelType)},
          {'role': 'user', 'content': userMessage},
        ],
        tools: buildAgentTools(),
        maxTokens: 300,
        temperature: 0.1,
      );
      sw.stop();

      final calls = result.toolCalls
          .map((c) => AgentToolCall(c.name, c.arguments))
          .toList();

      return AgentResult(
        success: result.success && calls.isNotEmpty,
        toolCalls: calls,
        latencyMs: sw.elapsedMilliseconds,
        error: calls.isEmpty ? 'No tool calls generated' : null,
      );
    } catch (e) {
      sw.stop();
      return AgentResult(
        success: false,
        toolCalls: const [],
        latencyMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  void dispose() => _unload();

  void _unload() {
    try {
      _engine?.dispose();
    } catch (_) {}
    _engine = null;
  }
}
