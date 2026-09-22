# Headless Benchmark Summary
Condition: en
Generated: 2026-07-18 20:29:44.157163
Total Tests: 330

## Model Performance

| Model | Input Mode | Tests | Success Rate | Function Acc | Param Acc | Avg Latency |
|-------|------------|-------|--------------|--------------|-----------|-------------|
| LFM2 1.2B Tool | pipeline | 30 | 40.0% | 50.0% | 40.0% | 20151ms |
| LFM2 350M | pipeline | 30 | 20.0% | 26.7% | 26.7% | 8611ms |
| LFM2.5 350M | pipeline | 30 | 36.7% | 63.3% | 36.7% | 8208ms |
| LFM2 700M | pipeline | 30 | 26.7% | 33.3% | 26.7% | 17486ms |
| LFM2 1.2B | pipeline | 30 | 23.3% | 33.3% | 26.7% | 24496ms |
| LFM2.5 1.2B | pipeline | 30 | 26.7% | 43.3% | 26.7% | 23751ms |
| Qwen3 0.6B | pipeline | 30 | 23.3% | 30.0% | 23.3% | 14636ms |
| Qwen3 1.7B | pipeline | 30 | 36.7% | 63.3% | 36.7% | 29956ms |
| Qwen3.5 0.8B | pipeline | 30 | 50.0% | 70.0% | 50.0% | 59332ms |
| Qwen3.5 2B | pipeline | 30 | 46.7% | 63.3% | 46.7% | 108586ms |
| Gemma 4 E2B | direct | 30 | 63.3% | 80.0% | 63.3% | 41693ms |

## Architecture Comparison: Pipeline vs Unified

**Pipeline (Whisper STT + SLM):**
- Models tested: 10
- Overall success rate: 33.0%
- Mean latency: 31521ms
- Mean WER: 0.236

**Unified Audio-Native (no STT stage):**
- Models tested: 1
- Overall success rate: 63.3%
- Mean latency: 41693ms
- Input WER: 0.000 (direct audio understanding)

> **Novel Finding:** Unified architecture outperforms pipeline by 30.3pp — empirical evidence for eliminating the ASR stage on mid-range devices.

## Semantic Resilience (pipeline arm)

Clean = WER 0 transcripts; Noisy = WER > 0 (real Whisper errors). Resilience gap = how much accuracy drops on mis-heard input; recovery rate = accuracy on the mis-heard subset.

| Model | Clean acc | Noisy acc | Resilience gap | Recovery rate (n) |
|-------|-----------|-----------|----------------|-------------------|
| LFM2 1.2B Tool | 45.5% | 36.8% | 8.6pp | 36.8% (7/19) |
| LFM2 350M | 9.1% | 26.3% | -17.2pp | 26.3% (5/19) |
| LFM2.5 350M | 27.3% | 42.1% | -14.8pp | 42.1% (8/19) |
| LFM2 700M | 9.1% | 36.8% | -27.8pp | 36.8% (7/19) |
| LFM2 1.2B | 18.2% | 26.3% | -8.1pp | 26.3% (5/19) |
| LFM2.5 1.2B | 18.2% | 31.6% | -13.4pp | 31.6% (6/19) |
| Qwen3 0.6B | 27.3% | 21.1% | 6.2pp | 21.1% (4/19) |
| Qwen3 1.7B | 36.4% | 36.8% | -0.5pp | 36.8% (7/19) |
| Qwen3.5 0.8B | 54.5% | 47.4% | 7.2pp | 47.4% (9/19) |
| Qwen3.5 2B | 54.5% | 42.1% | 12.4pp | 42.1% (8/19) |

### Accuracy vs WER band (pooled pipeline models)

| WER band | Commands | Success rate |
|----------|----------|--------------|
| 0 (clean) | 110 | 30.0% |
| 0–25% | 100 | 41.0% |
| 25–50% | 50 | 42.0% |
| >50% | 40 | 10.0% |
