# Headless Benchmark Summary
Condition: ablation_codeswitch
Generated: 2026-07-19 21:36:44.678264
Total Tests: 12

## Model Performance

| Model | Input Mode | Tests | Success Rate | Function Acc | Param Acc | Avg Latency |
|-------|------------|-------|--------------|--------------|-----------|-------------|
| Gemma 4 E2B | pipeline | 12 | 41.7% | 50.0% | 41.7% | 18097ms |

## Architecture Comparison: Pipeline vs Unified

**Pipeline (Whisper STT + SLM):**
- Models tested: 1
- Overall success rate: 41.7%
- Mean latency: 18097ms
- Mean WER: 0.807


## Semantic Resilience (pipeline arm)

Clean = WER 0 transcripts; Noisy = WER > 0 (real Whisper errors). Resilience gap = how much accuracy drops on mis-heard input; recovery rate = accuracy on the mis-heard subset.

| Model | Clean acc | Noisy acc | Resilience gap | Recovery rate (n) |
|-------|-----------|-----------|----------------|-------------------|
| Gemma 4 E2B | 0.0% | 41.7% | -41.7pp | 41.7% (5/12) |

### Accuracy vs WER band (pooled pipeline models)

| WER band | Commands | Success rate |
|----------|----------|--------------|
| 25–50% | 3 | 66.7% |
| >50% | 9 | 33.3% |
