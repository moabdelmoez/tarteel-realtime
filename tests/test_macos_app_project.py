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
    def _object_block(self, project: str, object_id: str, comment: str | None = None) -> str:
        comment_pattern = rf" /\* {re.escape(comment)} \*/" if comment else r"(?: /\* .*? \*/)?"
        match = re.search(
            rf"\n\t\t{re.escape(object_id)}{comment_pattern} = \{{(?P<body>.*?)\n\t\t\}};",
            project,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match, f"Missing object block {object_id} {comment or ''}")
        return match.group("body")

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

    def _target_build_configuration_bodies(self, project: str, target_name: str) -> list[str]:
        target_body = self._target_block(project, target_name)
        config_list_match = re.search(
            r"buildConfigurationList = ([A-Fa-f0-9]+) /\* Build configuration list for PBXNativeTarget",
            target_body,
        )
        self.assertIsNotNone(config_list_match, f"Missing build configuration list for {target_name}")
        config_list_body = self._object_block(project, config_list_match.group(1))
        config_ids = re.findall(r"([A-Fa-f0-9]+) /\* (?:Debug|Release) \*/", config_list_body)
        self.assertGreaterEqual(len(config_ids), 2, f"Expected Debug and Release configs for {target_name}")
        return [self._object_block(project, config_id) for config_id in config_ids]

    def _target_source_paths(self, project: str, target_name: str) -> set[str]:
        sources_body = self._target_phase_body(project, target_name, "Sources")
        build_file_ids = re.findall(r"([A-Fa-f0-9]+) /\* .*? in Sources \*/", sources_body)
        paths: set[str] = set()
        for build_file_id in build_file_ids:
            build_file_body = self._object_block(project, build_file_id)
            file_ref_match = re.search(r"fileRef = ([A-Fa-f0-9]+) /\* .*? \*/;", build_file_body)
            self.assertIsNotNone(file_ref_match, f"Missing fileRef for source build file {build_file_id}")
            file_ref_body = self._object_block(project, file_ref_match.group(1))
            path_match = re.search(r"path = ([^;]+);", file_ref_body)
            self.assertIsNotNone(path_match, f"Missing path for source fileRef {file_ref_match.group(1)}")
            paths.add(path_match.group(1).strip('"'))
        return paths

    def test_project_declares_native_macos_target(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")
        mac_target = self._target_block(project, "TarteelPrototypeMac")

        self.assertIn("productName = TarteelPrototypeMac;", mac_target)
        self.assertIn('productType = "com.apple.product-type.application";', mac_target)
        for config_body in self._target_build_configuration_bodies(project, "TarteelPrototypeMac"):
            self.assertIn("SDKROOT = macosx;", config_body)
            self.assertIn("MACOSX_DEPLOYMENT_TARGET = 14.0;", config_body)
            self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = dev.mostafa.TarteelPrototypeMac;", config_body)
            self.assertIn('SUPPORTED_PLATFORMS = "macosx";', config_body)

    def test_project_includes_shared_core_files_in_both_app_targets(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")
        iphone_paths = self._target_source_paths(project, "TarteelPrototype")
        mac_paths = self._target_source_paths(project, "TarteelPrototypeMac")

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
            expected_path = f"../TarteelClientCore/Sources/TarteelClientCore/{filename}"
            self.assertIn(expected_path, iphone_paths)
            self.assertIn(expected_path, mac_paths)

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
        self.assertIn('CommandMenu("Recitation")', app_source)
        self.assertIn("MacSettingsView", settings_source)
        self.assertIn("EventHistoryPanel", content_source)
        self.assertIn("SettingsLink", content_source)
        self.assertIn("AVCaptureDevice.requestAccess", audio_source)
        self.assertIn("AVAudioEngine", audio_source)
        self.assertNotIn("AVAudioSession", audio_source)

    def test_macos_ui_uses_native_visual_system_and_toolbar_actions(self) -> None:
        content_source = (MAC_APP_SOURCE_ROOT / "MacContentView.swift").read_text(encoding="utf-8")
        app_source = (MAC_APP_SOURCE_ROOT / "TarteelPrototypeMacApp.swift").read_text(encoding="utf-8")

        self.assertNotIn(".background(Color.white)", content_source)
        self.assertIn("Color(nsColor: .windowBackgroundColor)", content_source)
        self.assertIn(".background(.regularMaterial)", content_source)
        self.assertIn("ToolbarItemGroup", content_source)
        self.assertIn("Label(viewModel.recordingActionTitle", content_source)
        self.assertIn(".help(viewModel.recordingActionHelp)", content_source)
        self.assertIn(".windowToolbarStyle(.unifiedCompact)", app_source)
        self.assertIn('CommandMenu("Recitation")', app_source)
        self.assertIn(".keyboardShortcut(\"f\", modifiers: [.command])", app_source)

    def test_macos_ui_exposes_search_drag_drop_onboarding_and_transitions(self) -> None:
        content_source = (MAC_APP_SOURCE_ROOT / "MacContentView.swift").read_text(encoding="utf-8")

        self.assertIn("@FocusState", content_source)
        self.assertIn(".searchable(text:", content_source)
        self.assertIn("filteredSurahs", content_source)
        self.assertIn(".onDrop(of:", content_source)
        self.assertIn("UTType.url.identifier", content_source)
        self.assertIn("UTType.plainText.identifier", content_source)
        self.assertIn(".draggable(viewModel.shareableSessionSummary)", content_source)
        self.assertIn("NativeOnboardingSheet", content_source)
        self.assertIn("focusMacSurahSearch", content_source)
        self.assertIn(".onReceive(NotificationCenter.default.publisher", content_source)
        self.assertIn(".transition(.opacity.combined", content_source)
        self.assertIn(".animation(.snappy", content_source)

    def test_macos_settings_show_validation_and_disabled_state_feedback(self) -> None:
        settings_source = (MAC_APP_SOURCE_ROOT / "MacSettingsView.swift").read_text(encoding="utf-8")

        self.assertIn("backendURLValidationMessage", settings_source)
        self.assertIn("Label(message", settings_source)
        self.assertIn("exclamationmark.triangle", settings_source)
        self.assertIn("Settings controls are locked while recording", settings_source)
        self.assertIn(".help(", settings_source)


if __name__ == "__main__":
    unittest.main()
