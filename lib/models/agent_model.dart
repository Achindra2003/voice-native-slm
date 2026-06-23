/// The set of on-device models the app can run. Every entry supports function
/// calling, required for device-control intent parsing. This is the single
/// source of truth shared by the interactive screen and the benchmark runner.
///
/// `type` selects the adaptive system prompt (see `tools/agent_tools.dart`):
///   generalist — Transformer models (Qwen3 / Qwen3.5)
///   liquid     — hybrid-recurrent LFM2 (temporal reasoning)
///   specialist — function-calling tuned (FunctionGemma)
///   audio      — audio-native models that take raw PCM bytes (no ASR stage)
class AgentModel {
  final String id;   // folder name used under models/
  final String name; // display name
  final String type; // generalist | liquid | specialist | audio

  const AgentModel({required this.id, required this.name, required this.type});
}

const List<AgentModel> kAgentModels = [
  // ── Specialist ─────────────────────────────────────────────────────────────
  AgentModel(id: 'functiongemma-270m', name: 'FunctionGemma 270M', type: 'specialist'),
  // ── Liquid / LFM2 (hybrid-recurrent, temporal reasoning) ──────────────────
  AgentModel(id: 'lfm2-350m',   name: 'LFM2 350M',   type: 'liquid'),
  AgentModel(id: 'lfm2.5-350m', name: 'LFM2.5 350M', type: 'liquid'),
  AgentModel(id: 'lfm2-700m',   name: 'LFM2 700M',   type: 'liquid'),
  AgentModel(id: 'lfm2-1.2b',   name: 'LFM2 1.2B',   type: 'liquid'),
  // ── Transformer (Qwen3 / Qwen3.5) ─────────────────────────────────────────
  AgentModel(id: 'qwen3-0.6',   name: 'Qwen3 0.6B',   type: 'generalist'),
  AgentModel(id: 'qwen3-1.7',   name: 'Qwen3 1.7B',   type: 'generalist'),
  AgentModel(id: 'qwen3.5-0.8', name: 'Qwen3.5 0.8B', type: 'generalist'),
  AgentModel(id: 'qwen3.5-2b',  name: 'Qwen3.5 2B',   type: 'generalist'),
  // ── Audio-native (raw PCM → action, no separate ASR stage) ────────────────
  AgentModel(id: 'lfm2-audio-350m', name: 'LFM2-audio 350M', type: 'audio'),
  AgentModel(id: 'gemma-4-1b',      name: 'Gemma 4 1B',      type: 'audio'),
  // ── Placeholder (already transpiled, on-device) ───────────────────────────
  AgentModel(id: 'lfm2-vl-450m', name: 'LFM2-VL 450M (placeholder)', type: 'liquid'),
];

const String kDefaultModelId = 'lfm2-vl-450m';

AgentModel agentModelById(String id) {
  return kAgentModels.firstWhere(
    (m) => m.id == id,
    orElse: () => kAgentModels.first,
  );
}

String agentModelTypeLabel(String type) {
  switch (type) {
    case 'liquid':
      return 'Liquid — temporal reasoning (LFM2)';
    case 'specialist':
      return 'Specialist — function-calling tuned';
    case 'audio':
      return 'Audio-native — raw PCM input, no ASR stage';
    default:
      return 'Generalist — Transformer model';
  }
}
