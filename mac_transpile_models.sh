#!/bin/bash
# =============================================================================
#  Cactus model transpiler — RUN THIS ON AN APPLE SILICON MAC (M1/M2/M3/M4)
# =============================================================================
#  Produces runnable Cactus "components/" bundles, pinned to the EXACT engine
#  version on the target phone so the bundles load correctly. Each model is
#  zipped into ~/cactus_bundles/.
#
#  THIS RUN (2026-07-08): produces the TWO NEW Liquid 1.2B models —
#  lfm2-1.2b-tool (function-calling specialist, replaces the dead functiongemma)
#  and lfm2.5-1.2b (gen-2.5 instruct). Both are small (~2.4 GB download each)
#  and quick to transpile. whisper-base and gemma-4-e2b are listed first but
#  will [skip] automatically if their zips already exist in ~/cactus_bundles
#  from the previous run — do NOT delete that folder.
#  gemma-3n was removed — Cactus cannot transpile it. functiongemma-270m is
#  NOT re-transpiled: a 2026-07-07 re-transpile produced a byte-identical
#  (still unloadable) graph, so it's disabled in section 7.
#
#  HuggingFace auth: NOTHING in this run is gated — no HF login needed.
#
#  HOW TO RUN:
#     1. Copy this file to the Mac — DELETE any older mac_transpile_models.sh
#        in ~/Downloads first so you can't run a stale copy by mistake.
#     2. Open Terminal, then:  bash ~/Downloads/mac_transpile_models.sh
#     3. Wait. The two Liquid models are ~2.4 GB download each and transpile
#        in minutes. (whisper-base / gemma-4-e2b lines will print [skip].)
#     4. Send back ONLY:  lfm2-1.2b-tool.zip, lfm2.5-1.2b.zip, cactus_run.log
#        (do NOT re-send gemma-4-e2b.zip / whisper-base.zip — already have them)
#
#  It is safe to re-run — finished models are skipped, downloads are cached,
#  and the clone/venv/engine-build steps skip themselves if already done.
#  This run produces 2 NEW models: lfm2-1.2b-tool + lfm2.5-1.2b. The 8 text
#  models and whisper-base/gemma-4-e2b from previous runs are already on the
#  phone and are NOT rebuilt (their zips [skip] if still in ~/cactus_bundles).
#
#  NOTE ON WHISPER: Cactus lists Whisper as a supported STT family, so
#  `cactus convert openai/whisper-base` should work. If that specific convert
#  errors, say so in the reply — Whisper may need a different convert flag and
#  we'll adjust.
# =============================================================================
set -u
exec > >(tee "$HOME/cactus_run.log") 2>&1   # log everything

CACTUS_COMMIT="0afa515c470298b7f1d4cdbd8f17cc6f1ce5aa42"  # matches the phone's engine
WORK="$HOME/cactus_transpile"
OUT="$HOME/cactus_bundles"
PLATFORM="cpu"   # phone needs the portable ARM/CPU bundle, NOT the 'apple' one
BITS=4

echo "############ Cactus transpile run: $(date) ############"

# --- 0. Apple Silicon gate -------------------------------------------------
if [ "$(uname -m)" != "arm64" ]; then
  echo "!! ERROR: uname -m = $(uname -m). This is NOT an Apple Silicon Mac."
  echo "!! Cactus transpile only works on ARM. Stop here — this machine can't help."
  exit 1
fi
echo "[ok] Apple Silicon detected ($(uname -m))"

# --- 1. Xcode Command Line Tools (clang) -----------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
  echo ">> Installing Xcode Command Line Tools. A popup will appear — click Install."
  echo ">> When it finishes, RE-RUN this script."
  xcode-select --install
  exit 1
fi
echo "[ok] Xcode CLT present"

# --- 2. Homebrew -----------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  echo ">> Installing Homebrew (may ask for the Mac password)..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
echo "[ok] Homebrew: $(command -v brew)"

# --- 3. build + python deps ------------------------------------------------
echo ">> Installing cmake, git, python..."
brew install cmake git python@3.12 >/dev/null 2>&1 || brew install cmake git python >/dev/null 2>&1
PY="$(command -v python3.12 || command -v python3)"
echo "[ok] python: $PY ($($PY --version))"

# --- 4. clone / verify Cactus at the pinned commit -------------------------
mkdir -p "$WORK"; cd "$WORK"
if [ -d cactus/.git ] && git -C cactus rev-parse --verify --quiet "$CACTUS_COMMIT" >/dev/null 2>&1; then
  echo "[ok] cactus already at correct commit"
else
  rm -rf cactus
  echo ">> Cloning cactus..."
  git clone https://github.com/cactus-compute/cactus.git
  cd cactus
  git checkout "$CACTUS_COMMIT" || { echo "!! Could not checkout $CACTUS_COMMIT"; exit 1; }
  cd "$WORK"
fi
cd cactus
echo "[ok] cactus @ $(git rev-parse --short HEAD)"

# --- 5. venv + python packages --------------------------------------------
if [ ! -f "$WORK/venv/bin/cactus" ]; then
  $PY -m venv "$WORK/venv"
  source "$WORK/venv/bin/activate"
  pip install -U pip wheel >/dev/null
  echo ">> Installing torch + transformers (a few minutes)..."
  pip install torch transformers safetensors numpy huggingface_hub tokenizers >/dev/null
  pip install -e python >/dev/null   # installs the 'cactus' CLI from this exact source
else
  source "$WORK/venv/bin/activate"
fi
echo "[ok] cactus CLI: $(command -v cactus || echo 'via python -m cactus')"

run_cactus() { cactus "$@" 2>&1 || python -m cactus "$@" 2>&1; }

# --- 5b. HuggingFace auth ----------------------------------------------------
#  NOT NEEDED for this run: every model in the MODELS list below is public
#  (LiquidAI/LFM2-1.2B-Tool, LiquidAI/LFM2.5-1.2B-Instruct, openai/whisper-base,
#  google/gemma-4-E2B-it). If a token happens to be set we use it, but a 401 /
#  "gated repo" error should never appear — if it does, the script was edited.
if [ -n "${HF_TOKEN:-}" ]; then
  export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"   # some tools read this name
  huggingface-cli login --token "$HF_TOKEN" --add-to-git-credential >/dev/null 2>&1 || true
  echo "[ok] HF token found in \$HF_TOKEN (not required for this run)"
elif huggingface-cli whoami >/dev/null 2>&1; then
  echo "[ok] HF auth: logged in as $(huggingface-cli whoami 2>/dev/null) (not required)"
else
  echo "[ok] no HF auth — fine, nothing in this run is gated"
fi

# --- 6. build the engine dylib (native ARM — the step that fails on x86) ----
if [ -f "cactus-engine/build/libcactus_engine.dylib" ]; then
  echo "[skip] engine already built"
else
  echo ">> Building cactus engine for this Mac..."
  run_cactus build --python | tail -5 || echo "(will let transpile auto-build the engine)"
fi

# --- 7. transpile each model ----------------------------------------------
mkdir -p "$OUT"
# device-folder-name : HuggingFace id   (folder name = what we push to the phone)
# THIS RUN builds only the two NEW Liquid 1.2B models at the bottom of the
# list. whisper-base and gemma-4-e2b will [skip] (their zips already exist in
# ~/cactus_bundles from previous runs). The 8 text models from the first run
# are already on the phone — do NOT re-do them.
MODELS=(
  # ---- HIGHEST PRIORITY: the STT model that unlocks the whole pipeline arm ----
  # Whisper is the speech-recognition stage. Without it, NONE of the 9 text
  # models already on the phone can be benchmarked. If you only have time for
  # ONE model, do this one. Device folder name must stay 'whisper-base'.
  "whisper-base|openai/whisper-base"
  # ---- audio-native model (direct arm) ----
  # gemma-4-e2b: audio encoder CONFIRMED (gemma4_audio in its config.json).
  #   NOT gated. Single ~10 GB safetensors file (5.12B raw params, bf16).
  # NOTE: gemma-3n-e2b was REMOVED (2026-07-05): Cactus's transpile pipeline
  #   has no gemma3n adapter at ANY commit — "Cactus doesn't support it at this
  #   engine commit" is correct and unfixable. Do not re-add it.
  "gemma-4-e2b|google/gemma-4-E2B-it"
  # ---- pipeline-arm SPECIALIST — DO NOT RE-TRANSPILE (proven dead end, 2026-07-07) ----
  # functiongemma-270m fails cactus_init on the pinned v2.0 engine ("Failed to
  # initialize model"). We ORIGINALLY thought this was a stale-converter/format
  # issue and re-transpiled it with the CURRENT converter on 2026-07-07.
  # RESULT: the fresh output was BYTE-IDENTICAL to the failing on-device bundle
  # (components/decoder/graph.cactus md5 7f14af3a4b895f084b66f6ae0623e949, same
  # 250872 bytes). So it is NOT a stale bundle:
  #   - the converter emits a single monolithic components/decoder/ graph for
  #     this 270M model (the multi-graph decoder_*_chunk layout is only produced
  #     for larger/multimodal models), and
  #   - the pinned engine simply can't init a single-decoder-component gemma3
  #     bundle. Re-transpiling with the same converter can never change this.
  # Re-enabling it here just re-downloads a GATED repo to reproduce the identical
  # unloadable graph. Leave it OUT until the engine is upgraded to one that
  # supports single-decoder bundles (or functiongemma is dropped from the paper).
  # "functiongemma-270m|google/functiongemma-270m-it"   # disabled — see above
  # ---- NEW (2026-07-08): the two Liquid 1.2B additions ----
  # Both are Lfm2ForCausalLM — the exact architecture already proven to
  # transpile AND load on the phone's v2.0 engine (lfm2-1.2b passed a live
  # load test 2026-07-08). Neither repo is gated; no HF login needed. ~2.4 GB
  # download each (bf16 1.2B), minutes to transpile — far quicker than gemma.
  # lfm2-1.2b-tool: Liquid's function-calling specialist — replaces the dead
  #   functiongemma as the paper's specialist model.
  "lfm2-1.2b-tool|LiquidAI/LFM2-1.2B-Tool"
  # lfm2.5-1.2b: generation-2.5 instruct at 1.2B — completes the LFM2-vs-2.5
  #   generational comparison at a second size (we only had it at 350M).
  "lfm2.5-1.2b|LiquidAI/LFM2.5-1.2B-Instruct"
)

OK_LIST=(); FAIL_LIST=()
for entry in "${MODELS[@]}"; do
  name="${entry%%|*}"; hf="${entry##*|}"
  dest="$OUT/$name"
  echo ""
  echo "================ $name  ($hf) ================"
  if [ -f "$OUT/$name.zip" ]; then echo "[skip] already have $name.zip"; OK_LIST+=("$name"); continue; fi
  rm -rf "$dest"; mkdir -p "$dest"
  # build a runnable bundle locally, CPU/portable target, 4-bit
  run_cactus convert "$hf" "$dest" --platform "$PLATFORM" --bits "$BITS" | tail -25

  # locate the components/ (convert may nest it inside a subdir)
  comp="$(find "$dest" -type d -name components | head -1)"
  if [ -n "$comp" ] && [ -f "$comp/manifest.json" ]; then
    bundle_root="$(dirname "$comp")"
    ( cd "$bundle_root" && zip -r -q "$OUT/$name.zip" . )
    echo "[OK] $name -> $OUT/$name.zip  (components/manifest.json present)"
    OK_LIST+=("$name")
  else
    echo "[FAIL] $name — no components/manifest.json produced (see log above)"
    FAIL_LIST+=("$name")
  fi
done

# --- 8. summary ------------------------------------------------------------
echo ""
echo "######################## SUMMARY ########################"
echo "Bundles in: $OUT"
ls -lh "$OUT"/*.zip 2>/dev/null
echo ""
echo "OK   (${#OK_LIST[@]}): ${OK_LIST[*]:-none}"
echo "FAIL (${#FAIL_LIST[@]}): ${FAIL_LIST[*]:-none}"
echo ""
echo ">>> SEND BACK:  the ~/cactus_bundles/ folder  AND  ~/cactus_run.log"
echo "############ done: $(date) ############"
