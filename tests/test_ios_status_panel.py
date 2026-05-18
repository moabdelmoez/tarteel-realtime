from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
CONTENT_VIEW_PATH = (
    REPO_ROOT
    / "ios"
    / "TarteelPrototype"
    / "TarteelPrototype"
    / "App"
    / "ContentView.swift"
)
VIEW_MODEL_PATH = (
    REPO_ROOT
    / "ios"
    / "TarteelPrototype"
    / "TarteelPrototype"
    / "App"
    / "RecitationViewModel.swift"
)


class IOSStatusPanelSourceTests(unittest.TestCase):
    def test_status_panel_shows_real_asr_success_signals(self) -> None:
        source = CONTENT_VIEW_PATH.read_text(encoding="utf-8")

        self.assertIn("DebugStatusPanel", source)
        self.assertIn('"Connection"', source)
        self.assertIn('"Last event"', source)
        self.assertIn('"Ayah"', source)
        self.assertIn('"Ayah text"', source)
        self.assertNotIn('title: "Transcript"', source)
        self.assertIn("debugLastEventText", source)
        self.assertIn("debugAyahText", source)
        self.assertIn("debugAyahBodyText", source)

    def test_view_model_does_not_republish_identical_realtime_state(self) -> None:
        source = VIEW_MODEL_PATH.read_text(encoding="utf-8")

        self.assertIn("let nextState = currentState.applying(event)", source)
        self.assertIn("if nextState != currentState", source)


if __name__ == "__main__":
    unittest.main()
