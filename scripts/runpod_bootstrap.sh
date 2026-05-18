#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${TARTEEL_REPO_URL:-https://github.com/moabdelmoez/tarteel-realtime.git}"
APP_DIR="${TARTEEL_APP_DIR:-/workspace/tarteel-realtime}"

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ffmpeg
fi

if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"

export UV_CACHE_DIR="${UV_CACHE_DIR:-/workspace/.cache/uv}"
export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
export TORCH_HOME="${TORCH_HOME:-/workspace/.cache/torch}"
mkdir -p "$UV_CACHE_DIR" "$HF_HOME" "$TORCH_HOME"

if [ "${TARTEEL_DOWNLOAD_R2_ARTIFACTS:-0}" = "1" ]; then
  uv run --with boto3 python scripts/r2_artifacts.py download data/tanzil/quran-simple-clean.txt --destination data/tanzil/quran-simple-clean.txt
fi

uv run python -m compileall -q tarteel_realtime tests scripts

if [ -f data/tanzil/quran-simple-clean.txt ]; then
  uv run python -m tarteel_realtime.quran_data --check-manifest
fi

if [ "${TARTEEL_RUN_TESTS:-1}" = "1" ]; then
  uv run python -B -m unittest discover
fi
