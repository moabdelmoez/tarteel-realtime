from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "App"
PROJECT_FILE = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype.xcodeproj" / "project.pbxproj"


class IOSLiveKitVADSourceTests(unittest.TestCase):
    def test_livekit_client_is_guarded_until_sdk_is_linked(self) -> None:
        source = (APP_ROOT / "LiveKitRecitationClient.swift").read_text(encoding="utf-8")

        self.assertIn("#if canImport(LiveKit)", source)
        self.assertIn("setMicrophone(enabled: true)", source)
        self.assertIn("didReceiveData data", source)
        self.assertIn("encryptionType: EncryptionType", source)
        self.assertIn("tarteel.recitation.event", source)

    def test_voice_activity_detector_is_guarded_until_fluidaudio_is_linked(self) -> None:
        source = (APP_ROOT / "VoiceActivityDetector.swift").read_text(encoding="utf-8")

        self.assertIn("#if canImport(FluidAudio)", source)
        self.assertIn("VadManager", source)
        self.assertIn("VadManager.chunkSize", source)
        self.assertIn("manager.process(chunk)", source)
        self.assertIn("VoiceActivityPayload", source)

    def test_new_app_sources_are_in_xcode_project(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")

        self.assertIn("LiveKitRecitationClient.swift", project)
        self.assertIn("VoiceActivityDetector.swift", project)

    def test_livekit_and_fluidaudio_packages_are_linked_to_app_target(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")

        self.assertIn("https://github.com/livekit/client-sdk-swift.git", project)
        self.assertIn("https://github.com/FluidInference/FluidAudio.git", project)
        self.assertIn("LiveKit in Frameworks", project)
        self.assertIn("FluidAudio in Frameworks", project)


if __name__ == "__main__":
    unittest.main()
