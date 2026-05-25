from pathlib import Path
import plistlib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype.xcodeproj" / "project.pbxproj"
MAC_APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototypeMac"
MAC_APP_SOURCE_ROOT = MAC_APP_ROOT / "App"
MAC_PLIST_PATH = MAC_APP_ROOT / "Info.plist"
MODEL_NAME = "silero-vad-unified-256ms-v6.0.0.mlmodelc"


class MacOSAppProjectTests(unittest.TestCase):
    def test_project_declares_native_macos_target(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")

        self.assertIn("TarteelPrototypeMac", project)
        self.assertIn("TarteelPrototypeMac.app", project)
        self.assertIn("SDKROOT = macosx;", project)
        self.assertIn("MACOSX_DEPLOYMENT_TARGET = 14.0;", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = dev.mostafa.TarteelPrototypeMac;", project)
        self.assertIn('SUPPORTED_PLATFORMS = "macosx";', project)
        self.assertIn('productType = "com.apple.product-type.application";', project)

    def test_project_includes_shared_core_files_in_both_app_targets(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")

        for filename in [
            "AudioChunkPayload.swift",
            "BackendEndpointPreset.swift",
            "BackendWebSocketClient.swift",
            "RecitationClientProtocols.swift",
            "RecitationEvent.swift",
            "RecitationMode.swift",
            "RecitationPreferencesStore.swift",
            "RecitationScopeSelection.swift",
            "RecitationSessionState.swift",
            "RecitationViewModel.swift",
            "SurahCatalog.swift",
            "VoiceActivityPayload.swift",
        ]:
            self.assertIn(filename, project)

    def test_project_includes_vad_model_resource_for_iphone_and_macos(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")

        self.assertGreaterEqual(project.count(f"{MODEL_NAME} in Resources"), 2)
        self.assertIn(MODEL_NAME, project)

    def test_macos_info_plist_is_not_ios_plist(self) -> None:
        with MAC_PLIST_PATH.open("rb") as file:
            plist = plistlib.load(file)

        self.assertEqual(
            plist["NSMicrophoneUsageDescription"],
            "Microphone access streams recitation audio to your selected development backend.",
        )
        self.assertIn("NSAppTransportSecurity", plist)
        self.assertNotIn("LSRequiresIPhoneOS", plist)
        self.assertNotIn("UIApplicationSceneManifest", plist)
        self.assertNotIn("UILaunchScreen", plist)

    def test_macos_sources_define_desktop_app_surface(self) -> None:
        app_source = (MAC_APP_SOURCE_ROOT / "TarteelPrototypeMacApp.swift").read_text(encoding="utf-8")
        content_source = (MAC_APP_SOURCE_ROOT / "MacContentView.swift").read_text(encoding="utf-8")
        settings_source = (MAC_APP_SOURCE_ROOT / "MacSettingsView.swift").read_text(encoding="utf-8")
        audio_source = (MAC_APP_SOURCE_ROOT / "MacMicrophoneAudioStreamer.swift").read_text(encoding="utf-8")

        self.assertIn("@main", app_source)
        self.assertIn("Settings", app_source)
        self.assertIn("MacContentView", app_source)
        self.assertIn("CommandGroup", app_source)
        self.assertIn("MacSettingsView", settings_source)
        self.assertIn("EventHistoryPanel", content_source)
        self.assertIn("SettingsLink", content_source)
        self.assertIn("AVCaptureDevice.requestAccess", audio_source)
        self.assertIn("AVAudioEngine", audio_source)
        self.assertNotIn("AVAudioSession", audio_source)


if __name__ == "__main__":
    unittest.main()
