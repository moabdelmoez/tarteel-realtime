from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
STREAMER_PATH = (
    REPO_ROOT
    / "ios"
    / "TarteelPrototype"
    / "TarteelPrototype"
    / "App"
    / "MicrophoneAudioStreamer.swift"
)


class IOSAudioStreamerSourceTests(unittest.TestCase):
    def test_input_tap_uses_engine_selected_format(self) -> None:
        source = STREAMER_PATH.read_text(encoding="utf-8")
        tap_call = re.search(r"input\.installTap\([\s\S]*?\)\s*\{", source)

        self.assertIsNotNone(tap_call)
        self.assertIn("format: nil", tap_call.group(0))
        self.assertNotIn("format: inputFormat", tap_call.group(0))


if __name__ == "__main__":
    unittest.main()
