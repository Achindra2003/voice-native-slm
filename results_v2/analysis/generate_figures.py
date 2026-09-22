"""Six print-quality figures for paper_v2 (IEEE column sizes, PNG 300dpi + PDF).

Palette: dataviz-validated categorical slots, color follows the entity everywhere:
  LFM family  -> blue    #2a78d6
  Qwen family -> green   #008300
  Gemma-4-E2B -> magenta #e87ba4  (relief rule: every mark direct-labeled)
Generation carried by marker shape, never by a new hue.
"""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent
FIG = ROOT / "figures"
FIG.mkdir(exist_ok=True)
df = pd.read_csv(ROOT / "all_rows.csv")

BLUE, GREEN, MAGENTA = "#2a78d6", "#008300", "#e87ba4"
GRAY_TEXT, GRAY_MUTED, GRID = "#0b0b0b", "#52514e", "#e5e4e0"

PIPELINE = ["LFM2 350M", "LFM2.5 350M", "LFM2 700M", "LFM2 1.2B",
            "LFM2.5 1.2B", "LFM2 1.2B Tool", "Qwen3 0.6B", "Qwen3 1.7B",
            "Qwen3.5 0.8B", "Qwen3.5 2B"]
GEMMA = "Gemma 4 E2B"


def fam_color(m):
    if m.startswith("LFM"):
        return BLUE
    if m.startswith("Qwen"):
        return GREEN
    return MAGENTA


def fam_marker(m):
    if "Tool" in m:
        return "^"           # specialist
    if "2.5" in m or "3.5" in m:
        return "D"           # generation 2.5/3.5
    if m == GEMMA:
        return "*"
    return "o"


plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 7.5,
    "axes.titlesize": 8, "axes.labelsize": 7.5,
    "axes.edgecolor": GRAY_MUTED, "axes.linewidth": 0.6,
    "axes.spines.top": False, "axes.spines.right": False,
    "xtick.color": GRAY_MUTED, "ytick.color": GRAY_MUTED,
    "xtick.labelcolor": GRAY_TEXT, "ytick.labelcolor": GRAY_TEXT,
    "text.color": GRAY_TEXT, "axes.labelcolor": GRAY_TEXT,
    "grid.color": GRID, "grid.linewidth": 0.5,
    "figure.dpi": 300, "savefig.dpi": 300,
    "legend.frameon": False, "legend.fontsize": 6.5,
    # NOTE: savefig.bbox="tight" is deliberately NOT set. It trims the canvas to
    # the drawn content, so each figure came out a different width (3.33-4.35in)
    # and LaTeX then scaled it to \columnwidth by a different factor -- effective
    # font sizes ranged 6.0-9.0pt across the set. constrained_layout honours the
    # requested figsize exactly, so every figure is 3.5in = \columnwidth, scale
    # 1.0, and the 7.5pt base font renders at 7.5pt everywhere.
    "figure.constrained_layout.use": True,
    "figure.constrained_layout.h_pad": 0.02,
    "figure.constrained_layout.w_pad": 0.02,
})

# IEEEtran conference \columnwidth = 252pt = 3.5in. All figures use this width.
COLW = 3.5

main = df[df.condition == "main_en"]
mm = (main.groupby("model")
      .agg(succ=("success", "mean"), fn=("correct_function", "mean"),
           par=("correct_params", "mean"),
           med_lat=("latency_ms", "median"), p95=("latency_ms",
                                                  lambda s: s.quantile(.95)))
      .reindex(PIPELINE + [GEMMA]))
mm["med_s"] = mm.med_lat / 1000


def save(fig, name):
    fig.savefig(FIG / f"{name}.png")
    fig.savefig(FIG / f"{name}.pdf")
    plt.close(fig)
    print("saved", name)


# ---------------------------------------------------------------- Fig 1
fig, ax = plt.subplots(figsize=(3.5, 2.7))
ax.grid(True, axis="both", zorder=0)
for m, r in mm.iterrows():
    ax.scatter(r.med_s, 100 * r.succ, s=95 if m == GEMMA else 28,
               c=fam_color(m), marker=fam_marker(m), zorder=3,
               edgecolors="white", linewidths=0.5)
pareto = []
best = -1
for m, r in mm.sort_values("med_s").iterrows():
    if 100 * r.succ > best:
        best = 100 * r.succ
        pareto.append((r.med_s, best))
px, py = zip(*pareto)
ax.step(px, py, where="post", color=GRAY_MUTED, lw=0.8, ls="--", zorder=2)
# (dx pts, dy pts, ha)
offsets = {"LFM2 350M": (0, -11, "center"), "LFM2.5 350M": (0, 8, "center"),
           "LFM2 700M": (0, 7, "center"), "LFM2 1.2B": (4, -9, "left"),
           "LFM2.5 1.2B": (6, -2, "left"), "LFM2 1.2B Tool": (6, 4, "left"),
           "Qwen3 0.6B": (-6, -3, "right"), "Qwen3 1.7B": (6, -2, "left"),
           "Qwen3.5 0.8B": (0, 7, "center"), "Qwen3.5 2B": (0, 7, "center"),
           "Gemma 4 E2B": (7, 0, "left")}
for m, r in mm.iterrows():
    dx, dy, ha = offsets.get(m, (3, 3, "left"))
    ax.annotate(m, (r.med_s, 100 * r.succ), textcoords="offset points",
                xytext=(dx, dy), fontsize=6, ha=ha,
                color=GRAY_TEXT)
ax.set_xlabel("Median end-to-end latency (s)")
ax.set_ylabel("Task success (%)")
# Left margin: the leftmost points sit at ~8s and their labels are centred, so a
# 0-start axis pushed "LFM2.5 350M"/"LFM2 350M" out over the y-axis once the
# canvas stopped auto-expanding to fit them.
ax.set_xlim(-9, 122)
ax.set_ylim(0, 75)
ax.annotate("Pareto frontier", (34, 50), fontsize=6,
            color=GRAY_MUTED, style="italic", ha="center")
save(fig, "fig1_accuracy_latency")

# ---------------------------------------------------------------- Fig 2
order = mm.sort_values("med_s").index.tolist()
fig, ax = plt.subplots(figsize=(3.5, 2.9))
ax.grid(True, axis="x", zorder=0)
data = [main[main.model == m].latency_ms.values / 1000 for m in order]
bp = ax.boxplot(data, vert=False, patch_artist=True, widths=0.55,
                medianprops=dict(color="white", lw=1.2),
                flierprops=dict(marker="o", markersize=2.2,
                                markerfacecolor=GRAY_MUTED,
                                markeredgecolor="none"),
                whiskerprops=dict(color=GRAY_MUTED, lw=0.7),
                capprops=dict(color=GRAY_MUTED, lw=0.7), zorder=3)
for patch, m in zip(bp["boxes"], order):
    patch.set_facecolor(fam_color(m))
    patch.set_edgecolor("white")
    patch.set_linewidth(0.5)
ax.set_yticks(range(1, len(order) + 1))
ax.set_yticklabels([f"{m}{' (direct)' if m == GEMMA else ''}" for m in order],
                   fontsize=6.5)
ax.set_xlabel("Per-command latency (s)")
save(fig, "fig2_latency_box")

# ---------------------------------------------------------------- Fig 3
fig, ax = plt.subplots(figsize=(3.5, 2.9))
ax.grid(True, axis="x", zorder=0)
models = PIPELINE + [GEMMA]
y = np.arange(len(models))[::-1]
h = 0.38
ax.barh(y + h / 2 + 0.01, 100 * mm.loc[models, "fn"], height=h, color=BLUE,
        zorder=3, edgecolor="white", linewidth=0.5, label="Function accuracy")
ax.barh(y - h / 2 - 0.01, 100 * mm.loc[models, "par"], height=h, color=GREEN,
        zorder=3, edgecolor="white", linewidth=0.5, label="Parameter accuracy")
for yi, m in zip(y, models):
    ax.text(100 * mm.loc[m, "fn"] + 1, yi + h / 2, f"{100*mm.loc[m,'fn']:.0f}",
            va="center", fontsize=5.5, color=GRAY_MUTED)
    ax.text(100 * mm.loc[m, "par"] + 1, yi - h / 2, f"{100*mm.loc[m,'par']:.0f}",
            va="center", fontsize=5.5, color=GRAY_MUTED)
ax.set_yticks(y)
ax.set_yticklabels([f"{m}{' (direct)' if m == GEMMA else ''}" for m in models],
                   fontsize=6.5)
ax.set_xlabel("Accuracy (%)")
ax.set_xlim(0, 100)
ax.legend(loc="upper right")
save(fig, "fig3_function_vs_param")

# ---------------------------------------------------------------- Fig 4
bands = [(-0.001, 0.0), (0.0, 0.25), (0.25, 0.50), (0.50, 10)]
band_labels = ["0\n(clean)", "0–0.25", "0.25–0.50", ">0.50"]


def band_rates(sub):
    out = []
    for lo, hi in bands:
        s = sub[(sub.wer_norm > lo) & (sub.wer_norm <= hi)]
        out.append(100 * s.success.mean() if len(s) else np.nan)
    return out


def wilson(k, n, z=1.96):
    if n == 0:
        return (np.nan, np.nan)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    hw = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return 100 * (c - hw), 100 * (c + hw)


def band_counts(sub):
    out = []
    for lo, hi in bands:
        s = sub[(sub.wer_norm > lo) & (sub.wer_norm <= hi)]
        out.append((int(s.success.sum()), len(s)))
    return out


pl = main[main.arm == "pipeline"]
series = [
    ("LFM family (6 models)", band_counts(pl[pl.model.str.startswith("LFM")]),
     BLUE, -0.06),
    ("Qwen family (4 models)", band_counts(pl[pl.model.str.startswith("Qwen")]),
     GREEN, 0.06),
]
x = np.arange(4)
fig, ax = plt.subplots(figsize=(3.5, 2.5))
ax.grid(True, axis="y", zorder=0)
for label, kn, c, dx in series:
    vals = [100 * k / n for k, n in kn]
    los, his = zip(*[wilson(k, n) for k, n in kn])
    yerr = np.array([[v - lo for v, lo in zip(vals, los)],
                     [hi - v for v, hi in zip(vals, his)]])
    ax.errorbar(x + dx, vals, yerr=yerr, color=c, lw=1.6, marker="o",
                markersize=4, markeredgecolor="white", markeredgewidth=0.5,
                capsize=2, elinewidth=0.7, zorder=3, label=label)
counts = [len(pl[(pl.wer_norm > lo) & (pl.wer_norm <= hi)]) // 10
          for lo, hi in bands]
ax.set_xticks(x)
ax.set_xticklabels([f"{b}\nn={c} clips" for b, c in zip(band_labels, counts)],
                   fontsize=6)
ax.set_ylabel("Task success (%)")
ax.set_xlabel("Transcript WER band")
ax.set_ylim(0, 75)
ax.legend(loc="upper right")
save(fig, "fig4_wer_degradation")

# ---------------------------------------------------------------- Fig 5
cats = ["direct", "parameter", "temporal", "contextual", "rule"]
# Abbreviated: at the fixed 3.5in column width the full words ("Parameter",
# "Contextual") overlap their neighbours. Category names are spelled out in III-D.
cat_labels = ["Direct", "Param.", "Temporal", "Context.", "Rule"]
models5 = (mm.succ.sort_values(ascending=False).index.tolist())
grid = np.array([[main[(main.model == m) & (main.category == c)].success.mean()
                  for c in cats] for m in models5])
# sequential blue ramp (palette steps 100->700)
from matplotlib.colors import LinearSegmentedColormap
ramp = LinearSegmentedColormap.from_list(
    "blueseq", ["#f5f9fe", "#cde2fb", "#9ec5f4", "#5598e7", "#2a78d6",
                "#1c5cab", "#0d366b"])
fig, ax = plt.subplots(figsize=(3.5, 2.9))
im = ax.imshow(100 * grid, cmap=ramp, vmin=0, vmax=100, aspect="auto")
for i in range(grid.shape[0]):
    for j in range(grid.shape[1]):
        v = grid[i, j]
        ax.text(j, i, f"{100*v:.0f}", ha="center", va="center", fontsize=6,
                color="white" if v > 0.55 else GRAY_TEXT)
n_clips_cat = {c: main[(main.category == c) & (main.arm == "pipeline")]
               .clip_idx.nunique() for c in cats}
ax.set_xticks(range(len(cats)))
ax.set_xticklabels([f"{l}\nn={n_clips_cat[c]}"
                    for l, c in zip(cat_labels, cats)], fontsize=6.0)
ax.set_yticks(range(len(models5)))
ax.set_yticklabels([f"{m}{' (direct)' if m == GEMMA else ''}" for m in models5],
                   fontsize=6.5)
ax.tick_params(length=0)
for s in ax.spines.values():
    s.set_visible(False)
cb = fig.colorbar(im, ax=ax, fraction=0.04, pad=0.02)
# Cells are printed as percentages, so the colourbar must read in percent too --
# a 0.0-1.0 bar beside cells labelled "90"/"100" shows one quantity on two scales.
cb.set_label("Task success (%)", fontsize=6.5)
cb.ax.tick_params(labelsize=6)
cb.outline.set_visible(False)
save(fig, "fig5_category_heatmap")

# ---------------------------------------------------------------- Fig 6
systems = [
    ("Pipeline mean\n(10 models)",
     df[(df.condition == "pilot_en") & (df.arm == "pipeline")].success.mean(),
     df[(df.condition == "pilot_cs") & (df.arm == "pipeline")].success.mean()),
    ("Best pipeline\nQwen3.5 0.8B",
     df[(df.condition == "pilot_en") & (df.model == "Qwen3.5 0.8B")].success.mean(),
     df[(df.condition == "pilot_cs") & (df.model == "Qwen3.5 0.8B")].success.mean()),
    ("Gemma-4-E2B\nfed transcripts",
     df[df.condition == "ablation_pilot_en"].success.mean(),
     df[df.condition == "ablation_cs"].success.mean()),
    ("Gemma-4-E2B\ndirect audio",
     df[(df.condition == "pilot_en") & (df.model == GEMMA)].success.mean(),
     df[(df.condition == "pilot_cs") & (df.model == GEMMA)].success.mean()),
]
fig, ax = plt.subplots(figsize=(3.5, 2.4))
ax.grid(True, axis="y", zorder=0)
x = np.arange(len(systems))
w = 0.36
en_vals = [100 * s[1] for s in systems]
cs_vals = [100 * s[2] for s in systems]
ax.bar(x - w / 2 - 0.01, en_vals, width=w, color=BLUE, zorder=3,
       edgecolor="white", linewidth=0.5, label="English")
ax.bar(x + w / 2 + 0.01, cs_vals, width=w, color=GREEN, zorder=3,
       edgecolor="white", linewidth=0.5, label="Code-switched")
for xi, (e, c) in enumerate(zip(en_vals, cs_vals)):
    ax.text(xi - w / 2 - 0.01, e + 1.5, f"{e:.0f}", ha="center", fontsize=6,
            color=GRAY_MUTED)
    ax.text(xi + w / 2 + 0.01, c + 1.5, f"{c:.0f}", ha="center", fontsize=6,
            color=GRAY_MUTED)
    d = c - e
    # one decimal: the text and Table VII quote -20.8 pp, so "-21 pp" here read
    # as a different number.
    ax.annotate(f"{d:+.1f} pp", (xi, max(e, c) + 9), ha="center", fontsize=6,
                color=GRAY_TEXT, style="italic")
ax.set_xticks(x)
# Labels were colliding ("(Qwen3.5 0.8B)" ran into "Gemma-4-E2B"). Shorter lines
# plus a small inset keep them clear at \columnwidth.
ax.set_xticklabels([s[0] for s in systems], fontsize=6.0, linespacing=1.25)
ax.set_xlim(-0.6, len(systems) - 0.4)
ax.set_ylabel("Task success (%)")
ax.set_ylim(0, 118)
ax.set_yticks([0, 25, 50, 75, 100])
ax.legend(loc="lower center", bbox_to_anchor=(0.5, 1.0), ncol=2)
save(fig, "fig6_en_vs_codeswitch")

print("all figures done ->", FIG)
