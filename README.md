# voice-native-slm

On-device voice-controlled automation for Android, powered by small language models (SLMs) running entirely on the phone — no cloud, no internet. A spoken or typed command is mapped to a device-control function call (Do Not Disturb, flashlight, volume, brightness, Wi-Fi, contextual rules).

Built as the experimental platform for a research study comparing two on-device architectures for voice control:

- **Pipeline** — speech is transcribed on-device by Whisper-base, then a text SLM emits the function call.
- **Audio-native** — a multimodal model maps the raw audio straight to the function call, with no transcript.

Both arms receive the same recorded clips (matched audio), so the architecture is the only thing that changes.

- **Runtime:** [Cactus](https://github.com/cactus-compute/cactus) v2.0, called directly over Dart FFI
- **Platform:** Flutter, Android (CPU-only inference, 4-bit weights)
- **Test device:** OPPO F25 Pro (MediaTek Dimensity 7050, 8 GB)

## Models

The model set is the single source of truth in [`lib/models/agent_model.dart`](lib/models/agent_model.dart).

| Role | Models |
|------|--------|
| ASR (pipeline stage 1) | Whisper-base (74M) |
| Hybrid conv-attention (pipeline) | LFM2 350M, 700M, 1.2B · LFM2.5 350M, 1.2B |
| Tool-calling specialist (pipeline) | LFM2 1.2B Tool |
| Dense Transformer (pipeline) | Qwen3 0.6B, 1.7B · Qwen3.5 0.8B, 2B |
| Audio-native (direct) | Gemma 4 E2B |

FunctionGemma 270M is listed in the registry but does not load on the Cactus v2.0 runtime, so it is not part of the evaluated set.

## How it works

```
Pipeline:     audio ──▶ Whisper-base ──▶ transcript ──▶ text SLM + tools ──▶ function call ──▶ device action
Audio-native: audio ──────────────────────────────────▶ Gemma 4 E2B + tools ──▶ function call ──▶ device action
```

Each model gets the six tool definitions and a system prompt from [`lib/tools/agent_tools.dart`](lib/tools/agent_tools.dart), and must return a structured function call. The same tools and prompts drive both the interactive app and the benchmark, so the app behaves exactly as it is measured.

## Setup

Model bundles are too large for git. They are pushed to the phone once, into
`/storage/emulated/0/Android/data/com.example.my_agent_app/files/models/<id>/`
(see [`push_models.ps1`](push_models.ps1)), then:

```bash
flutter run --release
```

## Using the app

1. Press **Initialize** to load the selected model.
2. Press **Request DND Permission**.
3. Type a command, e.g. *"I need silence for 2 hours"*, and press **Send** — the model's function call is executed on the device.

Benchmarking:

- **Mic icon** — record the benchmark voice clips (16 kHz mono WAV) for the selected condition.
- **Condition dropdown** — Main (English), Pilot English, or Pilot code-switched (Hinglish/Kanglish).
- **Run benchmark** — runs every model over the recorded clips: Whisper transcribes once, the transcripts are cached, and every pipeline model and the audio-native model are scored on the same audio.
- **⋮ menu** — Smoke test (Whisper + one text + one audio model, 2 commands), Load sweep, Gemma transcript ablation (the audio-native model fed the cached transcripts as text), and Prompt-fairness swap.

Results are written after every command (a crashed run resumes), to the app's external files directory, pullable with `adb pull`:

- `headless_benchmark_results[_<condition>].csv` / `.json` — every trial
- `headless_benchmark_summary[_<condition>].md` — per-model summary
- `benchmark_progress[_<condition>].json` — resume checkpoint

Each row records the input mode (`pipeline` or `direct`), the transcript and its word error rate, the expected vs. actual function and parameters, and latency.

## Project structure

```
lib/
├─ main.dart                          app entry
├─ native/
│  ├─ cactus.dart                     FFI bindings to the Cactus engine
│  ├─ cactus_engine.dart              model load / completion / transcription
│  └─ model_store.dart                on-device model + results paths
├─ screens/
│  ├─ home_screen.dart                interactive UI + benchmark controls
│  └─ recording_screen.dart           records the benchmark clips
├─ services/
│  ├─ agent_service.dart              owns the model; command → tool calls
│  ├─ device_executor.dart            executes tool calls + manages rules
│  ├─ headless_benchmark_runner.dart  crash-resistant two-arm benchmark
│  ├─ benchmark_service.dart          result/dataset data classes
│  └─ wer.dart                        word error rate
├─ tools/
│  ├─ agent_tools.dart                tool schema + system prompts (shared)
│  └─ device_controls.dart            Android device-control channel
├─ models/
│  ├─ agent_model.dart                model catalog (single source)
│  └─ automation_rule.dart
└─ widgets/                           model selector · metrics · onboarding
```

## License

MIT — see [LICENSE](LICENSE).
