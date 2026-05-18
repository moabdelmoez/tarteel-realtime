import hashlib
import io
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tarteel_realtime.evaluate import DEFAULT_TANZIL_PATH as EVALUATE_DEFAULT_TANZIL_PATH
from tarteel_realtime.quran_data import (
    DEFAULT_MANIFEST_PATH,
    DEFAULT_TANZIL_PATH,
    inspect_tanzil_file,
    load_manifest,
    main,
    validate_tanzil_file,
    write_manifest,
)


SAMPLE_TANZIL_TEXT = "\n".join([
    "# local smoke fixture",
    "1|1|بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
])


class TanzilManifestTests(unittest.TestCase):
    def test_default_data_paths_match_evaluator_default(self):
        self.assertEqual(DEFAULT_TANZIL_PATH, Path("data/tanzil/quran-simple-clean.txt"))
        self.assertEqual(DEFAULT_MANIFEST_PATH, Path("data/tanzil/quran-simple-clean.metadata.json"))
        self.assertEqual(EVALUATE_DEFAULT_TANZIL_PATH, DEFAULT_TANZIL_PATH)

    def test_inspects_tanzil_file_with_checksum_and_reference_bounds(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "quran-simple-clean.txt"
            path.write_text(SAMPLE_TANZIL_TEXT, encoding="utf-8")

            manifest = inspect_tanzil_file(
                path,
                source_name="Tanzil",
                source_url="https://example.invalid/quran-simple-clean.txt",
            )

        self.assertEqual(manifest.format, "tanzil-pipe-v1")
        self.assertEqual(manifest.path, str(path))
        self.assertEqual(manifest.source_name, "Tanzil")
        self.assertEqual(manifest.source_url, "https://example.invalid/quran-simple-clean.txt")
        self.assertEqual(manifest.sha256, hashlib.sha256(SAMPLE_TANZIL_TEXT.encode("utf-8")).hexdigest())
        self.assertEqual(manifest.bytes, len(SAMPLE_TANZIL_TEXT.encode("utf-8")))
        self.assertEqual(manifest.ayah_count, 2)
        self.assertEqual(manifest.first_ref, "1:1")
        self.assertEqual(manifest.last_ref, "114:1")

    def test_writes_loads_and_validates_manifest_against_current_file(self):
        with TemporaryDirectory() as directory:
            directory_path = Path(directory)
            tanzil_path = directory_path / "quran-simple-clean.txt"
            manifest_path = directory_path / "quran-simple-clean.metadata.json"
            tanzil_path.write_text(SAMPLE_TANZIL_TEXT, encoding="utf-8")
            manifest = inspect_tanzil_file(tanzil_path, source_name="Tanzil")

            write_manifest(manifest, manifest_path)

            self.assertEqual(load_manifest(manifest_path), manifest)
            self.assertEqual(validate_tanzil_file(tanzil_path, manifest_path), manifest)

            tanzil_path.write_text(SAMPLE_TANZIL_TEXT + "\n2|1|الم", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Tanzil checksum mismatch"):
                validate_tanzil_file(tanzil_path, manifest_path)

    def test_cli_writes_and_checks_manifest(self):
        with TemporaryDirectory() as directory:
            directory_path = Path(directory)
            tanzil_path = directory_path / "quran-simple-clean.txt"
            manifest_path = directory_path / "quran-simple-clean.metadata.json"
            tanzil_path.write_text(SAMPLE_TANZIL_TEXT, encoding="utf-8")
            output = io.StringIO()

            write_exit_code = main([
                "--tanzil-path",
                str(tanzil_path),
                "--manifest-path",
                str(manifest_path),
                "--source-name",
                "Tanzil",
                "--write-manifest",
            ], stdout=output)
            check_exit_code = main([
                "--tanzil-path",
                str(tanzil_path),
                "--manifest-path",
                str(manifest_path),
                "--check-manifest",
            ], stdout=io.StringIO())

            payload = json.loads(output.getvalue())
            manifest_exists = manifest_path.exists()

        self.assertEqual(write_exit_code, 0)
        self.assertEqual(check_exit_code, 0)
        self.assertEqual(payload["source_name"], "Tanzil")
        self.assertEqual(payload["ayah_count"], 2)
        self.assertTrue(manifest_exists)


if __name__ == "__main__":
    unittest.main()
