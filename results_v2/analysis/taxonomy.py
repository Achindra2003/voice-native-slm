"""Error taxonomy for pipeline failures (Main condition).

Buckets every failed pipeline test into one of:
  A. asked-permission   - no tool call; prose asks/confirms instead of acting
  B. other-prose        - no tool call; other conversational/reasoning text
  C. empty-or-malformed - no tool call; empty output or unparseable call
  D. wrong-function     - called a function, wrong one
  E. wrong-params       - right function, wrong/missing arguments
Cross-cut: transcript state (clean / noisy / destroyed >=0.5 WER) to separate
ASR-cascade failures from pure reasoning failures.
Also extracts semantic-resilience WINS: successes on noisy transcripts.
"""

import re
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent
df = pd.read_csv(ROOT / "all_rows.csv").fillna("")

pl = df[(df.condition == "main_en") & (df.arm == "pipeline")]
fails = pl[pl.success == 0].copy()

PERMISSION_PAT = re.compile(
    r"would you like|shall i|do you want|should i|can i |may i |"
    r"let me know|please confirm|\?\s*\"?$", re.I)


def bucket(r):
    err = str(r["error"])
    if "No tool calls generated" in err:
        m = re.search(r'raw: "(.*)"?$', err, re.S)
        raw = (m.group(1) if m else "").strip()
        if not raw or raw in ('"', "''"):
            return "C-empty-or-malformed"
        if re.search(r"\w+\(.*\)", raw) and len(raw) < 80:
            return "C-empty-or-malformed"   # positional/pseudo-call the parser rejected
        if PERMISSION_PAT.search(raw):
            return "A-asked-permission"
        return "B-other-prose"
    if r["actual_function"] and r["actual_function"] != r["expected_function"]:
        return "D-wrong-function"
    if r["actual_function"] == r["expected_function"]:
        return "E-wrong-params"
    return "C-empty-or-malformed"


fails["bucket"] = fails.apply(bucket, axis=1)
fails["tstate"] = pd.cut(fails.wer_norm, [-1, 0, 0.5, 10],
                         labels=["clean", "noisy<0.5", "destroyed>=0.5"])

print("=== BUCKET x TRANSCRIPT STATE (n=%d failures) ===" % len(fails))
ct = pd.crosstab(fails.bucket, fails.tstate, margins=True)
print(ct)
print()
print("=== BUCKET x MODEL ===")
print(pd.crosstab(fails.bucket, fails.model).to_string())
print()

# most common wrong-function confusions
print("=== TOP WRONG-FUNCTION CONFUSIONS ===")
wf = fails[fails.bucket == "D-wrong-function"]
conf = (wf.groupby(["expected_function", "actual_function"]).size()
        .sort_values(ascending=False).head(8))
print(conf.to_string())
print()

# examples per bucket (for the paper's verbatim quotes)
print("=== EXAMPLES ===")
for b in sorted(fails.bucket.unique()):
    sub = fails[fails.bucket == b].head(3)
    print(f"\n--- {b} ---")
    for _, r in sub.iterrows():
        err = str(r["error"])[:180].replace("\n", " ")
        print(f'  [{r.model} | clip {r.clip_idx} | WER {r.wer_norm:.2f}] '
              f'"{r.transcript}" expected {r.expected_function}')
        if r["actual_function"]:
            print(f'    -> called {r.actual_function}({r.actual_params})')
        else:
            print(f'    -> {err}')

# resilience wins: success on noisy transcripts, listed for the paper
print("\n=== SEMANTIC-RESILIENCE WINS (success despite WER>=0.3) ===")
wins = pl[(pl.success == 1) & (pl.wer_norm >= 0.3)]
for _, r in wins.iterrows():
    print(f'  [{r.model}] "{r.command}" heard as "{r.transcript}" '
          f'(WER {r.wer_norm:.2f}) -> {r.actual_function}({r.actual_params})')

# ASR-cascade "wrong but faithful": failures where the call matches the
# transcript's literal content (the model obeyed a corrupted instruction)
print("\n=== CASCADE: destroyed-transcript failures (WER>=0.5) by bucket ===")
print(fails[fails.tstate == "destroyed>=0.5"].bucket.value_counts().to_string())

fails.to_csv(ROOT / "failure_taxonomy.csv", index=False)
print("\nwrote failure_taxonomy.csv")
