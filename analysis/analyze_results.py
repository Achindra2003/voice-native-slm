#!/usr/bin/env python3
"""
Turn the pulled on-device benchmark output into every table, statistic, and
figure that paper_v2.md needs (Tables I-VI, the section III-G tests, Figs 1-6).

Usage:
    python analyze_results.py [RESULTS_DIR] [--out OUT_DIR]

RESULTS_DIR (default: ./device_results) is the folder pulled from the phone:
    adb pull /storage/emulated/0/Android/data/com.example.my_agent_app/files/results device_results

Expected files (produced by HeadlessBenchmarkRunner):
    headless_benchmark_results.csv              English run (condition 'en')
    headless_benchmark_results_codeswitch.csv   code-switched pilot (optional)
    transcripts.json                            per-clip Whisper output + WER
    transcripts_codeswitch.json                 (optional)

Outputs into OUT_DIR (default: ./analysis_out):
    tables/table1.md ... table6.md   (+ matching .tex for the LaTeX paper)
    stats.md                         (McNemar, Cochran's Q, Spearman, chi-square)
    crosstab_ivc.md                  (the section IV-C per-clip cross-tabulation)
    figures/fig1_pareto.pdf/.png ... fig6_codeswitch.pdf/.png

Requires: pandas, numpy, scipy, statsmodels, matplotlib
    pip install pandas numpy scipy statsmodels matplotlib
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats as sps

try:
    from statsmodels.stats.contingency_tables import mcnemar, cochrans_q
except ImportError:
    sys.exit("statsmodels missing: pip install statsmodels")

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ── Model registry: id → (params in B, family, pretty name) ────────────────
# Family is the categorical identity for color; size/generation vary within it.
MODELS = {
    "functiongemma-270m": (0.27, "specialist", "FunctionGemma 270M"),
    "lfm2-350m":          (0.35, "hybrid",     "LFM2 350M"),
    "lfm2.5-350m":        (0.35, "hybrid",     "LFM2.5 350M"),
    "lfm2-700m":          (0.70, "hybrid",     "LFM2 700M"),
    "lfm2-1.2b":          (1.20, "hybrid",     "LFM2 1.2B"),
    "qwen3-0.6":          (0.60, "transformer", "Qwen3 0.6B"),
    "qwen3.5-0.8":        (0.80, "transformer", "Qwen3.5 0.8B"),
    "qwen3-1.7":          (1.70, "transformer", "Qwen3 1.7B"),
    "qwen3.5-2b":         (2.00, "transformer", "Qwen3.5 2B"),
    "gemma-4-e2b":        (2.00, "audio",      "Gemma-4 E2B (direct)"),
}
SIZE_MATCHED_PIPELINE = "qwen3.5-2b"  # size-matched control vs the direct arm

# Okabe-Ito (CVD-safe) hues, one per FAMILY — fixed assignment, never cycled.
# Identity is composite: family hue + per-model marker + direct label, so the
# figures survive grayscale printing (IEEE reviewers print B/W).
FAMILY_COLOR = {
    "hybrid":      "#0072B2",  # blue
    "transformer": "#E69F00",  # orange
    "specialist":  "#009E73",  # green
    "audio":       "#D55E00",  # vermillion
}
FAMILY_LABEL = {
    "hybrid": "LFM (hybrid)", "transformer": "Qwen (Transformer)",
    "specialist": "Specialist", "audio": "Audio-native (direct)",
}
MODEL_MARKER = {  # per-model marker within the family hue
    "functiongemma-270m": "P", "lfm2-350m": "o", "lfm2.5-350m": "D",
    "lfm2-700m": "s", "lfm2-1.2b": "^", "qwen3-0.6": "o",
    "qwen3.5-0.8": "D", "qwen3-1.7": "s", "qwen3.5-2b": "^",
    "gemma-4-e2b": "*",
}

plt.rcParams.update({
    "font.size": 8, "axes.titlesize": 9, "axes.labelsize": 8,
    "xtick.labelsize": 7, "ytick.labelsize": 7, "legend.fontsize": 7,
    "figure.dpi": 300, "savefig.bbox": "tight",
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.alpha": 0.25, "grid.linewidth": 0.4,
    "axes.axisbelow": True,
})
IEEE_COL = 3.5   # single-column width, inches
IEEE_FULL = 7.16 # double-column width


# ── Loading ─────────────────────────────────────────────────────────────────
def load_results(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    for col in ("success", "correct_function", "correct_params"):
        df[col] = df[col].astype(str).str.lower().isin(("true", "1"))
    df["word_error_rate"] = pd.to_numeric(df["word_error_rate"], errors="coerce")
    df["latency_ms"] = pd.to_numeric(df["latency_ms"], errors="coerce")
    if "condition" in df.columns:  # drop smoke-test rows if they leaked in
        df = df[df["condition"] != "smoke"]
    df = df[df["model"].isin(MODELS)]
    df["params"] = df["model"].map(lambda m: MODELS[m][0])
    df["family"] = df["model"].map(lambda m: MODELS[m][1])
    df["pretty"] = df["model"].map(lambda m: MODELS[m][2])
    return df


def load_transcripts(path: Path):
    if not path.exists():
        return None
    return pd.DataFrame(json.loads(path.read_text(encoding="utf-8")))


# ── Table emitters ──────────────────────────────────────────────────────────
def emit_table(df: pd.DataFrame, out: Path, name: str, caption: str, label: str,
               floatfmt: str = ".1f"):
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{name}.md").write_text(
        f"**{caption}**\n\n" + df.to_markdown(index=False, floatfmt=floatfmt),
        encoding="utf-8")
    tex = df.to_latex(index=False, float_format=f"%{floatfmt}f".replace("f%", "%"),
                      escape=True)
    (out / f"{name}.tex").write_text(
        "\\begin{table}[t]\n\\centering\n\\caption{%s}\n\\label{%s}\n"
        "\\resizebox{\\columnwidth}{!}{%%\n%s}\n\\end{table}\n"
        % (caption, label, tex), encoding="utf-8")
    print(f"  wrote tables/{name}.md + .tex")


def pct(x) -> float:
    return 100.0 * float(np.mean(x)) if len(x) else float("nan")


# ── Tables I-VI ─────────────────────────────────────────────────────────────
def table1_whisper(tr_en, tr_cs, tables_dir):
    rows = []
    for label, tr in (("English", tr_en), ("Code-switched", tr_cs)):
        if tr is None or tr.empty:
            continue
        rows.append({
            "Condition": label, "Clips": len(tr),
            "Mean WER": round(tr["wer"].mean(), 3),
            "Median WER": round(tr["wer"].median(), 3),
            "% WER=0": round(pct(tr["wer"] == 0), 1),
            "% WER>0.25": round(pct(tr["wer"] > 0.25), 1),
        })
    if rows:
        emit_table(pd.DataFrame(rows), tables_dir, "table1",
                   "Whisper-base transcription quality by condition",
                   "tab:whisper", ".3f")


def table2_pipeline(pipe: pd.DataFrame, tables_dir):
    rows = []
    for m, g in pipe.groupby("model"):
        rows.append({
            "Model": MODELS[m][2], "Params (B)": MODELS[m][0], "n": len(g),
            "Task success %": round(pct(g["success"]), 1),
            "Function acc %": round(pct(g["correct_function"]), 1),
            "Param acc %": round(pct(g["correct_params"]), 1),
            "Median lat. (ms)": int(g["latency_ms"].median()),
            "p95 lat. (ms)": int(g["latency_ms"].quantile(0.95)),
        })
    t = pd.DataFrame(rows).sort_values("Params (B)")
    emit_table(t, tables_dir, "table2",
               "Aggregate performance, pipeline arm (English)", "tab:pipeline")
    return t


def table3_arch(en: pd.DataFrame, tables_dir, stats_lines):
    pipe = en[en["input_mode"] == "pipeline"]
    direct = en[en["input_mode"] == "direct"]
    if direct.empty:
        print("  !! no direct-arm rows found; Table III skipped")
        return
    best = pipe.groupby("model")["success"].mean().idxmax()
    rows = []
    for label, m, g in (
        (f"Best pipeline ({MODELS[best][2]})", best, pipe[pipe.model == best]),
        (f"Size-matched pipeline ({MODELS[SIZE_MATCHED_PIPELINE][2]})",
         SIZE_MATCHED_PIPELINE, pipe[pipe.model == SIZE_MATCHED_PIPELINE]),
        (f"Direct ({MODELS['gemma-4-e2b'][2]})", "gemma-4-e2b", direct),
    ):
        if g.empty:
            continue
        rows.append({
            "System": label,
            "Task success %": round(pct(g["success"]), 1),
            "Function acc %": round(pct(g["correct_function"]), 1),
            "Param acc %": round(pct(g["correct_params"]), 1),
            "Median lat. (ms)": int(g["latency_ms"].median()),
        })
    emit_table(pd.DataFrame(rows), tables_dir, "table3",
               "Pipeline vs.\\ direct on matched audio", "tab:arch")

    # Paired McNemar per pipeline reference, joined on the reference command.
    d = direct.set_index("command")["success"]
    for ref in {best, SIZE_MATCHED_PIPELINE}:
        p = pipe[pipe.model == ref].set_index("command")["success"]
        common = p.index.intersection(d.index)
        if len(common) < 5:
            continue
        a = p.loc[common].astype(int); b = d.loc[common].astype(int)
        tbl = pd.crosstab(a, b).reindex(index=[0, 1], columns=[0, 1], fill_value=0)
        res = mcnemar(tbl.values, exact=True)
        stats_lines.append(
            f"- **McNemar (paired, n={len(common)}) — direct vs {MODELS[ref][2]}:** "
            f"pipeline-only wins={tbl.values[1][0]}, direct-only wins={tbl.values[0][1]}, "
            f"statistic={res.statistic:.3g}, p={res.pvalue:.4f}")


def table4_5_resilience(pipe: pd.DataFrame, tables_dir, stats_lines):
    rows = []
    for m, g in pipe.groupby("model"):
        clean, noisy = g[g.word_error_rate == 0], g[g.word_error_rate > 0]
        rows.append({
            "Model": MODELS[m][2],
            "Clean acc %": round(pct(clean["success"]), 1),
            "Noisy acc %": round(pct(noisy["success"]), 1),
            "Resilience gap (pp)": round(pct(clean["success"]) - pct(noisy["success"]), 1),
            "Recovery rate": f"{pct(noisy['success']):.1f}% ({int(noisy['success'].sum())}/{len(noisy)})"
                             if len(noisy) else "—",
        })
    emit_table(pd.DataFrame(rows).sort_values("Model"), tables_dir, "table4",
               "Semantic resilience: clean vs.\\ noisy accuracy per pipeline model",
               "tab:resilience")

    bands = [("0 (clean)", lambda w: w == 0), ("0–25\\%", lambda w: (w > 0) & (w <= .25)),
             ("25–50\\%", lambda w: (w > .25) & (w <= .5)), (">50\\%", lambda w: w > .5)]
    rows = []
    for label, f in bands:
        g = pipe[f(pipe.word_error_rate)]
        if len(g):
            rows.append({"WER band": label, "n": len(g),
                         "Success %": round(pct(g["success"]), 1)})
    emit_table(pd.DataFrame(rows), tables_dir, "table5",
               "Success rate by WER band, pooled pipeline models", "tab:werbands")

    rho, p = sps.spearmanr(pipe["word_error_rate"], pipe["success"].astype(int))
    stats_lines.append(f"- **Spearman WER vs success (pooled pipeline, n={len(pipe)}):** "
                       f"rho={rho:.3f}, p={p:.4f}")


def table6_codeswitch(en, cs, tables_dir):
    if cs is None or cs.empty:
        print("  (no code-switch CSV — Table VI skipped)")
        return
    rows = []
    for label, df in (("English", en), ("Code-switched", cs)):
        for arm in ("pipeline", "direct"):
            g = df[df.input_mode == arm]
            if g.empty:
                continue
            rows.append({
                "Condition": label, "Arm": arm, "n": len(g),
                "Success %": round(pct(g["success"]), 1),
                "Mean WER": round(g[g.input_mode == "pipeline"]["word_error_rate"].mean(), 3)
                            if arm == "pipeline" else 0.0,
            })
    emit_table(pd.DataFrame(rows), tables_dir, "table6",
               "English vs.\\ code-switched pilot by arm", "tab:codeswitch", ".3f")


# ── Section III-G stats ─────────────────────────────────────────────────────
def more_stats(pipe: pd.DataFrame, stats_lines):
    # Cochran's Q across pipeline models on the shared clips.
    mat = pipe.pivot_table(index="command", columns="model",
                           values="success", aggfunc="first")
    mat = mat.dropna().astype(int)
    if mat.shape[0] >= 5 and mat.shape[1] >= 3:
        q = cochrans_q(mat.values)
        stats_lines.append(f"- **Cochran's Q across {mat.shape[1]} pipeline models "
                           f"(paired on {mat.shape[0]} clips):** "
                           f"Q={q.statistic:.2f}, p={q.pvalue:.4f}")
    # Chi-square: category × success.
    ct = pd.crosstab(pipe["category"], pipe["success"])
    if ct.shape[0] > 1:
        chi2, p, dof, _ = sps.chi2_contingency(ct)
        stats_lines.append(f"- **Chi-square category × success:** "
                           f"chi2={chi2:.2f}, dof={dof}, p={p:.4f}")


def crosstab_ivc(en: pd.DataFrame, out_dir: Path):
    """Section IV-C: on clips the best pipeline model FAILED, did the direct
    arm succeed — and was the failure on a mis-transcribed clip (ASR damage)
    or a clean one (reasoning failure)?"""
    pipe, direct = en[en.input_mode == "pipeline"], en[en.input_mode == "direct"]
    if direct.empty or pipe.empty:
        return
    best = pipe.groupby("model")["success"].mean().idxmax()
    p = pipe[pipe.model == best].set_index("command")
    d = direct.set_index("command")
    common = p.index.intersection(d.index)
    rows = []
    for c in common:
        rows.append({
            "clip": c,
            "wer>0": bool(p.loc[c, "word_error_rate"] > 0),
            "pipeline_ok": bool(p.loc[c, "success"]),
            "direct_ok": bool(d.loc[c, "success"]),
        })
    t = pd.DataFrame(rows)
    xt = t.groupby(["wer>0", "pipeline_ok", "direct_ok"]).size().rename("clips").reset_index()
    md = (f"Cross-tabulation (best pipeline = {MODELS[best][2]} vs direct arm), "
          f"n={len(t)} matched clips.\n\n" + xt.to_markdown(index=False) +
          "\n\nRead: rows with wer>0=True & pipeline_ok=False & direct_ok=True are the "
          "clips where removing the ASR stage rescued a command the pipeline lost to "
          "transcription damage — the paper's key quantity.\n")
    (out_dir / "crosstab_ivc.md").write_text(md, encoding="utf-8")
    print("  wrote crosstab_ivc.md")


# ── Figures ─────────────────────────────────────────────────────────────────
def save(fig, figs_dir: Path, name: str):
    figs_dir.mkdir(parents=True, exist_ok=True)
    for ext in ("pdf", "png"):
        fig.savefig(figs_dir / f"{name}.{ext}")
    plt.close(fig)
    print(f"  wrote figures/{name}.pdf/.png")


def fig1_pareto(en, figs_dir):
    agg = en.groupby("model").agg(
        success=("success", "mean"), lat=("latency_ms", "median")).reset_index()
    fig, ax = plt.subplots(figsize=(IEEE_COL, 2.9))
    # Normalized coords for greedy label-collision avoidance.
    lat_rng = max(agg["lat"].max() - agg["lat"].min(), 1)
    suc_rng = max((agg["success"].max() - agg["success"].min()) * 100, 1)
    placed = []  # (nx, ny) of already-placed label anchors
    CAND = [((4, 3), "left"), ((4, -10), "left"), ((-4, 3), "right"),
            ((-4, -10), "right"), ((4, 12), "left"), ((-4, 12), "right")]
    for _, r in agg.sort_values("lat").iterrows():
        m = r["model"]
        x, y = r["lat"], 100 * r["success"]
        ax.scatter(x, y, s=28 + 40 * MODELS[m][0],
                   color=FAMILY_COLOR[MODELS[m][1]], marker=MODEL_MARKER[m],
                   edgecolors="white", linewidths=0.6, zorder=3)
        nx, ny = (x - agg["lat"].min()) / lat_rng, (y - 100 * agg["success"].min()) / suc_rng
        for (off, ha) in CAND:  # first offset whose anchor is clear of others
            cand = (nx + off[0] / 60, ny + off[1] / 30)
            if all(abs(cand[0] - p[0]) > 0.3 or abs(cand[1] - p[1]) > 0.1
                   for p in placed):
                break
        placed.append(cand)
        short = MODELS[m][2].replace(" (direct)", "")  # marker+legend carry arm
        ax.annotate(short, (x, y), textcoords="offset points",
                    xytext=off, ha=ha, fontsize=6)
    # Pareto frontier: lowest latency for each successively higher accuracy.
    pts = agg.sort_values("lat")[["lat", "success"]].values
    front, best = [], -1
    for lat, s in pts:
        if s > best:
            front.append((lat, 100 * s)); best = s
    if len(front) > 1:
        ax.plot(*zip(*front), color="#666666", lw=0.8, ls="--", zorder=2)
    handles = [plt.Line2D([], [], marker="o", ls="", color=c, label=FAMILY_LABEL[f])
               for f, c in FAMILY_COLOR.items()]
    ax.legend(handles=handles, frameon=False, loc="upper center",
              bbox_to_anchor=(0.5, -0.22), ncol=2)  # below axes: never on data
    ax.margins(x=0.12, y=0.12)
    ax.set_xlabel("Median end-to-end latency (ms)")
    ax.set_ylabel("Task success (%)")
    save(fig, figs_dir, "fig1_pareto")


def fig2_latency_box(en, figs_dir):
    order = sorted(en["model"].unique(), key=lambda m: MODELS[m][0])
    data = [en[en.model == m]["latency_ms"].dropna() for m in order]
    fig, ax = plt.subplots(figsize=(IEEE_FULL, 2.4))
    bp = ax.boxplot(data, tick_labels=[MODELS[m][2] for m in order], widths=0.55,
                    patch_artist=True, medianprops=dict(color="black", lw=1.2),
                    flierprops=dict(marker=".", markersize=3, alpha=0.6))
    for patch, m in zip(bp["boxes"], order):
        patch.set_facecolor(FAMILY_COLOR[MODELS[m][1]])
        patch.set_alpha(0.55); patch.set_edgecolor("black"); patch.set_linewidth(0.5)
    ax.set_ylabel("Latency (ms)")
    plt.setp(ax.get_xticklabels(), rotation=25, ha="right")
    save(fig, figs_dir, "fig2_latency_box")


def fig3_fn_vs_param(en, figs_dir):
    pipe = en[en.input_mode == "pipeline"]
    agg = pipe.groupby("model").agg(fn=("correct_function", "mean"),
                                    pr=("correct_params", "mean")).reset_index()
    agg = agg.sort_values(by="model", key=lambda s: s.map(lambda m: MODELS[m][0]))
    x = np.arange(len(agg)); w = 0.38
    fig, ax = plt.subplots(figsize=(IEEE_FULL, 2.4))
    ax.bar(x - w / 2, 100 * agg["fn"], w, label="Function accuracy",
           color="#0072B2", edgecolor="white", linewidth=0.5)
    ax.bar(x + w / 2, 100 * agg["pr"], w, label="Parameter accuracy",
           color="#56B4E9", hatch="///", edgecolor="white", linewidth=0.5)
    ax.set_xticks(x, [MODELS[m][2] for m in agg["model"]], rotation=25, ha="right")
    ax.set_ylabel("Accuracy (%)"); ax.set_ylim(0, 100)
    ax.legend(frameon=False, ncol=2, loc="upper left")
    save(fig, figs_dir, "fig3_fn_vs_param")


def fig4_degradation(en, figs_dir):
    pipe = en[en.input_mode == "pipeline"].copy()
    edges = [(-0.001, 0.0), (0.0, 0.25), (0.25, 0.5), (0.5, 10)]
    labels = ["0", "0–25%", "25–50%", ">50%"]
    fig, ax = plt.subplots(figsize=(IEEE_COL, 2.6))
    styles = {"hybrid": "-", "transformer": "--", "specialist": ":"}
    for fam, g in pipe.groupby("family"):
        ys, xs = [], []
        for i, (lo, hi) in enumerate(edges):
            sel = g[(g.word_error_rate > lo) & (g.word_error_rate <= hi)]
            if len(sel) >= 3:
                xs.append(i); ys.append(pct(sel["success"]))
        if len(xs) > 1:
            ax.plot(xs, ys, styles.get(fam, "-"), color=FAMILY_COLOR[fam],
                    marker="o", ms=4, lw=1.5, label=FAMILY_LABEL[fam])
    ax.set_xticks(range(4), labels)
    ax.set_xlabel("WER band"); ax.set_ylabel("Task success (%)")
    ax.legend(frameon=False)
    save(fig, figs_dir, "fig4_degradation")


def fig5_heatmap(en, figs_dir):
    pipe = en[en.input_mode == "pipeline"]
    mat = pipe.pivot_table(index="model", columns="category",
                           values="success", aggfunc="mean")
    mat = mat.reindex(sorted(mat.index, key=lambda m: MODELS[m][0]))
    fig, ax = plt.subplots(figsize=(IEEE_COL, 2.8))
    im = ax.imshow(100 * mat.values, cmap="Blues", vmin=0, vmax=100, aspect="auto")
    ax.set_xticks(range(mat.shape[1]), mat.columns, rotation=30, ha="right")
    ax.set_yticks(range(mat.shape[0]), [MODELS[m][2] for m in mat.index])
    for i in range(mat.shape[0]):        # print values so grayscale still reads
        for j in range(mat.shape[1]):
            v = 100 * mat.values[i, j]
            if not np.isnan(v):
                ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=6,
                        color="white" if v > 55 else "black")
    fig.colorbar(im, ax=ax, shrink=0.8, label="Success (%)")
    ax.grid(False)
    save(fig, figs_dir, "fig5_heatmap")


def fig6_codeswitch(en, cs, figs_dir):
    if cs is None or cs.empty:
        return
    rows = []
    for cond, df in (("English", en), ("Code-switched", cs)):
        for arm in ("pipeline", "direct"):
            g = df[df.input_mode == arm]
            if len(g):
                rows.append((cond, arm, pct(g["success"])))
    t = pd.DataFrame(rows, columns=["cond", "arm", "succ"])
    arms = ["pipeline", "direct"]; conds = ["English", "Code-switched"]
    x = np.arange(len(arms)); w = 0.38
    fig, ax = plt.subplots(figsize=(IEEE_COL, 2.4))
    for i, cond in enumerate(conds):
        vals = [t[(t.cond == cond) & (t.arm == a)]["succ"].mean() for a in arms]
        ax.bar(x + (i - 0.5) * w, vals, w, label=cond,
               color=["#0072B2", "#E69F00"][i], hatch=["", "///"][i],
               edgecolor="white", linewidth=0.5)
    ax.set_xticks(x, ["Pipeline arm", "Direct arm"])
    ax.set_ylabel("Task success (%)"); ax.set_ylim(0, 100)
    ax.legend(frameon=False)
    save(fig, figs_dir, "fig6_codeswitch")


# ── Main ────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results_dir", nargs="?", default="device_results")
    ap.add_argument("--out", default="analysis_out")
    args = ap.parse_args()
    rd, out = Path(args.results_dir), Path(args.out)
    tables, figs = out / "tables", out / "figures"

    en_csv = rd / "headless_benchmark_results.csv"
    if not en_csv.exists():
        sys.exit(f"Not found: {en_csv}\nPull it first:\n  adb pull /storage/emulated/0/"
                 f"Android/data/com.example.my_agent_app/files/results {rd}")
    en = load_results(en_csv)
    cs_csv = rd / "headless_benchmark_results_codeswitch.csv"
    cs = load_results(cs_csv) if cs_csv.exists() else None
    tr_en = load_transcripts(rd / "transcripts.json")
    tr_cs = load_transcripts(rd / "transcripts_codeswitch.json")
    pipe = en[en.input_mode == "pipeline"]

    print(f"Loaded {len(en)} English rows ({en['model'].nunique()} models), "
          f"{0 if cs is None else len(cs)} code-switch rows")

    stats_lines = ["# Statistical tests (section III-G)\n"]
    print("Tables:")
    table1_whisper(tr_en, tr_cs, tables)
    table2_pipeline(pipe, tables)
    table3_arch(en, tables, stats_lines)
    table4_5_resilience(pipe, tables, stats_lines)
    table6_codeswitch(en, cs, tables)
    more_stats(pipe, stats_lines)
    crosstab_ivc(en, out)
    (out / "stats.md").write_text("\n".join(stats_lines) + "\n", encoding="utf-8")
    print("  wrote stats.md")

    print("Figures:")
    fig1_pareto(en, figs)
    fig2_latency_box(en, figs)
    fig3_fn_vs_param(en, figs)
    fig4_degradation(en, figs)
    fig5_heatmap(en, figs)
    fig6_codeswitch(en, cs, figs)
    print(f"\nDone -> {out.resolve()}")


if __name__ == "__main__":
    main()
