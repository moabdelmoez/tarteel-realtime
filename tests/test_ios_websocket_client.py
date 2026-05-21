from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "App"


class IOSWebSocketClientSourceTests(unittest.TestCase):
    def test_websocket_client_waits_until_socket_is_open_before_streaming(self) -> None:
        source = (APP_ROOT / "BackendWebSocketClient.swift").read_text(encoding="utf-8")

        self.assertIn("try await waitUntilConnected(task)", source)
        self.assertIn("task.sendPing", source)
        self.assertLess(
            source.index("try await waitUntilConnected(task)"),
            source.index("receiveTask = Task"),
        )

    def test_view_model_maps_simulator_socket_errors_to_actionable_guidance(self) -> None:
        source = (APP_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertIn("errorMessage(for: error, backendPreset: backendPreset)", source)
        self.assertIn("Start the local Simulator backend", source)
        self.assertIn("Socket is not connected", source)


if __name__ == "__main__":
    unittest.main()
