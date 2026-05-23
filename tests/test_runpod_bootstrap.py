from __future__ import annotations

import unittest
from pathlib import Path


RUNPOD_SCRIPT = Path("scripts/runpod_bootstrap.sh").read_text(encoding="utf-8")
GPU_SCRIPT = Path("scripts/gpu_bootstrap.sh").read_text(encoding="utf-8")


class RunPodBootstrapTests(unittest.TestCase):
    def test_runpod_script_delegates_to_gpu_bootstrap(self) -> None:
        self.assertIn('exec "$SCRIPT_DIR/gpu_bootstrap.sh" "$@"', RUNPOD_SCRIPT)

    def test_downloads_real_proof_artifacts_from_r2(self) -> None:
        for key in (
            "data/tanzil/quran-simple-clean.txt",
            "fixtures/local_audio/${sample}.mp3",
        ):
            with self.subTest(key=key):
                self.assertIn(f'download_r2_artifact "{key}"', GPU_SCRIPT)

    def test_converts_local_audio_mp3s_to_mono_pcm_wavs(self) -> None:
        for sample in ("004001", "004002", "004003", "108001", "108002", "108003"):
            with self.subTest(sample=sample):
                self.assertIn(sample, GPU_SCRIPT)

        self.assertIn('LOCAL_AUDIO_SAMPLES="${TARTEEL_LOCAL_AUDIO_SAMPLES:-004001 004002 004003 108001 108002 108003}"', GPU_SCRIPT)
        self.assertIn('prepare_wav "fixtures/local_audio/${sample}.mp3" "fixtures/local_audio/${sample}.wav"', GPU_SCRIPT)
        self.assertIn("-ac 1", GPU_SCRIPT)
        self.assertIn("-ar 16000", GPU_SCRIPT)
        self.assertIn("-sample_fmt s16", GPU_SCRIPT)

    def test_git_clone_fails_fast_without_interactive_credential_prompt(self) -> None:
        self.assertIn('export GIT_TERMINAL_PROMPT="${GIT_TERMINAL_PROMPT:-0}"', GPU_SCRIPT)

    def test_supports_generic_artifact_flag_with_runpod_compatibility(self) -> None:
        self.assertIn(
            'DOWNLOAD_R2_ARTIFACTS="${TARTEEL_DOWNLOAD_ARTIFACTS:-${TARTEEL_DOWNLOAD_R2_ARTIFACTS:-0}}"',
            GPU_SCRIPT,
        )

    def test_uses_workspace_defaults_with_home_fallback(self) -> None:
        self.assertIn('if [ -d "/workspace" ]; then', GPU_SCRIPT)
        self.assertIn('DEFAULT_APP_DIR="/workspace/tarteel-realtime"', GPU_SCRIPT)
        self.assertIn('DEFAULT_APP_DIR="$HOME/tarteel-realtime"', GPU_SCRIPT)

    def test_can_checkout_requested_git_ref_for_branch_testing(self) -> None:
        self.assertIn('GIT_REF="${TARTEEL_GIT_REF:-}"', GPU_SCRIPT)
        self.assertIn('checkout_git_ref', GPU_SCRIPT)
        self.assertIn('git checkout "$GIT_REF"', GPU_SCRIPT)


if __name__ == "__main__":
    unittest.main()
