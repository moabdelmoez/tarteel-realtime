#!/usr/bin/env bash
set -euo pipefail

if [ -d "/workspace" ]; then
  DEFAULT_APP_DIR="/workspace/tarteel-realtime"
  DEFAULT_CACHE_ROOT="/workspace/.cache"
else
  DEFAULT_APP_DIR="$HOME/tarteel-realtime"
  DEFAULT_CACHE_ROOT="$HOME/.cache"
fi

REPO_URL="${TARTEEL_REPO_URL:-https://github.com/moabdelmoez/tarteel-realtime.git}"
APP_DIR="${TARTEEL_APP_DIR:-$DEFAULT_APP_DIR}"
CACHE_ROOT="${TARTEEL_CACHE_ROOT:-$DEFAULT_CACHE_ROOT}"
GIT_REF="${TARTEEL_GIT_REF:-}"
export GIT_TERMINAL_PROMPT="${GIT_TERMINAL_PROMPT:-0}"

DOWNLOAD_R2_ARTIFACTS="${TARTEEL_DOWNLOAD_ARTIFACTS:-${TARTEEL_DOWNLOAD_R2_ARTIFACTS:-0}}"
PREPARE_AUDIO_WAVS="${TARTEEL_PREPARE_AUDIO_WAVS:-$DOWNLOAD_R2_ARTIFACTS}"
LOCAL_AUDIO_SAMPLES="${TARTEEL_LOCAL_AUDIO_SAMPLES:-004001 004002 004003 108001 108002 108003}"

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

checkout_git_ref() {
  if [ -z "$GIT_REF" ]; then
    git pull --ff-only
    return 0
  fi

  git fetch origin
  git checkout "$GIT_REF"
  if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    git pull --ff-only
  fi
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
  git -C "$APP_DIR" fetch origin
else
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"
checkout_git_ref

export UV_CACHE_DIR="${UV_CACHE_DIR:-$CACHE_ROOT/uv}"
export HF_HOME="${HF_HOME:-$CACHE_ROOT/huggingface}"
export TORCH_HOME="${TORCH_HOME:-$CACHE_ROOT/torch}"
mkdir -p "$UV_CACHE_DIR" "$HF_HOME" "$TORCH_HOME"

if [ "$DOWNLOAD_R2_ARTIFACTS" = "1" ]; then
  download_r2_artifact "data/tanzil/quran-simple-clean.txt"
  for sample in $LOCAL_AUDIO_SAMPLES; do
    download_r2_artifact "fixtures/local_audio/${sample}.mp3"
  done
fi

if [ "$PREPARE_AUDIO_WAVS" = "1" ]; then
  for sample in $LOCAL_AUDIO_SAMPLES; do
    prepare_wav "fixtures/local_audio/${sample}.mp3" "fixtures/local_audio/${sample}.wav"
  done
fi

uv run python -m compileall -q tarteel_realtime tests scripts

if [ -f data/tanzil/quran-simple-clean.txt ]; then
  uv run python -m tarteel_realtime.quran_data --check-manifest
fi

if [ "${TARTEEL_RUN_TESTS:-1}" = "1" ]; then
  uv run python -B -m unittest discover
fi
