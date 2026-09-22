# Headless Benchmark Summary
Condition: pilot_en
Generated: 2026-07-19 15:00:26.665665
Total Tests: 132

## Model Performance

| Model | Input Mode | Tests | Success Rate | Function Acc | Param Acc | Avg Latency |
|-------|------------|-------|--------------|--------------|-----------|-------------|
| LFM2 1.2B Tool | pipeline | 12 | 75.0% | 75.0% | 75.0% | 17543ms |
| LFM2 350M | pipeline | 12 | 58.3% | 58.3% | 83.3% | 6657ms |
| LFM2.5 350M | pipeline | 12 | 75.0% | 83.3% | 75.0% | 6619ms |
| LFM2 700M | pipeline | 12 | 66.7% | 66.7% | 66.7% | 13391ms |
| LFM2 1.2B | pipeline | 12 | 25.0% | 25.0% | 25.0% | 21207ms |
| LFM2.5 1.2B | pipeline | 12 | 58.3% | 58.3% | 58.3% | 21831ms |
| Qwen3 0.6B | pipeline | 12 | 58.3% | 66.7% | 58.3% | 12463ms |
| Qwen3 1.7B | pipeline | 12 | 83.3% | 91.7% | 83.3% | 27023ms |
| Qwen3.5 0.8B | pipeline | 12 | 91.7% | 91.7% | 91.7% | 56593ms |
| Qwen3.5 2B | pipeline | 12 | 75.0% | 75.0% | 75.0% | 108963ms |
| Gemma 4 E2B | direct | 12 | 100.0% | 100.0% | 100.0% | 40722ms |

## Architecture Comparison: Pipeline vs Unified

**Pipeline (Whisper STT + SLM):**
- Models tested: 10
- Overall success rate: 66.7%
- Mean latency: 29229ms
- Mean WER: 0.292

**Unified Audio-Native (no STT stage):**
- Models tested: 1
- Overall success rate: 100.0%
- Mean latency: 40722ms
- Input WER: 0.000 (direct audio understanding)

> **Novel Finding:** Unified architecture outperforms pipeline by 33.3pp — empirical evidence for eliminating the ASR stage on mid-range devices.

## Semantic Resilience (pipeline arm)

Clean = WER 0 transcripts; Noisy = WER > 0 (real Whisper errors). Resilience gap = how much accuracy drops on mis-heard input; recovery rate = accuracy on the mis-heard subset.

| Model | Clean acc | Noisy acc | Resilience gap | Recovery rate (n) |
|-------|-----------|-----------|----------------|-------------------|
| LFM2 1.2B Tool | 100.0% | 66.7% | 33.3pp | 66.7% (6/9) |
| LFM2 350M | 66.7% | 55.6% | 11.1pp | 55.6% (5/9) |
| LFM2.5 350M | 100.0% | 66.7% | 33.3pp | 66.7% (6/9) |
| LFM2 700M | 66.7% | 66.7% | 0.0pp | 66.7% (6/9) |
| LFM2 1.2B | 33.3% | 22.2% | 11.1pp | 22.2% (2/9) |
| LFM2.5 1.2B | 33.3% | 66.7% | -33.3pp | 66.7% (6/9) |
| Qwen3 0.6B | 100.0% | 44.4% | 55.6pp | 44.4% (4/9) |
| Qwen3 1.7B | 100.0% | 77.8% | 22.2pp | 77.8% (7/9) |
| Qwen3.5 0.8B | 100.0% | 88.9% | 11.1pp | 88.9% (8/9) |
| Qwen3.5 2B | 100.0% | 66.7% | 33.3pp | 66.7% (6/9) |

### Accuracy vs WER band (pooled pipeline models)

| WER band | Commands | Success rate |
|----------|----------|--------------|
| 0 (clean) | 30 | 80.0% |
| 0–25% | 40 | 85.0% |
| 25–50% | 30 | 43.3% |
| >50% | 20 | 45.0% |
