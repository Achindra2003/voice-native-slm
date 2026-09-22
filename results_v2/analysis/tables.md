## TABLE I — Whisper-base transcription quality by condition

| Condition | Clips | Mean WER | Median WER | % WER=0 | % WER>0.25 |
|---|---|---|---|---|---|
| English (main) | 30 | 0.214 | 0.155 | 43.3 | 26.7 |
| English (pilot) | 12 | 0.214 | 0.083 | 50.0 | 25.0 |
| Code-switched (pilot) | 12 | 0.736 | 1.000 | 0.0 | 83.3 |

### Verbatim Whisper errors (main_en, for §IV-A prose)
- [26] "Brighten screen" -> "Right-end screen." (WER 1.00)
- [15] "Torch off please" -> "Dorch of please." (WER 0.67)
- [16] "Make screen brighter" -> "Mix green brighter." (WER 0.67)
- [11] "Turn off alerts while exercising" -> "Don't over load while exercising." (WER 0.60)
- [20] "Brighten screen" -> "Brightens screen." (WER 0.50)
- [13] "Set brightness for reading" -> "said rightness for reading." (WER 0.50)
- [28] "Phone settings for meditation" -> "Phone setting to meditation." (WER 0.50)
- [0] "Turn off flashlight" -> "Turn off the flashlight." (WER 0.33)

## TABLE II — Aggregate performance, pipeline arm (Main, n=30 each)

| Model | Params | Success % | Function % | Param % | Median lat (s) | p95 lat (s) |
|---|---|---|---|---|---|---|
| LFM2 350M | 350M | 20.0 | 26.7 | 26.7 | 8.4 | 10.2 |
| LFM2.5 350M | 350M | 36.7 | 63.3 | 36.7 | 7.8 | 10.5 |
| LFM2 700M | 700M | 26.7 | 33.3 | 26.7 | 18.0 | 20.5 |
| LFM2 1.2B | 1.2B | 23.3 | 33.3 | 26.7 | 22.5 | 30.3 |
| LFM2.5 1.2B | 1.2B | 26.7 | 43.3 | 26.7 | 23.4 | 26.5 |
| LFM2 1.2B Tool | 1.2B | 40.0 | 50.0 | 40.0 | 18.9 | 24.7 |
| Qwen3 0.6B | 0.6B | 23.3 | 30.0 | 23.3 | 13.9 | 18.5 |
| Qwen3 1.7B | 1.7B | 36.7 | 63.3 | 36.7 | 27.1 | 45.5 |
| Qwen3.5 0.8B | 0.8B | 50.0 | 70.0 | 50.0 | 57.9 | 71.9 |
| Qwen3.5 2B | 2B | 46.7 | 63.3 | 46.7 | 107.7 | 114.8 |
| **Gemma 4 E2B (direct)** | ~2B eff. | 63.3 | 80.0 | 63.3 | 40.8 | 51.3 |

## TABLE III — Pipeline vs direct on matched audio (Main) + within-model ablation

| System | Success % | Function % | Param % | Median lat (s) |
|---|---|---|---|---|
| Best pipeline (Qwen3.5 0.8B) | 50.0 | 70.0 | 50.0 | 57.9 |
| Size-matched pipeline (Qwen3.5 2B) | 46.7 | 63.3 | 46.7 | 107.7 |
| Pipeline mean (10 models) | 33.0 | 47.7 | 34.0 | 22.0 |
| Gemma-4-E2B fed transcripts (ablation) | 43.3 | 50.0 | 43.3 | 13.0 |
| Gemma-4-E2B direct audio | 63.3 | 80.0 | 63.3 | 40.8 |

### Ablation across all three conditions (within-model, same weights)

| Condition | Direct audio | Transcript-fed | Delta pp | Exact McNemar p |
|---|---|---|---|---|
| Main English (30) | 63.3 | 43.3 | +20.0 | 0.0703 |
| Pilot English (12) | 100.0 | 58.3 | +41.7 | 0.0625 |
| Code-switched (12) | 100.0 | 41.7 | +58.3 | 0.0156 |
| **Pooled (54)** | — | — | — | **4.01e-05** (19 vs 1 discordant) |

### IV-C cross-tabulation: Gemma vs best pipeline by transcript state

| Transcript state | n clips | Gemma only | Pipeline only | Both | Neither |
|---|---|---|---|---|---|
| Clean (WER=0) | 13 | 1 | 1 | 7 | 4 |
| Noisy (WER>0) | 17 | 5 | 1 | 6 | 5 |

## TABLE IV — Clean vs noisy accuracy per pipeline model (Main, normalized WER)

| Model | Clean acc % (n) | Noisy acc % (n) | Gap pp | Recovery rate % |
|---|---|---|---|---|
| LFM2 350M | 15.4 (13) | 23.5 (17) | -8.1 | 23.5 |
| LFM2.5 350M | 38.5 (13) | 35.3 (17) | +3.2 | 35.3 |
| LFM2 700M | 23.1 (13) | 29.4 (17) | -6.3 | 29.4 |
| LFM2 1.2B | 23.1 (13) | 23.5 (17) | -0.5 | 23.5 |
| LFM2.5 1.2B | 23.1 (13) | 29.4 (17) | -6.3 | 29.4 |
| LFM2 1.2B Tool | 53.8 (13) | 29.4 (17) | +24.4 | 29.4 |
| Qwen3 0.6B | 23.1 (13) | 23.5 (17) | -0.5 | 23.5 |
| Qwen3 1.7B | 38.5 (13) | 35.3 (17) | +3.2 | 35.3 |
| Qwen3.5 0.8B | 61.5 (13) | 41.2 (17) | +20.4 | 41.2 |
| Qwen3.5 2B | 53.8 (13) | 41.2 (17) | +12.7 | 41.2 |
| **Pooled** | 35.4 (130) | 31.2 (170) | +4.2 | 31.2 |

Category+model-controlled logistic regression: beta_WER = -1.59; p = 0.112 with standard errors clustered by clip (p = 0.0181 if the 300 trials are wrongly treated as independent). WER-success correlation negative in 9 of 10 models (sign test p = 0.021): consistent with a negative WER effect, not confirmed at n = 30 clips.

## TABLE V — Success rate by WER band, pooled pipeline (Main)

| WER band | n tests | Success % |
|---|---|---|
| 0 (clean) | 130 | 35.4 |
| 0-0.25 | 90 | 41.1 |
| 0.25-0.50 | 40 | 30.0 |
| >0.50 | 40 | 10.0 |

## TABLE VI — English vs code-switched, matched intents (12 each)

| System | EN success | CS success | Delta pp | EN mean WER | CS mean WER |
|---|---|---|---|---|---|
| Pipeline mean (10 models) | 66.7 | 45.8 | -20.8 | 0.214 | 0.736 |
| Best pipeline (Qwen3.5 0.8B) | 91.7 | 66.7 | -25.0 | 0.214 | 0.736 |
| Gemma-4-E2B fed transcripts (ablation) | 58.3 | 41.7 | -16.7 | 0.214 | 0.736 |
| Gemma-4-E2B direct audio | 100.0 | 100.0 | +0.0 | 0.214 | 0.736 |

Pipeline models losing accuracy EN -> CS: 9 of 10 (sign test p = 0.021); across the 12 intents: 7 worse, 3 better, 2 tied (sign test p = 0.34). Gemma direct: 12/12 in both registers (no discordant pairs).

## Supporting: success by category x model (Main, pipeline + direct)

| model          |   contextual |   direct |   parameter |   rule |   temporal |
|:---------------|-------------:|---------:|------------:|-------:|-----------:|
| LFM2 350M      |        0     |      0   |           0 |  0     |      0.857 |
| LFM2.5 350M    |        0.111 |      0.3 |           1 |  0     |      0.857 |
| LFM2 700M      |        0     |      0.1 |           1 |  0     |      0.857 |
| LFM2 1.2B      |        0.111 |      0   |           0 |  0     |      0.857 |
| LFM2.5 1.2B    |        0.111 |      0.1 |           0 |  0     |      0.857 |
| LFM2 1.2B Tool |        0     |      0.5 |           1 |  0     |      0.857 |
| Qwen3 0.6B     |        0     |      0.4 |           0 |  0.333 |      0.286 |
| Qwen3 1.7B     |        0     |      0.5 |           1 |  0.333 |      0.571 |
| Qwen3.5 0.8B   |        0.222 |      0.6 |           1 |  0     |      0.857 |
| Qwen3.5 2B     |        0.222 |      0.6 |           0 |  0     |      0.857 |
| Gemma 4 E2B    |        0.111 |      0.9 |           1 |  0.333 |      1     |
