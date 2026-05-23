from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "App"
PROJECT_PATH = (
    REPO_ROOT
    / "ios"
    / "TarteelPrototype"
    / "TarteelPrototype.xcodeproj"
    / "project.pbxproj"
)


class IOSWebSocketVADSourceTests(unittest.TestCase):
    def test_voice_activity_detector_is_guarded_until_fluidaudio_is_linked(self) -> None:
        source = (APP_ROOT / "VoiceActivityDetector.swift").read_text(encoding="utf-8")

        self.assertIn("#if canImport(FluidAudio)", source)
        self.assertIn("return nil", source)

    def test_voice_activity_detector_prefers_bundled_silero_coreml_model(self) -> None:
        source = (APP_ROOT / "VoiceActivityDetector.swift").read_text(encoding="utf-8")

        self.assertIn("silero-vad-unified-256ms-v6.0.0", source)
        self.assertIn("MLModel(contentsOf: modelURL", source)
        self.assertIn(".cpuOnly", source)

    def test_voice_activity_detector_resets_stream_state_on_stop(self) -> None:
        source = (APP_ROOT / "VoiceActivityDetector.swift").read_text(encoding="utf-8")
        view_model = (APP_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertIn("func reset() async", source)
        self.assertIn("await voiceActivityDetector.reset()", view_model)

    def test_websocket_path_uses_app_microphone_streamer_and_vad_before_transport(self) -> None:
        view_model = (APP_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertIn("audioStreamer.start", view_model)
        self.assertIn("voiceActivityDetector.process", view_model)
        self.assertIn("AudioChunkPayload(", view_model)
        self.assertIn("socketClient.send(payload)", view_model)

    def test_fluidaudio_package_remains_linked_for_websocket_vad(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")

        self.assertIn("https://github.com/FluidInference/FluidAudio.git", project)
        self.assertIn("FluidAudio in Frameworks", project)

    def test_silero_vad_coreml_bundle_is_packaged_with_ios_app(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")

        self.assertIn("silero-vad-unified-256ms-v6.0.0.mlmodelc in Resources", project)


if __name__ == "__main__":
    unittest.main()
