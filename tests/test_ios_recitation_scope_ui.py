from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "App"
CORE_ROOT = REPO_ROOT / "ios" / "TarteelClientCore" / "Sources" / "TarteelClientCore"


class IOSRecitationScopeUITests(unittest.TestCase):
    def test_client_core_has_selected_surah_scope_model(self) -> None:
        source = (CORE_ROOT / "RecitationScopeSelection.swift").read_text(encoding="utf-8")

        self.assertIn("enum RecitationScopeSelection", source)
        self.assertIn("case autoDetect", source)
        self.assertIn("case selectedSurah(id: Int)", source)
        self.assertIn("return \"\\(id)\"", source)

    def test_view_model_builds_recording_url_with_selected_recitation_scope(self) -> None:
        source = (CORE_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertFalse((APP_ROOT / "RecitationViewModel.swift").exists())
        self.assertIn("@Published public private(set) var recitationMode", source)
        self.assertIn("@Published public var selectedSurahID", source)
        self.assertIn("func selectRecitationMode", source)
        self.assertIn("supportedRecitationMode", source)
        self.assertIn("private var recitationScopeSelection", source)
        self.assertIn("return .selectedSurah(id: selectedSurahID)", source)
        self.assertIn("recitationScope: recitationScopeSelection", source)

    def test_content_view_keeps_selected_surah_controls_on_home_screen(self) -> None:
        source = (APP_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        app_source = (APP_ROOT / "TarteelPrototypeApp.swift").read_text(encoding="utf-8")

        self.assertNotIn("Picker(\"Recitation\"", source)
        self.assertNotIn("selectRecitationMode", source)
        self.assertNotIn("Text(\"Auto\").tag(RecitationMode.autoDetect)", source)
        self.assertNotIn("Text(\"Surah\").tag(RecitationMode.selectedSurah)", source)
        self.assertNotIn("if viewModel.recitationMode == .selectedSurah", source)
        self.assertIn("Picker(\"Surah\"", source)
        self.assertIn("ForEach(SurahCatalog.all)", source)
        self.assertIn(".pickerStyle(.menu)", source)
        self.assertIn("Image(systemName: \"gearshape.fill\")", source)
        self.assertIn("SettingsSheet(", source)
        self.assertIn("SettingsSheet(viewModel: viewModel)", source)
        self.assertIn("VoiceActivityIndicator(isActive: viewModel.isRecording)", source)
        self.assertIn("Image(systemName: viewModel.isRecording ? \"xmark\" : \"mic.fill\")", source)
        self.assertIn('Image("quran_logo")', source)
        self.assertIn("QuranLogoMark", source)
        self.assertIn("DebugStatusPanel(", source)
        self.assertIn("RoutingBackendSocketClient", app_source)
        self.assertIn("CoreMLFastConformerSocketClient", app_source)

    def test_content_view_allows_runtime_errors_to_wrap(self) -> None:
        source = (APP_ROOT / "ContentView.swift").read_text(encoding="utf-8")

        self.assertIn("if let errorMessage = viewModel.errorMessage", source)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", source)
        self.assertIn(".frame(maxWidth: .infinity)", source)

    def test_content_view_renders_canonical_ayah_words_as_primary_surface(self) -> None:
        source = (APP_ROOT / "ContentView.swift").read_text(encoding="utf-8")

        self.assertIn("CanonicalAyahWordsView", source)
        self.assertIn("viewModel.state.currentAyahWords", source)
        self.assertIn("viewModel.state.completedWordCount", source)
        self.assertIn("if !viewModel.state.currentAyahWords.isEmpty", source)
        self.assertNotIn("Text(viewModel.state.detail)", source)
        self.assertIn("highlightedText", source)
        self.assertIn("item.offset < completedWordCount", source)


if __name__ == "__main__":
    unittest.main()
