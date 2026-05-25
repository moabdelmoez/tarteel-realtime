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
        source = (APP_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertIn("@Published private(set) var recitationMode", source)
        self.assertIn("@Published var selectedSurahID", source)
        self.assertIn("func selectRecitationMode", source)
        self.assertIn("private var recitationScopeSelection", source)
        self.assertIn("recitationScope: recitationScopeSelection", source)

    def test_content_view_keeps_recitation_controls_on_home_screen(self) -> None:
        source = (APP_ROOT / "ContentView.swift").read_text(encoding="utf-8")

        self.assertIn("Picker(\"Recitation\"", source)
        self.assertIn("selectRecitationMode", source)
        self.assertIn("Text(\"Auto\").tag(RecitationMode.autoDetect)", source)
        self.assertIn("Text(\"Surah\").tag(RecitationMode.selectedSurah)", source)
        self.assertIn("Picker(\"Surah\"", source)
        self.assertIn("ForEach(SurahCatalog.all)", source)
        self.assertIn(".pickerStyle(.menu)", source)
        self.assertIn("Image(systemName: \"gearshape.fill\")", source)
        self.assertIn("SettingsSheet(", source)


if __name__ == "__main__":
    unittest.main()
