# voice-native-slm

On-device voice-controlled automation for Android, powered by small language models (SLMs) running entirely on the phone — no cloud, no internet. A spoken or typed command is mapped to a device-control function call (Do Not Disturb, flashlight, volume, brightness, Wi-Fi, contextual rules).

Built as the experimental platform for an IEEE-style research study on SLMs for on-device voice automation.

- **Runtime:** [Cactus](https://github.com/cactus-compute/cactus) (on-device inference)
- **Platform:** Flutter, Android
- **Test device:** OPPO F25 Pro (MediaTek Dimensity 7050)

## Models

All models run on-device via the Cactus registry and support function calling. Three families are evaluated:

| Family | Models | Notes |
|--------|--------|-------|
| Generalist (Transformer) | Qwen3 0.6B, Qwen3 1.7B | baseline reasoning + tool use |
| Liquid (hybrid-recurrent) | LFM2 350M, 700M, 1.2B | temporal reasoning |
| Specialist | FunctionGemma 270M | function-calling tuned |

The model set is the single source of truth in [`lib/models/agent_model.dart`](lib/models/agent_model.dart).

## How it works

```
Command (typed, or ASR transcription) ──▶ SLM + function-calling tools ──▶ device action
```

The model is given an adaptive system prompt (by family) and the six tool definitions, and must return a function call with parameters. The same tools and prompts drive both the interactive app and the benchmark, so the app behaves exactly as it is measured.

## Quick start

```bash
flutter run --release
```

In the app:
1. Press **Initialize** (downloads the model, ~30s).
2. Press **Request DND Permission**.
3. Type a command, e.g. *"I need silence for 2 hours"*, and press **Send**.
4. Press **Run benchmark** to evaluate all models over the dataset.

## Benchmark

The benchmark runs the evaluation dataset across each model with crash-resistant
incremental saving (results are written after every command, and a crashed run
auto-resumes). It can be launched from the in-app button or headless:

```bash
# all models, default commands each
dart run lib/services/headless_benchmark_runner.dart

# specific models / command count
dart run lib/services/headless_benchmark_runner.dart --models qwen3-0.6,lfm2-350m --commands 120
```

Output:
- `results/headless_benchmark_results.csv` — every test row
- `results/headless_benchmark_summary.md` — per-model summary
- `results/benchmark_progress.json` — resume checkpoint

Each result row records the input mode (`pipeline` = ASR-noisy text, `direct` = clean), the word error rate, the expected vs. actual function and parameters, and latency.

## Project structure

```
lib/
├─ main.dart                          app entry
├─ screens/
│  └─ home_screen.dart                interactive UI
├─ services/
│  ├─ agent_service.dart              owns the model; command → tool calls
│  ├─ device_executor.dart            executes tool calls + manages rules
│  ├─ headless_benchmark_runner.dart  crash-resistant benchmark
│  └─ benchmark_service.dart          result/dataset data classes
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
