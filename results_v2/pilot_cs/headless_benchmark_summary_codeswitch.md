# Headless Benchmark Summary
Condition: codeswitch
Generated: 2026-07-19 20:19:26.333432
Total Tests: 132

## Model Performance

| Model | Input Mode | Tests | Success Rate | Function Acc | Param Acc | Avg Latency |
|-------|------------|-------|--------------|--------------|-----------|-------------|
| LFM2 1.2B Tool | pipeline | 12 | 41.7% | 41.7% | 41.7% | 20182ms |
| LFM2 350M | pipeline | 12 | 33.3% | 33.3% | 41.7% | 7945ms |
| LFM2.5 350M | pipeline | 12 | 58.3% | 58.3% | 58.3% | 7608ms |
| LFM2 700M | pipeline | 12 | 41.7% | 41.7% | 41.7% | 17641ms |
| LFM2 1.2B | pipeline | 12 | 33.3% | 33.3% | 33.3% | 24618ms |
| LFM2.5 1.2B | pipeline | 12 | 50.0% | 50.0% | 50.0% | 23089ms |
| Qwen3 0.6B | pipeline | 12 | 33.3% | 33.3% | 33.3% | 14511ms |
| Qwen3 1.7B | pipeline | 12 | 58.3% | 66.7% | 58.3% | 29741ms |
| Qwen3.5 0.8B | pipeline | 12 | 66.7% | 66.7% | 66.7% | 59644ms |
| Qwen3.5 2B | pipeline | 12 | 41.7% | 41.7% | 41.7% | 109224ms |
| Gemma 4 E2B | direct | 12 | 100.0% | 100.0% | 100.0% | 41674ms |

## Architecture Comparison: Pipeline vs Unified

**Pipeline (Whisper STT + SLM):**
- Models tested: 10
- Overall success rate: 45.8%
- Mean latency: 31420ms
- Mean WER: 0.807

**Unified Audio-Native (no STT stage):**
- Models tested: 1
- Overall success rate: 100.0%
- Mean latency: 41674ms
- Input WER: 0.000 (direct audio understanding)

> **Novel Finding:** Unified architecture outperforms pipeline by 54.2pp — empirical evidence for eliminating the ASR stage on mid-range devices.

## Semantic Resilience (pipeline arm)

Clean = WER 0 transcripts; Noisy = WER > 0 (real Whisper errors). Resilience gap = how much accuracy drops on mis-heard input; recovery rate = accuracy on the mis-heard subset.

| Model | Clean acc | Noisy acc | Resilience gap | Recovery rate (n) |
|-------|-----------|-----------|----------------|-------------------|
| LFM2 1.2B Tool | 0.0% | 41.7% | -41.7pp | 41.7% (5/12) |
| LFM2 350M | 0.0% | 33.3% | -33.3pp | 33.3% (4/12) |
| LFM2.5 350M | 0.0% | 58.3% | -58.3pp | 58.3% (7/12) |
| LFM2 700M | 0.0% | 41.7% | -41.7pp | 41.7% (5/12) |
| LFM2 1.2B | 0.0% | 33.3% | -33.3pp | 33.3% (4/12) |
| LFM2.5 1.2B | 0.0% | 50.0% | -50.0pp | 50.0% (6/12) |
| Qwen3 0.6B | 0.0% | 33.3% | -33.3pp | 33.3% (4/12) |
| Qwen3 1.7B | 0.0% | 58.3% | -58.3pp | 58.3% (7/12) |
| Qwen3.5 0.8B | 0.0% | 66.7% | -66.7pp | 66.7% (8/12) |
| Qwen3.5 2B | 0.0% | 41.7% | -41.7pp | 41.7% (5/12) |

### Accuracy vs WER band (pooled pipeline models)

| WER band | Commands | Success rate |
|----------|----------|--------------|
| 25–50% | 30 | 73.3% |
| >50% | 90 | 36.7% |
