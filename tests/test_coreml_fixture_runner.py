from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
PACKAGE_PATH = REPO_ROOT / "ios" / "TarteelClientCore" / "Package.swift"
RUNNER_PATH = REPO_ROOT / "ios" / "TarteelClientCore" / "Sources" / "CoreMLFixtureRunner" / "main.swift"
MANIFEST_PATH = REPO_ROOT / "fixtures" / "local_audio_manifest.json"


class CoreMLFixtureRunnerTests(unittest.TestCase):
    def test_swift_package_declares_coreml_fixture_runner(self) -> None:
        package = PACKAGE_PATH.read_text(encoding="utf-8")

        self.assertIn('name: "coreml-fixture-runner"', package)
        self.assertIn('.executableTarget(', package)
        self.assertIn('name: "CoreMLFixtureRunner"', package)
        self.assertIn('"TarteelClientCore"', package)

    def test_runner_accepts_model_and_audio_fixture_paths(self) -> None:
        source = RUNNER_PATH.read_text(encoding="utf-8")

        self.assertIn("--model-dir", source)
        self.assertIn("--audio-dir", source)
        self.assertIn("--audio", source)
        self.assertIn("--json", source)
        self.assertIn("--manifest", source)
        self.assertIn("CoreMLFastConformerFixtureRunner", source)
        self.assertIn("CoreMLFastConformerFixtureManifest", source)
        self.assertIn("textSummary()", source)

    def test_local_audio_manifest_maps_existing_fixture_names_to_expected_refs(self) -> None:
        source = MANIFEST_PATH.read_text(encoding="utf-8")

        for audio_name, ayah_ref in (
            ("004001.wav", "4:1"),
            ("004002.wav", "4:2"),
            ("004003.wav", "4:3"),
            ("108001.wav", "108:1"),
            ("108002.wav", "108:2"),
            ("108003.wav", "108:3"),
        ):
            self.assertIn(f'"audio_file": "{audio_name}"', source)
            self.assertIn(f'"ayah_ref": "{ayah_ref}"', source)


if __name__ == "__main__":
    unittest.main()
