from pathlib import Path
import plistlib
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype.xcodeproj" / "project.pbxproj"
MAC_APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototypeMac"
MAC_APP_SOURCE_ROOT = MAC_APP_ROOT / "App"
MAC_PLIST_PATH = MAC_APP_ROOT / "Info.plist"
MODEL_NAME = "silero-vad-unified-256ms-v6.0.0.mlmodelc"


class MacOSAppProjectTests(unittest.TestCase):
    def _target_block(self, project: str, target_name: str) -> str:
        match = re.search(
            rf"\n\t\t[A-Fa-f0-9]+ /\* {re.escape(target_name)} \*/ = \{{(?P<body>\n\t\t\tisa = PBXNativeTarget;.*?)\n\t\t\}};",
            project,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match, f"Missing PBXNativeTarget block for {target_name}")
        return match.group("body")

    def _target_phase_body(self, project: str, target_name: str, phase_name: str) -> str:
        target_body = self._target_block(project, target_name)
        phase_id_match = re.search(
            rf"([A-Fa-f0-9]+) /\* {re.escape(phase_name)} \*/",
            target_body,
        )
        self.assertIsNotNone(phase_id_match, f"Missing {phase_name} phase for {target_name}")
        phase_id = phase_id_match.group(1)
        phase_match = re.search(
            rf"\n\t\t{re.escape(phase_id)} /\* {re.escape(phase_name)} \*/ = \{{(?P<body>.*?)\n\t\t\}};",
            project,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(phase_match, f"Missing {phase_name} phase body for {target_name}")
        return phase_match.group("body")

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
        iphone_sources = self._target_phase_body(project, "TarteelPrototype", "Sources")
        mac_sources = self._target_phase_body(project, "TarteelPrototypeMac", "Sources")

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
            self.assertIn(filename, iphone_sources)
            self.assertIn(filename, mac_sources)

    def test_project_includes_vad_model_resource_for_iphone_and_macos(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")
        iphone_resources = self._target_phase_body(project, "TarteelPrototype", "Resources")
        mac_resources = self._target_phase_body(project, "TarteelPrototypeMac", "Resources")

        self.assertIn(MODEL_NAME, iphone_resources)
        self.assertIn(MODEL_NAME, mac_resources)

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
        self.assertNotIn("UIApplicationSupportsIndirectInputEvents", plist)
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
