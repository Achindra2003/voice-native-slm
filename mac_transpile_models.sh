#!/bin/bash
# =============================================================================
#  Cactus model transpiler — RUN THIS ON AN APPLE SILICON MAC (M1/M2/M3/M4)
# =============================================================================
#  Produces runnable Cactus "components/" bundles for the 9 models that have no
#  prebuilt bundle, pinned to the EXACT engine version on the target phone so
#  the bundles load correctly. Each model is zipped into ~/cactus_bundles/.
#
#  HOW TO RUN:
#     1. Copy this file to the Mac (AirDrop / USB / email).
#     2. Open Terminal, then:  bash ~/Downloads/mac_transpile_models.sh
#     3. Wait (~30-90 min; it downloads ~15 GB of models + transpiles).
#     4. Send back the whole  ~/cactus_bundles/  folder AND  ~/cactus_run.log
#
#  It is safe to re-run — finished models are skipped, downloads are cached.
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

# --- 4. clone Cactus at the pinned commit ----------------------------------
mkdir -p "$WORK"; cd "$WORK"
if [ ! -d cactus/.git ]; then
  echo ">> Cloning cactus..."
  git clone https://github.com/cactus-compute/cactus.git
fi
cd cactus
git fetch --all --quiet
git checkout "$CACTUS_COMMIT" || { echo "!! Could not checkout $CACTUS_COMMIT"; exit 1; }
echo "[ok] cactus @ $(git rev-parse --short HEAD)"

# --- 5. venv + python packages --------------------------------------------
$PY -m venv "$WORK/venv"
source "$WORK/venv/bin/activate"
pip install -U pip wheel >/dev/null
echo ">> Installing torch + transformers (a few minutes)..."
pip install torch transformers safetensors numpy huggingface_hub tokenizers >/dev/null
pip install -e python >/dev/null   # installs the 'cactus' CLI from this exact source
echo "[ok] cactus CLI: $(command -v cactus || echo 'via python -m cactus')"

run_cactus() { cactus "$@" 2>&1 || python -m cactus "$@" 2>&1; }

# --- 6. build the engine dylib (native ARM — the step that fails on x86) ----
echo ">> Building cactus engine for this Mac..."
run_cactus build --python | tail -5 || echo "(will let transpile auto-build the engine)"

# --- 7. transpile each model ----------------------------------------------
mkdir -p "$OUT"
# device-folder-name : HuggingFace id   (folder name = what we push to the phone)
MODELS=(
  "lfm2-350m|LiquidAI/LFM2-350M"
  "lfm2.5-350m|LiquidAI/LFM2.5-350M"
  "lfm2-700m|LiquidAI/LFM2-700M"
  "lfm2-1.2b|LiquidAI/LFM2-1.2B"
  "qwen3-0.6|Qwen/Qwen3-0.6B"
  "qwen3-1.7|Qwen/Qwen3-1.7B"
  "qwen3.5-0.8|Qwen/Qwen3.5-0.8B"
  "qwen3.5-2b|Qwen/Qwen3.5-2B"
  "functiongemma-270m|google/functiongemma-270m-it"
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
