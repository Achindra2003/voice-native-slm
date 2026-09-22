# Headless Benchmark Summary
Condition: ablation_pilot_en
Generated: 2026-07-19 21:32:46.657946
Total Tests: 12

## Model Performance

| Model | Input Mode | Tests | Success Rate | Function Acc | Param Acc | Avg Latency |
|-------|------------|-------|--------------|--------------|-----------|-------------|
| Gemma 4 E2B | pipeline | 12 | 58.3% | 58.3% | 66.7% | 16465ms |

## Architecture Comparison: Pipeline vs Unified

**Pipeline (Whisper STT + SLM):**
- Models tested: 1
- Overall success rate: 58.3%
- Mean latency: 16465ms
- Mean WER: 0.292


## Semantic Resilience (pipeline arm)

Clean = WER 0 transcripts; Noisy = WER > 0 (real Whisper errors). Resilience gap = how much accuracy drops on mis-heard input; recovery rate = accuracy on the mis-heard subset.

| Model | Clean acc | Noisy acc | Resilience gap | Recovery rate (n) |
|-------|-----------|-----------|----------------|-------------------|
| Gemma 4 E2B | 66.7% | 55.6% | 11.1pp | 55.6% (5/9) |

### Accuracy vs WER band (pooled pipeline models)

| WER band | Commands | Success rate |
|----------|----------|--------------|
| 0 (clean) | 3 | 66.7% |
| 0–25% | 4 | 50.0% |
| 25–50% | 3 | 66.7% |
| >50% | 2 | 50.0% |
