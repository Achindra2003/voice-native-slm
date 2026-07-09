/// The set of on-device models the app can run. Every entry supports function
/// calling, required for device-control intent parsing. This is the single
/// source of truth shared by the interactive screen and the benchmark runner.
///
/// `type` selects the adaptive system prompt (see `tools/agent_tools.dart`):
///   generalist — Transformer models (Qwen3 / Qwen3.5)
///   liquid     — hybrid-recurrent LFM2 (temporal reasoning)
///   specialist — function-calling tuned (LFM2-1.2B-Tool; FunctionGemma is
///                unloadable on the v2.0 engine and excluded from benchmarks)
///   audio      — audio-native models that take raw PCM bytes (no ASR stage)
class AgentModel {
  final String id;   // folder name used under models/
  final String name; // display name
  final String type; // generalist | liquid | specialist | audio

  const AgentModel({required this.id, required this.name, required this.type});
}

const List<AgentModel> kAgentModels = [
  // ── Specialist ─────────────────────────────────────────────────────────────
  // functiongemma-270m stays selectable (it demos the v2.0 init failure live)
  // but is NOT in the benchmark set. lfm2-1.2b-tool replaces it as the
  // function-calling specialist (bundle pushed to the device 2026-07-09).
  AgentModel(id: 'functiongemma-270m', name: 'FunctionGemma 270M', type: 'specialist'),
  AgentModel(id: 'lfm2-1.2b-tool', name: 'LFM2 1.2B Tool', type: 'specialist'),
  // ── Liquid / LFM2 (hybrid-recurrent, temporal reasoning) ──────────────────
  AgentModel(id: 'lfm2-350m',   name: 'LFM2 350M',   type: 'liquid'),
  AgentModel(id: 'lfm2.5-350m', name: 'LFM2.5 350M', type: 'liquid'),
  AgentModel(id: 'lfm2-700m',   name: 'LFM2 700M',   type: 'liquid'),
  AgentModel(id: 'lfm2-1.2b',   name: 'LFM2 1.2B',   type: 'liquid'),
  // Gen-2.5 at 1.2B — completes the LFM2-vs-2.5 generational comparison at a
  // second size (bundle pushed to the device 2026-07-09).
  AgentModel(id: 'lfm2.5-1.2b', name: 'LFM2.5 1.2B', type: 'liquid'),
  // ── Transformer (Qwen3 / Qwen3.5) ─────────────────────────────────────────
  AgentModel(id: 'qwen3-0.6',   name: 'Qwen3 0.6B',   type: 'generalist'),
  AgentModel(id: 'qwen3-1.7',   name: 'Qwen3 1.7B',   type: 'generalist'),
  AgentModel(id: 'qwen3.5-0.8', name: 'Qwen3.5 0.8B', type: 'generalist'),
  AgentModel(id: 'qwen3.5-2b',  name: 'Qwen3.5 2B',   type: 'generalist'),
  // ── Audio-native (raw PCM → action, no separate ASR stage) ────────────────
  // Gemma 4 E2B carries the direct arm alone; its bundle ships a real
  // audio_encoder component (verified in the transpiled zip, 2026-07-05).
  // Gemma 3n was dropped: Cactus's transpiler has no gemma3n adapter at any
  // commit, so no runnable bundle can exist. LFM2-Audio was dropped earlier:
  // only a 1.5B end-to-end audio-token model exists, also untranspilable.
  AgentModel(id: 'gemma-4-e2b', name: 'Gemma 4 E2B', type: 'audio'),
  // ── Placeholder (already transpiled, on-device) ───────────────────────────
  AgentModel(id: 'lfm2-vl-450m', name: 'LFM2-VL 450M (placeholder)', type: 'liquid'),
];

const String kDefaultModelId = 'lfm2-vl-450m';

/// Whisper STT model that produces the transcript for the pipeline arm's ASR
/// stage. Not a model under test — it transcribes the recorded audio clips,
/// and that transcript is what the text SLMs receive. Stage it like any other
/// Cactus bundle: `adb push <whisper_dir> .../models/<id>`.
const String kWhisperModelId = 'whisper-base';

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
