"""Build the unified analysis dataset for paper_v2 from the pulled device results.

Outputs results_v2/analysis/all_rows.csv with one row per test execution across:
  main_en (330), pilot_en (132), pilot_cs (132),
  ablation_en (30), ablation_pilot_en (12), ablation_codeswitch (12)

Adds:
  clip_idx   — clip/command index within the condition (paired-test key)
  arm        — 'pipeline' | 'direct' | 'ablation' (Gemma fed transcripts as text)
  wer_norm   — WER recomputed with the normalization protocol of paper §III-B:
               lowercase, % -> ' percent', hyphens -> spaces, punctuation stripped,
               number words -> digits, whitespace collapsed.
               (The on-device wer.dart normalizes more naively, inflating WER on
               formatting-only differences like "Wi-Fi." vs "wifi".)
"""

import csv
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CONDITIONS = {
    # key: (results_json, transcripts_json, dataset_json, n_clips, arm_override)
    "main_en": ("main_en/headless_benchmark_results.json",
                "main_en/transcripts.json",
                "../assets/realistic_dataset.json", 30, None),
    "pilot_en": ("pilot_en/headless_benchmark_results_pilot_en.json",
                 "pilot_en/transcripts_pilot_en.json",
                 "../assets/pilot_en.json", 12, None),
    "pilot_cs": ("pilot_cs/headless_benchmark_results_codeswitch.json",
                 "pilot_cs/transcripts_codeswitch.json",
                 "../assets/pilot_codeswitch.json", 12, None),
    "ablation_en": ("ablation/headless_benchmark_results_ablation_en.json",
                    "main_en/transcripts.json",
                    "../assets/realistic_dataset.json", 30, "ablation"),
    "ablation_pilot_en": ("ablation/headless_benchmark_results_ablation_pilot_en.json",
                          "pilot_en/transcripts_pilot_en.json",
                          "../assets/pilot_en.json", 12, "ablation"),
    "ablation_cs": ("ablation/headless_benchmark_results_ablation_codeswitch.json",
                    "pilot_cs/transcripts_codeswitch.json",
                    "../assets/pilot_codeswitch.json", 12, "ablation"),
}

_NUM_WORDS = {
    "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
    "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
    "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
    "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
    "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
    "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
    "eighty": "80", "ninety": "90", "hundred": "100",
}


def normalize(text: str) -> list[str]:
    t = unicodedata.normalize("NFKC", text).lower()
    t = t.replace("%", " percent ")
    t = re.sub(r"[-_/]", " ", t)
    t = re.sub(r"[^\w\s]", "", t)          # strip remaining punctuation
    words = t.split()
    words = [_NUM_WORDS.get(w, w) for w in words]
    return words


def wer(ref: str, hyp: str) -> float:
    r, h = normalize(ref), normalize(hyp)
    if not r:
        return 0.0 if not h else 1.0
    # word-level Levenshtein
    dp = list(range(len(h) + 1))
    for i, rw in enumerate(r, 1):
        prev, dp[0] = dp[0], i
        for j, hw in enumerate(h, 1):
            cur = min(dp[j] + 1, dp[j - 1] + 1, prev + (rw != hw))
            prev, dp[j] = dp[j], cur
    return dp[len(h)] / len(r)


def load_condition(key):
    res_f, tr_f, ds_f, n_clips, arm_override = CONDITIONS[key]
    rows = json.loads((ROOT / res_f).read_text(encoding="utf-8"))
    transcripts = json.loads((ROOT / tr_f).read_text(encoding="utf-8"))
    dataset = json.loads((ROOT / ds_f).read_text(encoding="utf-8"))[:n_clips]

    # clip_idx assignment: transcript-text match first, occurrence order fallback
    by_cmd = {}
    for idx, tc in enumerate(dataset):
        by_cmd.setdefault(tc["original_command"], []).append(idx)
    tr_by_idx = {t["index"]: t for t in transcripts}

    out = []
    seen_occurrence = {}  # (model, command) -> count, for duplicate commands
    for r in rows:
        cmd = r["command"]
        cands = by_cmd[cmd]
        if len(cands) == 1:
            clip_idx = cands[0]
        else:
            # disambiguate duplicated commands by matching the stored transcript
            matches = [i for i in cands
                       if tr_by_idx[i]["transcript"] == r["transcribed_text"]]
            if len(matches) == 1:
                clip_idx = matches[0]
            else:
                k = (r["model"], cmd)
                n = seen_occurrence.get(k, 0)
                clip_idx = cands[n % len(cands)]
                seen_occurrence[k] = n + 1

        arm = arm_override or r["input_mode"]  # 'pipeline' | 'direct' | 'ablation'
        transcript = tr_by_idx[clip_idx]["transcript"]
        out.append({
            "condition": key,
            "arm": arm,
            "model": r["model"],
            "clip_idx": clip_idx,
            "command": cmd,
            "category": r["category"],
            "transcript": transcript,
            "success": int(r["success"]),
            "correct_function": int(r["correct_function"]),
            "correct_params": int(r["correct_params"]),
            "expected_function": r["expected_function"],
            "actual_function": r.get("actual_function", ""),
            "expected_params": r.get("expected_params", ""),
            "actual_params": r.get("actual_params", ""),
            "latency_ms": r["latency_ms"],
            "wer_raw": r["word_error_rate"],
            "wer_norm": wer(cmd, transcript) if arm != "direct" else 0.0,
            "error": r.get("error", ""),
        })
    return out


def main():
    all_rows = []
    for key in CONDITIONS:
        rows = load_condition(key)
        all_rows.extend(rows)
        n_models = len({r["model"] for r in rows})
        print(f"{key:18s} rows={len(rows):3d} models={n_models} "
              f"clips={len({r['clip_idx'] for r in rows})}")
    out = ROOT / "analysis" / "all_rows.csv"
    with out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(all_rows[0].keys()))
        w.writeheader()
        w.writerows(all_rows)
    print(f"\nwrote {len(all_rows)} rows -> {out}")

    # sanity: every (condition, model) covers every clip exactly once
    import collections
    cnt = collections.Counter((r["condition"], r["model"], r["clip_idx"])
                              for r in all_rows)
    bad = [k for k, v in cnt.items() if v != 1]
    print("duplicate/missing (condition,model,clip) pairs:", len(bad))
    if bad:
        for b in bad[:10]:
            print("  BAD:", b)

    # WER re-normalization effect (pipeline rows, per condition)
    for key in ("main_en", "pilot_en", "pilot_cs"):
        rs = [r for r in all_rows if r["condition"] == key and r["arm"] == "pipeline"]
        clips = {r["clip_idx"]: (r["wer_raw"], r["wer_norm"]) for r in rs}
        raw = sum(v[0] for v in clips.values()) / len(clips)
        norm = sum(v[1] for v in clips.values()) / len(clips)
        print(f"{key:10s} mean WER raw {raw:.3f} -> normalized {norm:.3f}")


if __name__ == "__main__":
    main()
