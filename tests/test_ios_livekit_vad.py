from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "App"
MODEL_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "Models"
PROJECT_FILE = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype.xcodeproj" / "project.pbxproj"
SILERO_VAD_MODEL = "silero-vad-unified-256ms-v6.0.0.mlmodelc"


class IOSLiveKitVADSourceTests(unittest.TestCase):
    def test_livekit_client_is_guarded_until_sdk_is_linked(self) -> None:
        source = (APP_ROOT / "LiveKitRecitationClient.swift").read_text(encoding="utf-8")

        self.assertIn("#if canImport(LiveKit)", source)
        self.assertIn("setMicrophone(enabled: true)", source)
        self.assertIn("AudioManager.shared.setManualRenderingMode(true)", source)
        self.assertIn("AudioManager.shared.mixer.capture(appAudio:", source)
        self.assertIn("didReceiveData data", source)
        self.assertIn("encryptionType: EncryptionType", source)
        self.assertIn("tarteel.recitation.event", source)
        self.assertIn("tarteel.voice_activity", source)

    def test_livekit_client_publishes_vad_metadata_and_gates_app_audio(self) -> None:
        source = (APP_ROOT / "LiveKitRecitationClient.swift").read_text(encoding="utf-8")

        self.assertIn("func publishAudio(", source)
        self.assertIn("voiceActivity: VoiceActivityPayload?", source)
        self.assertIn("LiveKitVoiceActivityMessage", source)
        self.assertIn("DataPublishOptions(topic: liveKitVoiceActivityTopic)", source)
        self.assertIn("room.localParticipant.publish(data:", source)
        self.assertIn("shouldPublishAudio(for: voiceActivity)", source)
        self.assertIn("voiceActivity.isSpeechActive", source)
        self.assertIn("voiceActivity.event == .speechStart", source)
        self.assertIn("voiceActivity.event == .speechEnd", source)
        self.assertIn("pcm.pcm16AudioBuffer(sampleRate:", source)

    def test_livekit_client_mutable_callback_is_main_actor_isolated(self) -> None:
        source = (APP_ROOT / "LiveKitRecitationClient.swift").read_text(encoding="utf-8")

        self.assertIn("@MainActor\nfinal class LiveKitRecitationClient: NSObject", source)
        self.assertIn("nonisolated func room(", source)
        self.assertIn("Task { @MainActor [weak self] in", source)

    def test_livekit_client_filters_events_to_current_session(self) -> None:
        source = (APP_ROOT / "LiveKitRecitationClient.swift").read_text(encoding="utf-8")

        self.assertIn("activeSessionId = token.sessionId", source)
        self.assertIn("guard event.sessionId == activeSessionId else { return }", source)
        self.assertIn("activeSessionId = nil", source)

    def test_voice_activity_detector_is_guarded_until_fluidaudio_is_linked(self) -> None:
        source = (APP_ROOT / "VoiceActivityDetector.swift").read_text(encoding="utf-8")

        self.assertIn("#if canImport(FluidAudio)", source)
        self.assertIn("VadManager", source)
        self.assertIn("VadStreamState", source)
        self.assertIn("manager.makeStreamState()", source)
        self.assertIn("manager.processStreamingChunk", source)
        self.assertIn("VoiceActivityPayload", source)

    def test_voice_activity_detector_prefers_bundled_silero_coreml_model(self) -> None:
        source = (APP_ROOT / "VoiceActivityDetector.swift").read_text(encoding="utf-8")

        self.assertIn("import CoreML", source)
        self.assertIn("silero-vad-unified-256ms-v6.0.0", source)
        self.assertIn("MLModel(contentsOf: modelURL, configuration: configuration)", source)
        self.assertIn("VadManager(config: .default, vadModel: vadModel)", source)
        self.assertIn("try await VadManager()", source)

    def test_silero_vad_coreml_bundle_is_packaged_with_ios_app(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")
        model_path = MODEL_ROOT / SILERO_VAD_MODEL

        self.assertTrue(model_path.is_dir())
        self.assertTrue((model_path / "coremldata.bin").is_file())
        self.assertTrue((model_path / "model.mil").is_file())
        self.assertTrue((model_path / "weights" / "weight.bin").is_file())
        self.assertIn(SILERO_VAD_MODEL, project)
        self.assertIn("silero-vad-unified-256ms-v6.0.0.mlmodelc in Resources", project)

    def test_voice_activity_detector_resets_stream_state_on_stop(self) -> None:
        source = (APP_ROOT / "VoiceActivityDetector.swift").read_text(encoding="utf-8")
        view_model = (APP_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertIn("func reset() async", source)
        self.assertIn("voiceActivityDetector.reset()", view_model)

    def test_livekit_path_uses_app_microphone_streamer_and_vad_before_transport(self) -> None:
        view_model = (APP_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertIn("try await audioStreamer.start", view_model)
        self.assertIn("publishLiveKitAudioChunk", view_model)
        self.assertIn("voiceActivityDetector.process", view_model)
        self.assertIn("liveKitClient.publishAudio", view_model)

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
        self.assertIn("@executable_path/Frameworks", project)
        self.assertIn("@loader_path/Frameworks", project)

    def test_app_has_livekit_autostart_launch_argument_for_simulator_smoke(self) -> None:
        app = (APP_ROOT / "TarteelPrototypeApp.swift").read_text(encoding="utf-8")
        content_view = (APP_ROOT / "ContentView.swift").read_text(encoding="utf-8")

        self.assertIn("--tarteel-autostart-livekit", app)
        self.assertIn("selectBackendPreset(.liveKitLocal)", app)
        self.assertIn("shouldAutostartLiveKit", content_view)
        self.assertIn("viewModel.toggleRecording()", content_view)


if __name__ == "__main__":
    unittest.main()
