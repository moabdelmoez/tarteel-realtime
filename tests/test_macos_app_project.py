import json
from pathlib import Path
import plistlib
import re
import unittest
import xml.etree.ElementTree as ET


REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype.xcodeproj" / "project.pbxproj"
MAC_APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototypeMac"
MAC_APP_SOURCE_ROOT = MAC_APP_ROOT / "App"
MAC_PLIST_PATH = MAC_APP_ROOT / "Info.plist"
MODEL_NAME = "silero-vad-unified-256ms-v6.0.0.mlmodelc"
QURAN_LOGO_NAME = "quran_logo.png"
ASSETS_CATALOG_NAME = "Assets.xcassets"
APP_ICON_NAME = "AppIcon"
COREML_CLIENT_NAME = "CoreMLFastConformerClient.swift"
COREML_SCORING_NAME = "CoreMLFastConformerFixtureScoring.swift"
LOCAL_AUDIO_REPLAY_NAME = "LocalAudioReplayStreamer.swift"
COREML_REPLAY_SCHEME_NAME = "TarteelPrototypeCoreMLReplay"
FASTCONFORMER_STREAMING_MODEL_NAME = "fastconformer-quran-streaming.mlpackage"
FASTCONFORMER_PRONUNCIATION_HEAD_NAME = "pronunciation-head.mlpackage"
FASTCONFORMER_TOKENIZER_NAME = "tokenizer.model"
FASTCONFORMER_TOKENS_NAME = "tokens.txt"
TANZIL_RESOURCE_NAME = "quran-simple-clean.txt"
TANZIL_COPY_SCRIPT = "copy-local-tanzil-resource.sh"
LOCAL_AUDIO_COPY_SCRIPT = "copy-local-audio-fixtures.sh"
COREML_REPLAY_SCHEME_PATH = (
    REPO_ROOT
    / "ios"
    / "TarteelPrototype"
    / "TarteelPrototype.xcodeproj"
    / "xcshareddata"
    / "xcschemes"
    / f"{COREML_REPLAY_SCHEME_NAME}.xcscheme"
)


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
            COREML_CLIENT_NAME,
            COREML_SCORING_NAME,
            LOCAL_AUDIO_REPLAY_NAME,
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

        self.assertIn("App/KeychainBackendBearerTokenStore.swift", mac_paths)
        self.assertNotIn("App/KeychainBackendBearerTokenStore.swift", iphone_paths)

    def test_project_includes_resources_for_iphone_and_macos(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")
        iphone_resources = self._target_phase_body(project, "TarteelPrototype", "Resources")
        mac_resources = self._target_phase_body(project, "TarteelPrototypeMac", "Resources")

        self.assertIn(MODEL_NAME, iphone_resources)
        self.assertIn(MODEL_NAME, mac_resources)
        self.assertIn(FASTCONFORMER_STREAMING_MODEL_NAME, iphone_resources)
        self.assertIn(FASTCONFORMER_STREAMING_MODEL_NAME, mac_resources)
        self.assertIn(FASTCONFORMER_PRONUNCIATION_HEAD_NAME, iphone_resources)
        self.assertIn(FASTCONFORMER_PRONUNCIATION_HEAD_NAME, mac_resources)
        self.assertIn(FASTCONFORMER_TOKENIZER_NAME, iphone_resources)
        self.assertIn(FASTCONFORMER_TOKENIZER_NAME, mac_resources)
        self.assertIn(FASTCONFORMER_TOKENS_NAME, iphone_resources)
        self.assertIn(FASTCONFORMER_TOKENS_NAME, mac_resources)
        self.assertIn(QURAN_LOGO_NAME, iphone_resources)
        self.assertIn(QURAN_LOGO_NAME, mac_resources)
        self.assertIn(ASSETS_CATALOG_NAME, iphone_resources)
        self.assertIn(ASSETS_CATALOG_NAME, mac_resources)

        for target_name in ["TarteelPrototype", "TarteelPrototypeMac"]:
            for config_body in self._target_build_configuration_bodies(project, target_name):
                self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", config_body)

        app_icon_path = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / ASSETS_CATALOG_NAME / f"{APP_ICON_NAME}.appiconset" / "Contents.json"
        with app_icon_path.open(encoding="utf-8") as file:
            contents = json.load(file)

        filenames = {image.get("filename") for image in contents["images"]}
        self.assertIn("app-icon-60@3x.png", filenames)
        self.assertIn("app-icon-1024.png", filenames)

    def test_coreml_client_emits_asr_diagnostics(self) -> None:
        source = (
            REPO_ROOT
            / "ios"
            / "TarteelClientCore"
            / "Sources"
            / "TarteelClientCore"
            / COREML_CLIENT_NAME
        ).read_text(encoding="utf-8")

        self.assertIn("import OSLog", source)
        self.assertIn("CoreMLFastConformerDiagnostics", source)
        self.assertIn("coreml_asr_connect", source)
        self.assertIn("coreml_asr_model_loaded", source)
        self.assertIn("coreml_asr_buffering", source)
        self.assertIn("coreml_asr_blank", source)
        self.assertIn("coreml_asr_transcript", source)
        self.assertIn("inference_ms", source)
        self.assertIn("confidence", source)
        self.assertIn("emitted_tokens", source)
        self.assertIn("cumulative_transcript", source)

    def test_coreml_client_reports_nonfinite_model_output(self) -> None:
        source = (
            REPO_ROOT
            / "ios"
            / "TarteelClientCore"
            / "Sources"
            / "TarteelClientCore"
            / COREML_CLIENT_NAME
        ).read_text(encoding="utf-8")

        self.assertIn("coreml_asr_invalid_output", source)
        self.assertIn("nonfinite_logprobs", source)
        self.assertIn("isFinite", source)
        self.assertIn("throw CoreMLFastConformerError.invalidModelOutput", source)

    def test_project_conditionally_bundles_local_tanzil_quran_text(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")
        script_path = REPO_ROOT / "ios" / "TarteelPrototype" / "Scripts" / TANZIL_COPY_SCRIPT
        self.assertTrue(script_path.exists(), f"Missing {script_path}")
        script = script_path.read_text(encoding="utf-8")

        self.assertIn("data/tanzil", script)
        self.assertIn("TARGET_BUILD_DIR", script)
        self.assertIn("UNLOCALIZED_RESOURCES_FOLDER_PATH", script)
        self.assertIn(TANZIL_RESOURCE_NAME, script)
        self.assertIn("[ -f", script)

        for target_name in ["TarteelPrototype", "TarteelPrototypeMac"]:
            phase = self._target_phase_body(project, target_name, "Copy Local Tanzil Quran")
            self.assertIn("PBXShellScriptBuildPhase", phase)
            self.assertIn(TANZIL_COPY_SCRIPT, phase)

    def test_project_conditionally_bundles_local_audio_replay_fixtures(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")
        script_path = REPO_ROOT / "ios" / "TarteelPrototype" / "Scripts" / LOCAL_AUDIO_COPY_SCRIPT
        self.assertTrue(script_path.exists(), f"Missing {script_path}")
        script = script_path.read_text(encoding="utf-8")

        self.assertIn("fixtures/local_audio", script)
        self.assertIn("TARGET_BUILD_DIR", script)
        self.assertIn("UNLOCALIZED_RESOURCES_FOLDER_PATH", script)
        self.assertIn("local_audio", script)
        self.assertIn("*.wav", script)
        self.assertIn("[ -d", script)

        for target_name in ["TarteelPrototype", "TarteelPrototypeMac"]:
            phase = self._target_phase_body(project, target_name, "Copy Local Audio Fixtures")
            self.assertIn("PBXShellScriptBuildPhase", phase)
            self.assertIn(LOCAL_AUDIO_COPY_SCRIPT, phase)

    def test_apps_support_developer_coreml_audio_replay_launch_argument(self) -> None:
        iphone_source = (APP_ROOT := REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "App" / "TarteelPrototypeApp.swift").read_text(encoding="utf-8")
        mac_source = (MAC_APP_SOURCE_ROOT / "TarteelPrototypeMacApp.swift").read_text(encoding="utf-8")
        replay_path = (
            REPO_ROOT
            / "ios"
            / "TarteelClientCore"
            / "Sources"
            / "TarteelClientCore"
            / LOCAL_AUDIO_REPLAY_NAME
        )
        self.assertTrue(replay_path.exists(), f"Missing {replay_path}")
        replay_source = replay_path.read_text(encoding="utf-8")

        for source in [iphone_source, mac_source]:
            self.assertIn("LocalAudioReplayConfiguration", source)
            self.assertIn("LocalAudioReplayStreamer", source)
            self.assertIn("startReplayIfNeeded", source)
            self.assertIn("replayConfiguration", source)
            self.assertIn(".coreML", source)
            self.assertIn(".selectedSurah", source)

        self.assertIn("--tarteel-replay-audio", replay_source)
        self.assertIn("--tarteel-replay-surah", replay_source)
        self.assertIn("local_audio", replay_source)
        self.assertIn("func replay()", replay_source)

    def test_apple_apps_default_to_coreml_selected_surah_for_local_testing(self) -> None:
        iphone_source = (
            REPO_ROOT
            / "ios"
            / "TarteelPrototype"
            / "TarteelPrototype"
            / "App"
            / "TarteelPrototypeApp.swift"
        ).read_text(encoding="utf-8")
        mac_source = (MAC_APP_SOURCE_ROOT / "TarteelPrototypeMacApp.swift").read_text(encoding="utf-8")

        for source in [iphone_source, mac_source]:
            self.assertIn(
                "UserDefaultsRecitationPreferencesStore(fallbackValues: .coreMLSelectedSurah108)",
                source,
            )

    def test_project_has_shared_coreml_replay_scheme_for_physical_device_testing(self) -> None:
        self.assertTrue(COREML_REPLAY_SCHEME_PATH.exists(), f"Missing {COREML_REPLAY_SCHEME_PATH}")
        scheme = ET.parse(COREML_REPLAY_SCHEME_PATH).getroot()
        self.assertEqual(scheme.tag, "Scheme")

        buildable_refs = scheme.findall(".//BuildableReference")
        iphone_refs = [
            ref for ref in buildable_refs
            if ref.get("BlueprintName") == "TarteelPrototype"
        ]
        self.assertGreaterEqual(len(iphone_refs), 2)
        for ref in iphone_refs:
            self.assertEqual(ref.get("BuildableName"), "TarteelPrototype.app")
            self.assertEqual(ref.get("BlueprintIdentifier"), "100000000000000000000050")
            self.assertEqual(ref.get("ReferencedContainer"), "container:TarteelPrototype.xcodeproj")

        enabled_arguments = [
            argument.get("argument")
            for argument in scheme.findall(".//LaunchAction/CommandLineArguments/CommandLineArgument")
            if argument.get("isEnabled") == "YES"
        ]
        self.assertEqual(
            enabled_arguments,
            ["--tarteel-replay-audio", "108001.wav", "--tarteel-replay-surah", "108"],
        )

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
        keychain_source = (MAC_APP_SOURCE_ROOT / "KeychainBackendBearerTokenStore.swift").read_text(encoding="utf-8")

        self.assertIn("@main", app_source)
        self.assertIn("Settings", app_source)
        self.assertIn("MacContentView", app_source)
        self.assertIn("RoutingBackendSocketClient", app_source)
        self.assertIn("CoreMLFastConformerSocketClient", app_source)
        self.assertIn('CommandMenu("Recitation")', app_source)
        self.assertIn("UserDefaultsRecitationPreferencesStore(fallbackValues: .coreMLSelectedSurah108)", app_source)
        self.assertIn("KeychainBackendBearerTokenStore()", app_source)
        self.assertIn('Image("quran_logo")', content_source)
        self.assertIn("QuranLogoMark", content_source)
        self.assertIn("MacSettingsView", settings_source)
        self.assertIn("EventHistoryPanel", content_source)
        self.assertIn("SettingsLink", content_source)
        self.assertIn("AVCaptureDevice.requestAccess", audio_source)
        self.assertIn("AVAudioEngine", audio_source)
        self.assertNotIn("AVAudioSession", audio_source)
        self.assertIn("import Security", keychain_source)
        self.assertIn("SecItemCopyMatching", keychain_source)
        self.assertIn("SecItemAdd", keychain_source)
        self.assertIn("SecItemUpdate", keychain_source)
        self.assertIn("SecItemDelete", keychain_source)
        self.assertIn("dev.mostafa.TarteelPrototypeMac.backend-token", keychain_source)

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
        surah_catalog_source = (
            REPO_ROOT
            / "ios"
            / "TarteelClientCore"
            / "Sources"
            / "TarteelClientCore"
            / "SurahCatalog.swift"
        ).read_text(encoding="utf-8")
        view_model_source = (
            REPO_ROOT
            / "ios"
            / "TarteelClientCore"
            / "Sources"
            / "TarteelClientCore"
            / "RecitationViewModel.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("@FocusState", content_source)
        self.assertNotIn(".searchable(text:", content_source)
        self.assertNotIn(".searchFocused($isSearchFocused)", content_source)
        self.assertIn('TextField("Search surahs"', content_source)
        self.assertIn(".focused($isSearchFocused)", content_source)
        self.assertIn("SurahCatalog.matchingSurahs(for: searchText)", content_source)
        self.assertIn(".onChange(of: searchText)", content_source)
        self.assertIn("SurahCatalog.selectionID(for: query)", content_source)
        self.assertIn("selectSurah", content_source)
        self.assertIn("viewModel.selectRecitationMode(.selectedSurah)", content_source)
        search_selection_match = re.search(
            r"private func applySearchSelection\(_ query: String\) \{(?P<body>.*?)\n    \}",
            content_source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(search_selection_match)
        search_selection_body = search_selection_match.group("body")
        self.assertIsNotNone(re.search(
            r"guard let selectionID = SurahCatalog\.selectionID\(for: query\) else \{ return \}"
            r".*viewModel\.selectedSurahID = selectionID"
            r".*viewModel\.selectRecitationMode\(\.selectedSurah\)",
            search_selection_body,
            flags=re.DOTALL,
        ))
        self.assertIsNone(re.search(
            r"viewModel\.selectRecitationMode\(\.selectedSurah\).*"
            r"guard let selectionID = SurahCatalog\.selectionID\(for: query\)",
            search_selection_body,
            flags=re.DOTALL,
        ))
        self.assertIn("if isShowingSearchResults && !filteredSurahs.isEmpty", content_source)
        self.assertIn("filteredSurahs", content_source)
        self.assertIn("ForEach(filteredSurahs)", content_source)
        self.assertNotIn("ForEach(SurahCatalog.all)", content_source)
        self.assertIn("No matching surah", content_source)
        self.assertIn("matchingSurahs(for query: String)", surah_catalog_source)
        self.assertIn("selectionID(for query: String)", surah_catalog_source)
        self.assertIn(".onDrop(of:", content_source)
        self.assertIn("UTType.url.identifier", content_source)
        self.assertIn("UTType.plainText.identifier", content_source)
        self.assertIn("DropFeedbackBanner", content_source)
        self.assertIn("backendDropFeedback", content_source)
        self.assertIn("BackendDropFeedback", view_model_source)
        self.assertIn(".draggable(viewModel.shareableSessionSummary)", content_source)
        self.assertIn("NativeOnboardingSheet", content_source)
        self.assertIn("NativeOnboardingSheet(hasSeenNativeOnboarding: $hasSeenNativeOnboarding)", content_source)
        self.assertIn("@Binding var hasSeenNativeOnboarding", content_source)
        self.assertIn('Text("Timeline")', content_source)
        self.assertIn("repeatBadgeText", content_source)
        self.assertIn("recitation milestones", content_source)
        self.assertNotIn('Text("Recent Events")', content_source)
        self.assertNotIn("backend events", content_source)
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
        self.assertIn("tokenHelpText", settings_source)
        self.assertIn("Saved securely in macOS Keychain", settings_source)
        self.assertIn("backendBearerTokenPersistenceMessage", settings_source)
        self.assertNotIn("memory-only", settings_source)
        self.assertNotIn("not saved", settings_source)
        self.assertIn(".help(viewModel.backendBearerTokenPersistenceMessage ?? tokenHelpText)", settings_source)
        self.assertNotIn(".help(tokenHelpText)", settings_source)
        self.assertIn("if let tokenMessage = viewModel.backendBearerTokenPersistenceMessage", settings_source)
        self.assertIsNotNone(re.search(
            r"if let tokenMessage = viewModel\.backendBearerTokenPersistenceMessage \{"
            r".*Label\(tokenMessage, systemImage: \"key\.horizontal\"\)"
            r".*\} else \{"
            r".*Text\(tokenHelpText\)",
            settings_source,
            flags=re.DOTALL,
        ))


if __name__ == "__main__":
    unittest.main()
