"""§III-G statistical tests + supporting analyses for paper_v2.

Reads analysis/all_rows.csv (from build_dataset.py).
Writes analysis/stats.json (machine-readable, feeds tables/figures)
and prints a human-readable report.
"""

import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats as sps
from statsmodels.stats.contingency_tables import mcnemar, cochrans_q

ROOT = Path(__file__).resolve().parent
df = pd.read_csv(ROOT / "all_rows.csv")

OUT = {}

PIPELINE_MODELS = [
    "LFM2 350M", "LFM2.5 350M", "LFM2 700M", "LFM2 1.2B", "LFM2.5 1.2B",
    "LFM2 1.2B Tool", "Qwen3 0.6B", "Qwen3 1.7B", "Qwen3.5 0.8B", "Qwen3.5 2B",
]
GEMMA = "Gemma 4 E2B"


def per_clip(cond, model, arm=None):
    q = df[(df.condition == cond) & (df.model == model)]
    if arm:
        q = q[q.arm == arm]
    return q.sort_values("clip_idx").set_index("clip_idx")["success"]


def mcnemar_pair(a: pd.Series, b: pd.Series, exact=True):
    """a,b: aligned binary series. Returns dict with table + p."""
    idx = a.index.intersection(b.index)
    a, b = a.loc[idx], b.loc[idx]
    n01 = int(((a == 0) & (b == 1)).sum())  # a fails, b succeeds
    n10 = int(((a == 1) & (b == 0)).sum())
    n11 = int(((a == 1) & (b == 1)).sum())
    n00 = int(((a == 0) & (b == 0)).sum())
    tbl = [[n11, n10], [n01, n00]]
    res = mcnemar(tbl, exact=exact)
    return {"n11": n11, "n10": n10, "n01": n01, "n00": n00,
            "statistic": float(res.statistic), "p": float(res.pvalue)}


# ---------------------------------------------------------------- 1. headline
print("=" * 70)
print("1. PIPELINE vs DIRECT (McNemar, per-clip paired, Main n=30)")
gem = per_clip("main_en", GEMMA)
OUT["mcnemar_main"] = {}
for name in ["Qwen3.5 0.8B", "Qwen3.5 2B"]:
    m = mcnemar_pair(per_clip("main_en", name), gem)
    OUT["mcnemar_main"][name] = m
    print(f"  Gemma vs {name:14s}: gemma-only wins={m['n01']}, "
          f"{name}-only wins={m['n10']}, both={m['n11']}, neither={m['n00']}, "
          f"exact p={m['p']:.4f}")

# within-model ablation: Gemma direct vs Gemma-fed-transcripts, per condition
print("\n1b. WITHIN-MODEL ABLATION (Gemma direct vs transcript-fed)")
OUT["mcnemar_ablation"] = {}
for cond, abl_cond in [("main_en", "ablation_en"),
                       ("pilot_en", "ablation_pilot_en"),
                       ("pilot_cs", "ablation_cs")]:
    d = per_clip(cond, GEMMA)
    a = per_clip(abl_cond, GEMMA)
    m = mcnemar_pair(d, a)
    OUT["mcnemar_ablation"][cond] = m
    print(f"  {cond:9s}: direct-only wins={m['n10']}, text-only wins={m['n01']}, "
          f"both={m['n11']}, neither={m['n00']}, exact p={m['p']:.4f}")

# pooled ablation across all 54 paired clips
d_all = pd.concat([per_clip(c, GEMMA).rename(lambda i: f"{c}_{i}")
                   for c in ["main_en", "pilot_en", "pilot_cs"]])
a_all = pd.concat([per_clip(c, GEMMA).rename(lambda i: f"{c2}_{i}")
                   for c, c2 in [("ablation_en", "main_en"),
                                 ("ablation_pilot_en", "pilot_en"),
                                 ("ablation_cs", "pilot_cs")]])
m = mcnemar_pair(d_all, a_all)
OUT["mcnemar_ablation"]["pooled"] = m
print(f"  pooled 54: direct-only={m['n10']}, text-only={m['n01']}, "
      f"both={m['n11']}, neither={m['n00']}, exact p={m['p']:.4f}")

# ------------------------------------------------------------- 2. Cochran's Q
print("\n2. MODEL EFFECT WITHIN PIPELINE ARM (Cochran's Q, Main)")
mat = np.column_stack([per_clip("main_en", m).values for m in PIPELINE_MODELS])
q = cochrans_q(mat)
OUT["cochrans_q"] = {"Q": float(q.statistic), "df": len(PIPELINE_MODELS) - 1,
                     "p": float(q.pvalue)}
print(f"  Q={q.statistic:.2f}, df={len(PIPELINE_MODELS)-1}, p={q.pvalue:.5f}")

# post-hoc pairwise McNemar with Holm correction
pairs, ps = [], []
for i in range(len(PIPELINE_MODELS)):
    for j in range(i + 1, len(PIPELINE_MODELS)):
        a = per_clip("main_en", PIPELINE_MODELS[i])
        b = per_clip("main_en", PIPELINE_MODELS[j])
        m = mcnemar_pair(a, b)
        pairs.append((PIPELINE_MODELS[i], PIPELINE_MODELS[j], m["p"]))
        ps.append(m["p"])
order = np.argsort(ps)
holm_sig = []
n_p = len(ps)
for rank, k in enumerate(order):
    adj = ps[k] * (n_p - rank)
    if adj < 0.05:
        holm_sig.append((pairs[k][0], pairs[k][1], ps[k], min(adj, 1.0)))
    else:
        break
OUT["posthoc_holm_significant"] = holm_sig
print(f"  post-hoc: {len(holm_sig)} of {n_p} pairs significant after Holm")
for a, b, p, adj in holm_sig:
    print(f"    {a} vs {b}: raw p={p:.4f}, Holm-adj={adj:.4f}")

# ------------------------------------------------------------- 3. Spearman
print("\n3. SEMANTIC RESILIENCE (Spearman WER vs success, pipeline Main)")
pl = df[(df.condition == "main_en") & (df.arm == "pipeline")]
rho, p = sps.spearmanr(pl.wer_norm, pl.success)
OUT["spearman_pooled"] = {"rho": float(rho), "p": float(p), "n": len(pl)}
print(f"  pooled: rho={rho:.3f}, p={p:.5f}, n={len(pl)}")
OUT["spearman_per_model"] = {}
for m in PIPELINE_MODELS:
    sub = pl[pl.model == m]
    rho, p = sps.spearmanr(sub.wer_norm, sub.success)
    OUT["spearman_per_model"][m] = {"rho": float(rho), "p": float(p)}

# --------------------------------------------------------------- 4. category
print("\n4. CATEGORY EFFECT (chi-square, pipeline Main)")
ct = pd.crosstab(pl.category, pl.success)
chi2, p, dof, _ = sps.chi2_contingency(ct)
OUT["chi2_category"] = {"chi2": float(chi2), "df": int(dof), "p": float(p),
                        "table": ct.to_dict()}
print(f"  chi2={chi2:.2f}, df={dof}, p={p:.5f}")
print(ct.assign(rate=lambda d: (d[1] / (d[0] + d[1])).round(3)))

# ------------------------------------------- 4b. category-controlled resilience
print("\n4b. CATEGORY-CONTROLLED RESILIENCE (logistic: success ~ wer + category)")
import statsmodels.formula.api as smf
pl2 = pl.copy()
pl2["clean"] = (pl2.wer_norm == 0).astype(int)
# naive (confounded) gap
naive_clean = pl2[pl2.clean == 1].success.mean()
naive_noisy = pl2[pl2.clean == 0].success.mean()
logit = smf.logit("success ~ wer_norm + C(category) + C(model)", data=pl2).fit(disp=0)
OUT["logit_wer"] = {
    "coef_wer": float(logit.params["wer_norm"]),
    "p_wer": float(logit.pvalues["wer_norm"]),
    "naive_clean_acc": float(naive_clean), "naive_noisy_acc": float(naive_noisy),
}
print(f"  naive clean acc={naive_clean:.3f} vs noisy acc={naive_noisy:.3f} "
      f"(confounded by category mix)")
print(f"  logit success ~ wer_norm + category + model: "
      f"beta_wer={logit.params['wer_norm']:.2f}, p={logit.pvalues['wer_norm']:.4f}")
# category composition of clean vs noisy clips
comp = pd.crosstab(pl2.category, pl2.clean, normalize="columns").round(3)
print("  category mix (cols: noisy=0, clean=1):")
print(comp)
OUT["category_mix_clean_noisy"] = comp.to_dict()

# --------------------------------------------------------------- 5. pilot
print("\n5. CODE-SWITCH PILOT (exact McNemar EN vs CS, n=12, per model)")
OUT["mcnemar_pilot"] = {}
for m in PIPELINE_MODELS + [GEMMA]:
    en = per_clip("pilot_en", m)
    cs = per_clip("pilot_cs", m)
    r = mcnemar_pair(en, cs)
    OUT["mcnemar_pilot"][m] = r
# pooled pipeline
en_all = pd.concat([per_clip("pilot_en", m).rename(lambda i: f"{m}_{i}")
                    for m in PIPELINE_MODELS])
cs_all = pd.concat([per_clip("pilot_cs", m).rename(lambda i: f"{m}_{i}")
                    for m in PIPELINE_MODELS])
r = mcnemar_pair(en_all, cs_all)
OUT["mcnemar_pilot"]["pipeline_pooled"] = r
print(f"  pipeline pooled (120 paired): EN-only wins={r['n10']}, "
      f"CS-only wins={r['n01']}, exact p={r['p']:.5f}")
g = OUT["mcnemar_pilot"][GEMMA]
print(f"  Gemma direct: EN-only={g['n10']}, CS-only={g['n01']} (12/12 both) "
      f"p={g['p']:.3f}")

# ----------------------------------------------------- 6. IV-C cross-tab
print("\n6. CROSS-TAB: where does the direct arm's advantage live? (Main)")
best = per_clip("main_en", "Qwen3.5 0.8B")
gemd = per_clip("main_en", GEMMA)
wer_by_clip = (df[(df.condition == "main_en") & (df.arm == "pipeline")]
               .groupby("clip_idx").wer_norm.first())
# NB: bracket access throughout — "pipe" collides with DataFrame.pipe()
tab = pd.DataFrame({"pipe": best, "gem": gemd, "wer": wer_by_clip})
tab["clean"] = tab["wer"] == 0
xt = {}
for clean in (True, False):
    sub = tab[tab["clean"] == clean]
    xt["clean" if clean else "noisy"] = {
        "n": len(sub),
        "pipe_fail_gem_win": int(((sub["pipe"] == 0) & (sub["gem"] == 1)).sum()),
        "pipe_win_gem_fail": int(((sub["pipe"] == 1) & (sub["gem"] == 0)).sum()),
        "both_win": int(((sub["pipe"] == 1) & (sub["gem"] == 1)).sum()),
        "both_fail": int(((sub["pipe"] == 0) & (sub["gem"] == 0)).sum()),
    }
OUT["crosstab_best_vs_gemma"] = xt
print(json.dumps(xt, indent=2))

# pipeline failures split by cause proxy: failed on clean vs noisy transcript
fails = pl[pl.success == 0]
OUT["pipeline_fail_split"] = {
    "n_fail": len(fails),
    "fail_on_clean": int((fails.wer_norm == 0).sum()),
    "fail_on_noisy": int((fails.wer_norm > 0).sum()),
}

# ------------------------------------ 7. unit-of-analysis corrected tests
# The 300 Main pipeline rows are 30 clips x 10 models, and WER and category
# are clip properties, so tests pooled over rows overstate n. Re-run with the
# clip (or the model) as the unit.
import statsmodels.formula.api as smf

clip = pl.groupby("clip_idx").agg(cat=("category", "first"),
                                  succ=("success", "mean"),
                                  wer=("wer_norm", "first"))
H, p = sps.kruskal(*[g.succ.values for _, g in clip.groupby("cat")])
OUT["category_clip_level"] = {"H": float(H), "df": clip.cat.nunique() - 1,
                              "p": float(p), "n_clips": len(clip),
                              "mean_success": clip.groupby("cat").succ.mean().round(2).to_dict()}

rho, p = sps.spearmanr(clip.wer, clip.succ)
OUT["spearman_clip_level"] = {"rho": float(rho), "p": float(p), "n": len(clip)}

neg = sum(1 for v in OUT["spearman_per_model"].values() if v["rho"] < 0)
OUT["wer_sign_test_models"] = {"negative": neg, "n": len(PIPELINE_MODELS),
                               "p": float(sps.binomtest(neg, len(PIPELINE_MODELS)).pvalue)}

clustered = smf.logit("success ~ wer_norm + C(category) + C(model)", data=pl).fit(
    disp=0, cov_type="cluster", cov_kwds={"groups": pl.clip_idx})
OUT["logit_wer_clip_clustered"] = {"coef_wer": float(clustered.params["wer_norm"]),
                                   "p_wer": float(clustered.pvalues["wer_norm"])}

# code-switched pilot: models as the unit, then intents as the unit
mp = OUT["mcnemar_pilot"]
drop = sum(1 for m in PIPELINE_MODELS if mp[m]["n10"] > mp[m]["n01"])
rise = sum(1 for m in PIPELINE_MODELS if mp[m]["n10"] < mp[m]["n01"])
en = df[(df.condition == "pilot_en") & (df.arm == "pipeline")].groupby("clip_idx").success.mean()
cs = df[(df.condition == "pilot_cs") & (df.arm == "pipeline")].groupby("clip_idx").success.mean()
worse, better = int((en > cs).sum()), int((en < cs).sum())
OUT["codeswitch_sign_tests"] = {
    "models_drop": drop, "models_rise": rise,
    "p_models": float(sps.binomtest(drop, drop + rise).pvalue),
    "intents_worse": worse, "intents_better": better, "intents_tied": int((en == cs).sum()),
    "p_intents": float(sps.binomtest(worse, worse + better).pvalue),
}
# ------------------------------------------ 8. Wilson 95% CIs, Main success
from statsmodels.stats.proportion import proportion_confint

OUT["wilson_ci_main"] = {}
for m in PIPELINE_MODELS + [GEMMA]:
    s = df[(df.condition == "main_en") & (df.model == m)].success
    lo, hi = proportion_confint(int(s.sum()), len(s), method="wilson")
    OUT["wilson_ci_main"][m] = {"k": int(s.sum()), "n": len(s), "lo": lo, "hi": hi}
s = df[df.condition == "ablation_en"].success
lo, hi = proportion_confint(int(s.sum()), len(s), method="wilson")
OUT["wilson_ci_main"]["Gemma 4 E2B (transcripts)"] = {"k": int(s.sum()), "n": len(s), "lo": lo, "hi": hi}

print(json.dumps({k: OUT[k] for k in ["category_clip_level", "spearman_clip_level",
                                      "wer_sign_test_models", "logit_wer_clip_clustered",
                                      "codeswitch_sign_tests"]}, indent=2))

with (ROOT / "stats.json").open("w") as f:
    json.dump(OUT, f, indent=2, default=str)
print("\nwrote stats.json")
