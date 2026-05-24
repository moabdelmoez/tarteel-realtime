#!/usr/bin/env bash
set -euo pipefail

export TARTEEL_TANZIL_PATH="${TARTEEL_TANZIL_PATH:-/app/data/tanzil/quran-simple-clean.txt}"
export TARTEEL_WHISPER_BACKEND="${TARTEEL_WHISPER_BACKEND:-faster-whisper}"
export TARTEEL_WHISPER_MODEL_ID="${TARTEEL_WHISPER_MODEL_ID:-OdyAsh/faster-whisper-base-ar-quran}"
export TARTEEL_WHISPER_DEVICE="${TARTEEL_WHISPER_DEVICE:-cuda:0}"
export TARTEEL_FASTER_WHISPER_COMPUTE_TYPE="${TARTEEL_FASTER_WHISPER_COMPUTE_TYPE:-float16}"
export TARTEEL_HF_CACHE_ROOT="${TARTEEL_HF_CACHE_ROOT:-/runpod-volume/huggingface-cache/hub}"
export TARTEEL_ASR_BUFFERING_PROFILE="${TARTEEL_ASR_BUFFERING_PROFILE:-low-latency}"

exec uv run --with faster-whisper uvicorn tarteel_realtime.asr_app:create_app_from_env \
  --factory \
  --host 0.0.0.0 \
  --port "${PORT:-8000}"
