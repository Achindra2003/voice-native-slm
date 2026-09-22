# Headless Benchmark Summary
Condition: ablation_en
Generated: 2026-07-19 21:29:07.760601
Total Tests: 30

## Model Performance

| Model | Input Mode | Tests | Success Rate | Function Acc | Param Acc | Avg Latency |
|-------|------------|-------|--------------|--------------|-----------|-------------|
| Gemma 4 E2B | pipeline | 30 | 43.3% | 50.0% | 43.3% | 14612ms |

## Architecture Comparison: Pipeline vs Unified

**Pipeline (Whisper STT + SLM):**
- Models tested: 1
- Overall success rate: 43.3%
- Mean latency: 14612ms
- Mean WER: 0.236


## Semantic Resilience (pipeline arm)

Clean = WER 0 transcripts; Noisy = WER > 0 (real Whisper errors). Resilience gap = how much accuracy drops on mis-heard input; recovery rate = accuracy on the mis-heard subset.

| Model | Clean acc | Noisy acc | Resilience gap | Recovery rate (n) |
|-------|-----------|-----------|----------------|-------------------|
| Gemma 4 E2B | 27.3% | 52.6% | -25.4pp | 52.6% (10/19) |

### Accuracy vs WER band (pooled pipeline models)

| WER band | Commands | Success rate |
|----------|----------|--------------|
| 0 (clean) | 11 | 27.3% |
| 0–25% | 10 | 60.0% |
| 25–50% | 5 | 40.0% |
| >50% | 4 | 50.0% |
