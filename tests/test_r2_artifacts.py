from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import r2_artifacts


class FakeClientError(Exception):
    operation_name = "PutObject"
    response = {
        "Error": {
            "Code": "AccessDenied",
            "Message": "Access Denied",
        }
    }


class R2ArtifactsTests(unittest.TestCase):
    def test_default_key_uses_repo_relative_posix_path(self) -> None:
        path = r2_artifacts.REPO_ROOT / "data" / "tanzil" / "quran-simple-clean.txt"

        self.assertEqual(
            r2_artifacts.default_object_key(path),
            "data/tanzil/quran-simple-clean.txt",
        )

    def test_default_key_rejects_paths_outside_repo(self) -> None:
        outside_path = Path(tempfile.gettempdir()) / "outside.txt"

        with self.assertRaisesRegex(ValueError, "outside the repository"):
            r2_artifacts.default_object_key(outside_path)

    def test_iter_upload_files_skips_hidden_platform_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            keep = root / "audio.wav"
            skip = root / ".DS_Store"
            nested = root / "nested"
            nested.mkdir()
            nested_keep = nested / "clip.wav"
            keep.write_text("audio", encoding="utf-8")
            skip.write_text("platform metadata", encoding="utf-8")
            nested_keep.write_text("clip", encoding="utf-8")

            upload_files = list(r2_artifacts.iter_upload_files(root))

        self.assertEqual(upload_files, [keep, nested_keep])

    def test_env_validation_requires_s3_credentials_not_cloudflare_api_token(self) -> None:
        env = {
            "R2_ENDPOINT_URL": "https://example.r2.cloudflarestorage.com",
            "R2_BUCKET": "tarteel-realtime",
            "CLOUDFLARE_API_TOKEN": "general-api-token-placeholder",
        }

        with mock.patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "R2_ACCESS_KEY_ID"):
                r2_artifacts.load_r2_config()

    def test_r2_errors_are_reported_without_traceback_noise(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "AccessDenied.*PutObject"):
            r2_artifacts.raise_r2_error(FakeClientError())


if __name__ == "__main__":
    unittest.main()
