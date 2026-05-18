from __future__ import annotations

import unittest
from pathlib import Path


SCRIPT = Path("scripts/runpod_bootstrap.sh").read_text(encoding="utf-8")


class RunPodBootstrapTests(unittest.TestCase):
    def test_downloads_real_proof_artifacts_from_r2(self) -> None:
        for key in (
            "data/tanzil/quran-simple-clean.txt",
            "fixtures/local_audio/114001.mp3",
            "fixtures/local_audio/114002.mp3",
        ):
            with self.subTest(key=key):
                self.assertIn(f'download_r2_artifact "{key}"', SCRIPT)

    def test_converts_local_audio_mp3s_to_mono_pcm_wavs(self) -> None:
        for sample in ("114001", "114002"):
            with self.subTest(sample=sample):
                self.assertIn(
                    f'prepare_wav "fixtures/local_audio/{sample}.mp3" "fixtures/local_audio/{sample}.wav"',
                    SCRIPT,
                )

        self.assertIn("-ac 1", SCRIPT)
        self.assertIn("-ar 16000", SCRIPT)
        self.assertIn("-sample_fmt s16", SCRIPT)


if __name__ == "__main__":
    unittest.main()
