from __future__ import annotations

from pathlib import Path, PurePosixPath

import modal


APP_NAME = "tarteel-realtime-asr"
SECRET_NAME = "tarteel-modal-asr-secrets"
MODEL_VOLUME_NAME = "tarteel-asr-model-cache"
HF_CACHE_ROOT = PurePosixPath("/models/huggingface-cache/hub")
TANZIL_PATH = PurePosixPath("/root/data/tanzil/quran-simple-clean.txt")
DEFAULT_MODEL_ID = "mohammed/fastconformer-quran-ar"
DEFAULT_NEMO_MODEL_FILE = "phase3_full/phase3_full_wer0.0014.nemo"
DEFAULT_ASR_MODEL = "nemo-fastconformer-quran-ar"
CUDA_IMAGE_TAG = "12.4.1-cudnn-runtime-ubuntu22.04"

PROJECT_RUNTIME_DEPENDENCIES = (
    "fastapi>=0.115.0",
    "httpx>=0.28.0",
    "rapidfuzz>=3",
    "uvicorn[standard]>=0.34.0",
)
MODAL_ASR_DEPENDENCIES = (
    "nemo_toolkit[asr]",
    "faster-whisper",
    "huggingface_hub",
)

RUNTIME_ENV = {
    "TARTEEL_TANZIL_PATH": str(TANZIL_PATH),
    "TARTEEL_HF_CACHE_ROOT": str(HF_CACHE_ROOT),
    "HF_HUB_CACHE": str(HF_CACHE_ROOT),
    "TARTEEL_ASR_BUFFERING_PROFILE": "low-latency",
    "TARTEEL_ASR_MIN_AUDIO_MS": "3000",
    "TARTEEL_ASR_FLUSH_MS": "3000",
    "TARTEEL_ASR_TAIL_MS": "2500",
    "TARTEEL_ASR_SPEECH_END_MIN_AUDIO_MS": "1500",
    "TARTEEL_ASR_FLUSH_ON_SPEECH_END": "1",
}

MODAL_ASR_MODEL_PROFILES = {
    "nemo-fastconformer-quran-ar": {
        "TARTEEL_ASR_BACKEND": "nemo",
        "TARTEEL_ASR_MODEL_ID": DEFAULT_MODEL_ID,
        "TARTEEL_NEMO_MODEL_FILE": DEFAULT_NEMO_MODEL_FILE,
        "TARTEEL_ASR_DEVICE": "cuda:0",
    },
    "faster-whisper-base-ar-quran": {
        "TARTEEL_ASR_BACKEND": "faster-whisper",
        "TARTEEL_ASR_MODEL_ID": "OdyAsh/faster-whisper-base-ar-quran",
        "TARTEEL_ASR_DEVICE": "cuda:0",
        "TARTEEL_FASTER_WHISPER_COMPUTE_TYPE": "float16",
    },
}


model_cache_volume = modal.Volume.from_name(MODEL_VOLUME_NAME, create_if_missing=True)

image = (
    modal.Image.from_registry(f"nvidia/cuda:{CUDA_IMAGE_TAG}", add_python="3.13")
    .entrypoint([])
    .apt_install("git", "clang", "build-essential")
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
    import os

    from tarteel_realtime.asr_app import create_model_selecting_asr_app
    from tarteel_realtime.asr_runtime import settings_from_env

    settings_by_asr_model = {}
    for asr_model, profile in MODAL_ASR_MODEL_PROFILES.items():
        values = dict(os.environ)
        values.update(profile)
        settings_by_asr_model[asr_model] = settings_from_env(values)

    return create_model_selecting_asr_app(
        settings_by_asr_model,
        default_asr_model=DEFAULT_ASR_MODEL,
    )


@app.function(
    timeout=60 * 30,
    volumes={str(HF_CACHE_ROOT): model_cache_volume},
)
def prewarm_models() -> tuple[str, ...]:
    from huggingface_hub import snapshot_download

    warmed_paths = []
    for profile in MODAL_ASR_MODEL_PROFILES.values():
        snapshot_path = snapshot_download(
            repo_id=profile["TARTEEL_ASR_MODEL_ID"],
            cache_dir=str(HF_CACHE_ROOT),
        )
        if profile.get("TARTEEL_NEMO_MODEL_FILE"):
            model_path = Path(snapshot_path) / profile["TARTEEL_NEMO_MODEL_FILE"]
            if not model_path.exists():
                raise FileNotFoundError(
                    "Missing NeMo model file in Hugging Face snapshot: "
                    f"{profile['TARTEEL_NEMO_MODEL_FILE']}"
                )
            warmed_paths.append(str(model_path))
        else:
            warmed_paths.append(snapshot_path)
    model_cache_volume.commit()
    return tuple(warmed_paths)


@app.local_entrypoint()
def prewarm() -> None:
    for path in prewarm_models.remote():
        print(path)
