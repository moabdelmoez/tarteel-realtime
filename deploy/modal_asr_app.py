from __future__ import annotations

from pathlib import PurePosixPath

import modal


APP_NAME = "tarteel-realtime-asr"
SECRET_NAME = "tarteel-modal-asr-secrets"
MODEL_VOLUME_NAME = "tarteel-asr-model-cache"
HF_CACHE_ROOT = PurePosixPath("/models/huggingface-cache/hub")
TANZIL_PATH = PurePosixPath("/root/data/tanzil/quran-simple-clean.txt")
DEFAULT_MODEL_ID = "OdyAsh/faster-whisper-base-ar-quran"
CUDA_IMAGE_TAG = "12.4.1-cudnn-runtime-ubuntu22.04"

PROJECT_RUNTIME_DEPENDENCIES = (
    "fastapi>=0.115.0",
    "httpx>=0.28.0",
    "rapidfuzz>=3",
    "uvicorn[standard]>=0.34.0",
)
MODAL_ASR_DEPENDENCIES = (
    "faster-whisper",
    "huggingface_hub",
)

RUNTIME_ENV = {
    "TARTEEL_TANZIL_PATH": str(TANZIL_PATH),
    "TARTEEL_WHISPER_BACKEND": "faster-whisper",
    "TARTEEL_WHISPER_MODEL_ID": DEFAULT_MODEL_ID,
    "TARTEEL_WHISPER_DEVICE": "cuda:0",
    "TARTEEL_FASTER_WHISPER_COMPUTE_TYPE": "float16",
    "TARTEEL_HF_CACHE_ROOT": str(HF_CACHE_ROOT),
    "TARTEEL_ASR_BUFFERING_PROFILE": "low-latency",
}


model_cache_volume = modal.Volume.from_name(MODEL_VOLUME_NAME, create_if_missing=True)

image = (
    modal.Image.from_registry(f"nvidia/cuda:{CUDA_IMAGE_TAG}", add_python="3.13")
    .entrypoint([])
    .apt_install("git")
    .uv_pip_install(*PROJECT_RUNTIME_DEPENDENCIES, *MODAL_ASR_DEPENDENCIES)
    .add_local_python_source("tarteel_realtime", copy=True)
    .add_local_dir("data", "/root/data", copy=True)
    .env({"UV_NO_PROGRESS": "1"})
)

app = modal.App(APP_NAME, image=image)


@app.function(
    gpu="L4",
    min_containers=0,
    max_containers=1,
    scaledown_window=60,
    volumes={str(HF_CACHE_ROOT): model_cache_volume},
    secrets=[modal.Secret.from_name(SECRET_NAME)],
    env=RUNTIME_ENV,
)
@modal.concurrent(max_inputs=4)
@modal.asgi_app()
def fastapi_app():
    from tarteel_realtime.asr_app import create_app_from_env

    return create_app_from_env()


@app.function(
    timeout=60 * 30,
    volumes={str(HF_CACHE_ROOT): model_cache_volume},
)
def prewarm_model(model_id: str = DEFAULT_MODEL_ID) -> str:
    from huggingface_hub import snapshot_download

    snapshot_path = snapshot_download(
        repo_id=model_id,
        cache_dir=str(HF_CACHE_ROOT),
    )
    model_cache_volume.commit()
    return snapshot_path


@app.local_entrypoint()
def prewarm(model_id: str = DEFAULT_MODEL_ID) -> None:
    print(prewarm_model.remote(model_id))
