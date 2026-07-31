#!/bin/zsh
# Builds everything convert_lama_coreml.py needs: a Python that has wheels, the
# lama source tree, and the big-lama checkpoint.
#
# Do NOT `pip install -r lama/requirements.txt`. Those pins are from 2020 and
# include a numpy with no arm64 wheel, so pip compiles it from source and the old
# numpy build system passes `-faltivec` — a PowerPC flag clang rejects. The
# conversion only touches the generator, which needs none of that file.
#
# Usage:  zsh Scripts/setup_lama_env.sh

set -euo pipefail

VENV="${LAMA_VENV:-$HOME/.venvs/lama}"
REPO="${LAMA_REPO:-$HOME/src/lama}"
MODELS="${LAMA_MODELS:-$HOME/models}"
CHECKPOINT="$MODELS/big-lama"

# --- Python ----------------------------------------------------------------
# Xcode ships 3.9, which is old enough that several of these packages have no
# wheel for it. 3.11 and 3.12 both have wheels for torch and coremltools.
PYTHON=""
for candidate in python3.12 python3.11 /opt/homebrew/bin/python3.12 \
                 /opt/homebrew/bin/python3.11 /usr/local/bin/python3.12; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PYTHON="$(command -v "$candidate")"
    break
  fi
done

if [[ -z "$PYTHON" ]]; then
  cat <<'MESSAGE' >&2
No Python 3.11/3.12 found — only Xcode's 3.9, which cannot install these wheels.

    brew install python@3.12

then run this script again.
MESSAGE
  exit 1
fi
echo "==> Python: $PYTHON ($("$PYTHON" -V))"

# --- Virtual environment ---------------------------------------------------
if [[ ! -d "$VENV" ]]; then
  echo "==> Creating $VENV"
  "$PYTHON" -m venv "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --quiet --upgrade pip wheel setuptools

echo "==> Installing packages (torch is ~200 MB, this takes a few minutes)"
# torch is capped: coremltools' TorchScript frontend is only tested up to 2.7, and
# a newer torch emits operators its converter has never seen.
python -m pip install \
  "numpy>=1.26" \
  "torch>=2.2,<2.8" \
  "omegaconf>=2.3" \
  "kornia>=0.7" \
  "coremltools>=8.0"

# --- Source tree -----------------------------------------------------------
# Only `saicinpainting.training.modules` is imported, for the FFC generator.
# kornia is in the list above because that package imports it.
if [[ ! -d "$REPO" ]]; then
  echo "==> Cloning advimman/lama into $REPO"
  mkdir -p "$(dirname "$REPO")"
  git clone --depth 1 https://github.com/advimman/lama "$REPO"
else
  echo "==> Reusing $REPO"
fi

# --- Checkpoint ------------------------------------------------------------
if [[ ! -f "$CHECKPOINT/models/best.ckpt" ]]; then
  echo "==> Downloading big-lama (~400 MB)"
  mkdir -p "$MODELS"
  curl -L --fail --progress-bar \
    -o "$MODELS/big-lama.zip" \
    https://huggingface.co/smartywu/big-lama/resolve/main/big-lama.zip
  unzip -q -o "$MODELS/big-lama.zip" -d "$MODELS"
  rm -f "$MODELS/big-lama.zip"
else
  echo "==> Reusing $CHECKPOINT"
fi

cat <<MESSAGE

Ready. Convert with:

    source $VENV/bin/activate
    python3 Scripts/convert_lama_coreml.py --lama-repo $REPO --checkpoint $CHECKPOINT

MESSAGE
