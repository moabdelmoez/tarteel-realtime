#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${TARTEEL_REPO_URL:-https://github.com/moabdelmoez/tarteel-realtime.git}"
APP_DIR="${TARTEEL_APP_DIR:-/workspace/tarteel-realtime}"

download_r2_artifact() {
  local key="$1"
  uv run --with boto3 python scripts/r2_artifacts.py download "$key" --destination "$key"
}

prepare_wav() {
  local source_mp3="$1"
  local target_wav="$2"

  if [ ! -f "$source_mp3" ]; then
    echo "Skipping WAV preparation; missing $source_mp3" >&2
    return 0
  fi

  if [ -f "$target_wav" ] && [ "$target_wav" -nt "$source_mp3" ]; then
    echo "Keeping existing $target_wav"
    return 0
  fi

  mkdir -p "$(dirname "$target_wav")"
  ffmpeg -y -i "$source_mp3" -ac 1 -ar 16000 -sample_fmt s16 "$target_wav"
}

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
  download_r2_artifact "data/tanzil/quran-simple-clean.txt"
  download_r2_artifact "fixtures/local_audio/114001.mp3"
  download_r2_artifact "fixtures/local_audio/114002.mp3"
fi

if [ "${TARTEEL_PREPARE_AUDIO_WAVS:-${TARTEEL_DOWNLOAD_R2_ARTIFACTS:-0}}" = "1" ]; then
  prepare_wav "fixtures/local_audio/114001.mp3" "fixtures/local_audio/114001.wav"
  prepare_wav "fixtures/local_audio/114002.mp3" "fixtures/local_audio/114002.wav"
fi

uv run python -m compileall -q tarteel_realtime tests scripts

if [ -f data/tanzil/quran-simple-clean.txt ]; then
  uv run python -m tarteel_realtime.quran_data --check-manifest
fi

if [ "${TARTEEL_RUN_TESTS:-1}" = "1" ]; then
  uv run python -B -m unittest discover
fi
