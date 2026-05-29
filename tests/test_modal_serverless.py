from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
MODAL_APP = REPO_ROOT / "deploy" / "modal_asr_app.py"


class ModalServerlessTests(unittest.TestCase):
    def test_modal_adapter_serves_existing_asgi_app(self) -> None:
        source = MODAL_APP.read_text(encoding="utf-8")

        self.assertIn("@modal.asgi_app()", source)
        self.assertIn("from tarteel_realtime.asr_app import create_app_from_env", source)
        self.assertIn("return create_app_from_env()", source)

    def test_modal_adapter_uses_controlled_gpu_autoscaling_defaults(self) -> None:
        source = MODAL_APP.read_text(encoding="utf-8")

        self.assertIn('gpu="L4"', source)
        self.assertIn("min_containers=0", source)
        self.assertIn("max_containers=1", source)
        self.assertIn("scaledown_window=60", source)
        self.assertIn("@modal.concurrent(max_inputs=4)", source)

    def test_modal_adapter_uses_volume_for_huggingface_cache(self) -> None:
        source = MODAL_APP.read_text(encoding="utf-8")

        self.assertIn('MODEL_VOLUME_NAME = "tarteel-asr-model-cache"', source)
        self.assertIn('HF_CACHE_ROOT = PurePosixPath("/models/huggingface-cache/hub")', source)
        self.assertIn("modal.Volume.from_name(MODEL_VOLUME_NAME", source)
        self.assertIn("snapshot_download(", source)
        self.assertIn("cache_dir=str(HF_CACHE_ROOT)", source)
        self.assertIn("model_cache_volume.commit()", source)

    def test_modal_adapter_keeps_heavy_dependencies_out_of_default_project(self) -> None:
        source = MODAL_APP.read_text(encoding="utf-8")
        pyproject = (REPO_ROOT / "pyproject.toml").read_text(encoding="utf-8")

        self.assertIn('CUDA_IMAGE_TAG = "12.4.1-cudnn-runtime-ubuntu22.04"', source)
        self.assertIn('modal.Image.from_registry(f"nvidia/cuda:{CUDA_IMAGE_TAG}", add_python="3.13")', source)
        self.assertIn(".entrypoint([])", source)
        self.assertIn(".uv_pip_install(*PROJECT_RUNTIME_DEPENDENCIES, *MODAL_ASR_DEPENDENCIES)", source)
        self.assertIn('"fastapi>=0.115.0"', source)
        self.assertIn('"uvicorn[standard]>=0.34.0"', source)
        self.assertIn('"faster-whisper"', source)
        self.assertNotIn(".uv_sync()", source)
        self.assertNotIn("modal", pyproject)
        self.assertNotIn("faster-whisper", pyproject)

    def test_modal_adapter_uses_provider_neutral_bearer_secret(self) -> None:
        source = MODAL_APP.read_text(encoding="utf-8")

        self.assertIn('SECRET_NAME = "tarteel-modal-asr-secrets"', source)
        self.assertIn("modal.Secret.from_name(SECRET_NAME)", source)
        self.assertIn('"TARTEEL_HF_CACHE_ROOT": str(HF_CACHE_ROOT)', source)


if __name__ == "__main__":
    unittest.main()
