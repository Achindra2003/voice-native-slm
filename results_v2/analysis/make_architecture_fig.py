"""Figure 1 — two-arm measurement pipeline (IEEE single-column, 300 dpi).

Draws the matched-audio design: one recorded clip feeds both the ASR->SLM
cascade (Phase 2) and the audio-native model (Phase 3), with the Phase-4
modality ablation replaying the cached transcripts into the same audio-native
weights. Palette and typography match the data figures in generate_figures.py.

Layout is three horizontal lanes (pipeline / ablation / direct) converging on a
single scoring block, so no connector crosses a box.
"""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

FIG = Path(__file__).resolve().parent / "figures"
FIG.mkdir(exist_ok=True)

BLUE, GREEN, MAGENTA = "#2a78d6", "#008300", "#e87ba4"
GRAY_TEXT, GRAY_MUTED = "#0b0b0b", "#52514e"

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 7.5,
    "text.color": GRAY_TEXT,
    "figure.dpi": 300, "savefig.dpi": 300,
    # No savefig.bbox="tight": it trimmed this diagram to 2.91in, so LaTeX
    # scaled it 1.20x to \columnwidth and its fonts rendered ~20% larger than
    # every other figure. Fixed canvas keeps the whole set at one scale.
    "figure.constrained_layout.use": True,
})


def box(ax, x, y, w, h, label, color, *, dashed=False, fill=0.10, fs=6.5):
    for face, alpha in ((color, fill), ("none", 1.0)):
        ax.add_patch(FancyBboxPatch(
            (x, y), w, h,
            boxstyle="round,pad=0.008,rounding_size=0.025",
            linewidth=1.0, edgecolor=color, facecolor=face,
            alpha=alpha if face != "none" else 1.0,
            linestyle="--" if dashed else "-", zorder=2))
    ax.text(x + w / 2, y + h / 2, label, ha="center", va="center",
            fontsize=fs, linespacing=1.4, zorder=4)


def arrow(ax, p, q, color=GRAY_MUTED, dashed=False, rad=0.0):
    ax.add_patch(FancyArrowPatch(
        p, q, arrowstyle="-|>", mutation_scale=7,
        linewidth=0.9, color=color, zorder=1,
        linestyle="--" if dashed else "-",
        connectionstyle=f"arc3,rad={rad}", shrinkA=2, shrinkB=2))


fig, ax = plt.subplots(figsize=(3.5, 2.75))
# Small bleed margin: with the canvas now fixed at 3.5in the rightmost box
# ("Function-call scoring") sat flush on the figure edge.
ax.set_xlim(-0.025, 1.025)
ax.set_ylim(-0.02, 1.02)
ax.axis("off")

# lane geometry
XA, WA = 0.255, 0.215      # column A (Whisper)
XB, WB = 0.525, 0.235      # column B (models)
XS, WS = 0.815, 0.175      # column S (scoring)
H = 0.145
Y_PIPE, Y_ABL, Y_DIR = 0.80, 0.475, 0.17

# shared input
box(ax, 0.015, Y_ABL, 0.165, H, "54 clips\n16 kHz", GRAY_MUTED, fill=0.07)

# pipeline lane
box(ax, XA, Y_PIPE, WA, H, "Whisper\nbase 74M", BLUE)
box(ax, XB, Y_PIPE, WB, H, "10 text SLMs\n350M–2B", BLUE)

# ablation lane (dashed)
box(ax, XB, Y_ABL, WB, H, "Gemma-4-E2B\nfed transcripts", MAGENTA,
    dashed=True, fill=0.05)

# direct lane
box(ax, XB, Y_DIR, WB, H, "Gemma-4-E2B\nraw PCM", MAGENTA)

# scoring
box(ax, XS, Y_ABL, WS, H, "Function-\ncall scoring", GREEN)

# --- connectors (all left-to-right or vertical; none cross a box) --------
arrow(ax, (0.18, Y_ABL + H * 0.75), (XA, Y_PIPE + H / 2), rad=-0.22)
arrow(ax, (0.18, Y_ABL + H * 0.25), (XB, Y_DIR + H / 2), rad=0.22)
arrow(ax, (XA + WA, Y_PIPE + H / 2), (XB, Y_PIPE + H / 2))
# cached transcripts feed the ablation lane
arrow(ax, (XB + WB * 0.5, Y_PIPE), (XB + WB * 0.5, Y_ABL + H),
      color=MAGENTA, dashed=True)
ax.text(XB + WB * 0.5 + 0.018, (Y_PIPE + Y_ABL + H) / 2 + 0.005,
        "cached\ntranscripts", fontsize=5.4, color=MAGENTA,
        va="center", ha="left", linespacing=1.25)
# all three lanes -> scoring
arrow(ax, (XB + WB, Y_PIPE + H / 2), (XS, Y_ABL + H * 0.85), rad=-0.25)
arrow(ax, (XB + WB, Y_ABL + H / 2), (XS, Y_ABL + H / 2), color=MAGENTA)
arrow(ax, (XB + WB, Y_DIR + H / 2), (XS, Y_ABL + H * 0.12),
      color=MAGENTA, rad=0.14)

# Lane labels. ABLATION sits left-aligned under its box so the direct-arm
# connector (which sweeps up the right-hand side) cannot run through it.
ax.text(XB + WB / 2, Y_PIPE + H + 0.035, "PIPELINE ARM  (Phases 1–2)",
        fontsize=5.9, color=BLUE, ha="center", fontweight="bold")
ax.text(XB, Y_ABL - 0.052, "ABLATION  (Phase 4)",
        fontsize=5.9, color=MAGENTA, ha="left", fontweight="bold")
ax.text(XB, Y_DIR + H + 0.032, "DIRECT ARM  (Phase 3)",
        fontsize=5.9, color=MAGENTA, ha="left", fontweight="bold")

ax.text(0.5, 0.025,
        "matched audio: every system consumes the identical recording",
        fontsize=5.7, color=GRAY_MUTED, ha="center", style="italic")

fig.savefig(FIG / "fig1_architecture.png")
fig.savefig(FIG / "fig1_architecture.pdf")
print("wrote", FIG / "fig1_architecture.pdf")
