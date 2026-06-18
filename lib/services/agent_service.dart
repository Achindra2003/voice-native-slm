// Owns the on-device language model (Cactus) and turns a natural-language
// command into structured tool calls. Pure logic — no Flutter dependencies.

import 'package:cactus/cactus.dart';

import '../models/agent_model.dart';
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
  CactusLM? _lm;
  String currentModelId;

  AgentService({this.currentModelId = kDefaultModelId});

  bool get isLoaded => _lm?.isLoaded() ?? false;

  /// Download (if needed) and initialize the current model.
  Future<void> initialize({void Function(String)? onStatus}) async {
    onStatus?.call('Downloading $currentModelId…');
    _lm = CactusLM();
    await _lm!.downloadModel(
      model: currentModelId,
      downloadProcessCallback: (progress, msg, isError) {
        if (!isError) {
          final pct = progress != null
              ? ' (${(progress * 100).toStringAsFixed(0)}%)'
              : '';
          onStatus?.call('$msg$pct');
        }
      },
    );
    onStatus?.call('Initializing $currentModelId…');
    await _lm!.initializeModel();
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
      final result = await _lm!.generateCompletion(
        messages: [
          ChatMessage(content: systemPromptFor(modelType), role: 'system'),
          ChatMessage(content: userMessage, role: 'user'),
        ],
        params: CactusCompletionParams(
          tools: buildAgentTools(),
          maxTokens: 300,
          temperature: 0.1,
        ),
      );
      sw.stop();

      final calls = result.toolCalls
          .map((c) => AgentToolCall(
                c.name,
                Map<String, dynamic>.from(c.arguments),
              ))
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
      _lm?.unload();
    } catch (_) {}
    _lm = null;
  }
}
