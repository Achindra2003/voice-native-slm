"""Generate Tables I-VI (+ supporting) for paper_v2 as markdown -> tables.md."""

import json
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
df = pd.read_csv(ROOT / "all_rows.csv")
stats = json.loads((ROOT / "stats.json").read_text())

PIPELINE = ["LFM2 350M", "LFM2.5 350M", "LFM2 700M", "LFM2 1.2B",
            "LFM2.5 1.2B", "LFM2 1.2B Tool", "Qwen3 0.6B", "Qwen3 1.7B",
            "Qwen3.5 0.8B", "Qwen3.5 2B"]
PARAMS = {"LFM2 350M": "350M", "LFM2.5 350M": "350M", "LFM2 700M": "700M",
          "LFM2 1.2B": "1.2B", "LFM2.5 1.2B": "1.2B", "LFM2 1.2B Tool": "1.2B",
          "Qwen3 0.6B": "0.6B", "Qwen3 1.7B": "1.7B", "Qwen3.5 0.8B": "0.8B",
          "Qwen3.5 2B": "2B", "Gemma 4 E2B": "~2B eff."}
GEMMA = "Gemma 4 E2B"

out = []


def emit(s=""):
    out.append(s)


def pct(x):
    return f"{100*x:.1f}"


# ---------------------------------------------------------------- Table I
emit("## TABLE I — Whisper-base transcription quality by condition")
emit()
emit("| Condition | Clips | Mean WER | Median WER | % WER=0 | % WER>0.25 |")
emit("|---|---|---|---|---|---|")
for cond, label in [("main_en", "English (main)"), ("pilot_en", "English (pilot)"),
                    ("pilot_cs", "Code-switched (pilot)")]:
    w = (df[(df.condition == cond) & (df.arm == "pipeline")]
         .groupby("clip_idx").wer_norm.first())
    emit(f"| {label} | {len(w)} | {w.mean():.3f} | {w.median():.3f} "
         f"| {pct((w==0).mean())} | {pct((w>0.25).mean())} |")
emit()

# example errors for §IV-A prose
emit("### Verbatim Whisper errors (main_en, for §IV-A prose)")
tr = (df[(df.condition == "main_en") & (df.arm == "pipeline")]
      .groupby("clip_idx").first()[["command", "transcript", "wer_norm"]]
      .sort_values("wer_norm", ascending=False))
for i, r in tr.head(8).iterrows():
    emit(f'- [{i}] "{r.command}" -> "{r.transcript}" (WER {r.wer_norm:.2f})')
emit()

# ---------------------------------------------------------------- Table II
emit("## TABLE II — Aggregate performance, pipeline arm (Main, n=30 each)")
emit()
emit("| Model | Params | Success % | Function % | Param % | Median lat (s) | p95 lat (s) |")
emit("|---|---|---|---|---|---|---|")
main_pl = df[(df.condition == "main_en") & (df.arm == "pipeline")]
for m in PIPELINE:
    s = main_pl[main_pl.model == m]
    emit(f"| {m} | {PARAMS[m]} | {pct(s.success.mean())} | "
         f"{pct(s.correct_function.mean())} | {pct(s.correct_params.mean())} | "
         f"{s.latency_ms.median()/1000:.1f} | {s.latency_ms.quantile(.95)/1000:.1f} |")
g = df[(df.condition == "main_en") & (df.model == GEMMA)]
emit(f"| **{GEMMA} (direct)** | {PARAMS[GEMMA]} | {pct(g.success.mean())} | "
     f"{pct(g.correct_function.mean())} | {pct(g.correct_params.mean())} | "
     f"{g.latency_ms.median()/1000:.1f} | {g.latency_ms.quantile(.95)/1000:.1f} |")
emit()

# ---------------------------------------------------------------- Table III
emit("## TABLE III — Pipeline vs direct on matched audio (Main) + within-model ablation")
emit()
emit("| System | Success % | Function % | Param % | Median lat (s) |")
emit("|---|---|---|---|---|")
rows = [
    ("Best pipeline (Qwen3.5 0.8B)", main_pl[main_pl.model == "Qwen3.5 0.8B"]),
    ("Size-matched pipeline (Qwen3.5 2B)", main_pl[main_pl.model == "Qwen3.5 2B"]),
    ("Pipeline mean (10 models)", main_pl),
    ("Gemma-4-E2B fed transcripts (ablation)",
     df[df.condition == "ablation_en"]),
    ("Gemma-4-E2B direct audio", g),
]
for label, s in rows:
    emit(f"| {label} | {pct(s.success.mean())} | {pct(s.correct_function.mean())} | "
         f"{pct(s.correct_params.mean())} | {s.latency_ms.median()/1000:.1f} |")
emit()
emit("### Ablation across all three conditions (within-model, same weights)")
emit()
emit("| Condition | Direct audio | Transcript-fed | Delta pp | Exact McNemar p |")
emit("|---|---|---|---|---|")
for cond, abl, label in [("main_en", "ablation_en", "Main English (30)"),
                         ("pilot_en", "ablation_pilot_en", "Pilot English (12)"),
                         ("pilot_cs", "ablation_cs", "Code-switched (12)")]:
    d = df[(df.condition == cond) & (df.model == GEMMA)].success.mean()
    a = df[df.condition == abl].success.mean()
    p = stats["mcnemar_ablation"][cond]["p"]
    emit(f"| {label} | {pct(d)} | {pct(a)} | +{100*(d-a):.1f} | {float(p):.4f} |")
mp = stats["mcnemar_ablation"]["pooled"]
emit(f"| **Pooled (54)** | — | — | — | **{float(mp['p']):.2e}** "
     f"(19 vs 1 discordant) |")
emit()

# cross-tab
xt = stats["crosstab_best_vs_gemma"]
emit("### IV-C cross-tabulation: Gemma vs best pipeline by transcript state")
emit()
emit("| Transcript state | n clips | Gemma only | Pipeline only | Both | Neither |")
emit("|---|---|---|---|---|---|")
for k, label in [("clean", "Clean (WER=0)"), ("noisy", "Noisy (WER>0)")]:
    v = xt[k]
    emit(f"| {label} | {v['n']} | {v['pipe_fail_gem_win']} | "
         f"{v['pipe_win_gem_fail']} | {v['both_win']} | {v['both_fail']} |")
emit()

# ---------------------------------------------------------------- Table IV
emit("## TABLE IV — Clean vs noisy accuracy per pipeline model (Main, normalized WER)")
emit()
emit("| Model | Clean acc % (n) | Noisy acc % (n) | Gap pp | Recovery rate % |")
emit("|---|---|---|---|---|")
for m in PIPELINE:
    s = main_pl[main_pl.model == m]
    cl = s[s.wer_norm == 0]
    no = s[s.wer_norm > 0]
    emit(f"| {m} | {pct(cl.success.mean())} ({len(cl)}) | "
         f"{pct(no.success.mean())} ({len(no)}) | "
         f"{100*(cl.success.mean()-no.success.mean()):+.1f} | "
         f"{pct(no.success.mean())} |")
cl = main_pl[main_pl.wer_norm == 0]
no = main_pl[main_pl.wer_norm > 0]
emit(f"| **Pooled** | {pct(cl.success.mean())} ({len(cl)}) | "
     f"{pct(no.success.mean())} ({len(no)}) | "
     f"{100*(cl.success.mean()-no.success.mean()):+.1f} | {pct(no.success.mean())} |")
emit()
lg = stats["logit_wer"]
lc = stats["logit_wer_clip_clustered"]
st = stats["wer_sign_test_models"]
emit(f"Category+model-controlled logistic regression: beta_WER = "
     f"{float(lg['coef_wer']):.2f}; p = {float(lc['p_wer']):.3f} with standard errors "
     f"clustered by clip (p = {float(lg['p_wer']):.4f} if the 300 trials are wrongly "
     f"treated as independent). WER-success correlation negative in {st['negative']} of "
     f"{st['n']} models (sign test p = {st['p']:.3f}): consistent with a negative WER "
     "effect, not confirmed at n = 30 clips.")
emit()

# ---------------------------------------------------------------- Table V
emit("## TABLE V — Success rate by WER band, pooled pipeline (Main)")
emit()
emit("| WER band | n tests | Success % |")
emit("|---|---|---|")
bands = [(-0.001, 0.0, "0 (clean)"), (0.0, 0.25, "0-0.25"),
         (0.25, 0.50, "0.25-0.50"), (0.50, 10, ">0.50")]
for lo, hi, label in bands:
    s = main_pl[(main_pl.wer_norm > lo) & (main_pl.wer_norm <= hi)]
    emit(f"| {label} | {len(s)} | {pct(s.success.mean()) if len(s) else '—'} |")
emit()

# ---------------------------------------------------------------- Table VI
emit("## TABLE VI — English vs code-switched, matched intents (12 each)")
emit()
emit("| System | EN success | CS success | Delta pp | EN mean WER | CS mean WER |")
emit("|---|---|---|---|---|---|")


def cond_stats(cond, model=None, arm=None):
    s = df[df.condition == cond]
    if model:
        s = s[s.model == model]
    if arm:
        s = s[s.arm == arm]
    return s


en_wer = cond_stats("pilot_en", arm="pipeline").groupby("clip_idx").wer_norm.first().mean()
cs_wer = cond_stats("pilot_cs", arm="pipeline").groupby("clip_idx").wer_norm.first().mean()
rows6 = [
    ("Pipeline mean (10 models)",
     cond_stats("pilot_en", arm="pipeline").success.mean(),
     cond_stats("pilot_cs", arm="pipeline").success.mean()),
    ("Best pipeline (Qwen3.5 0.8B)",
     cond_stats("pilot_en", "Qwen3.5 0.8B").success.mean(),
     cond_stats("pilot_cs", "Qwen3.5 0.8B").success.mean()),
    ("Gemma-4-E2B fed transcripts (ablation)",
     df[df.condition == "ablation_pilot_en"].success.mean(),
     df[df.condition == "ablation_cs"].success.mean()),
    ("Gemma-4-E2B direct audio",
     cond_stats("pilot_en", GEMMA).success.mean(),
     cond_stats("pilot_cs", GEMMA).success.mean()),
]
for label, e, c in rows6:
    emit(f"| {label} | {pct(e)} | {pct(c)} | {100*(c-e):+.1f} | "
         f"{en_wer:.3f} | {cs_wer:.3f} |")
emit()
cs = stats["codeswitch_sign_tests"]
emit(f"Pipeline models losing accuracy EN -> CS: {cs['models_drop']} of "
     f"{cs['models_drop'] + cs['models_rise']} (sign test p = {cs['p_models']:.3f}); "
     f"across the 12 intents: {cs['intents_worse']} worse, {cs['intents_better']} better, "
     f"{cs['intents_tied']} tied (sign test p = {cs['p_intents']:.2f}). "
     f"Gemma direct: 12/12 in both registers (no discordant pairs).")
emit()

# ------------------------------------------- category table (Fig 5 / prose)
emit("## Supporting: success by category x model (Main, pipeline + direct)")
emit()
cat = (df[df.condition == "main_en"]
       .pivot_table(index="model", columns="category", values="success",
                    aggfunc="mean"))
cat = cat.reindex(PIPELINE + [GEMMA])
emit(cat.round(3).to_markdown())
emit()

(ROOT / "tables.md").write_text("\n".join(out), encoding="utf-8")
print("\n".join(out))
