from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "App"
CORE_ROOT = REPO_ROOT / "ios" / "TarteelClientCore" / "Sources" / "TarteelClientCore"


class IOSWebSocketClientSourceTests(unittest.TestCase):
    def test_websocket_client_waits_until_socket_is_open_before_streaming(self) -> None:
        source = (CORE_ROOT / "BackendWebSocketClient.swift").read_text(encoding="utf-8")

        self.assertIn("try await waitUntilConnected(task)", source)
        self.assertIn("task.sendPing", source)
        self.assertLess(
            source.index("try await waitUntilConnected(task)"),
            source.index("receiveTask = Task"),
        )

    def test_websocket_client_can_attach_runpod_bearer_token(self) -> None:
        source = (CORE_ROOT / "BackendWebSocketClient.swift").read_text(encoding="utf-8")

        self.assertIn("authorizationToken: String?", source)
        self.assertIn("URLRequest(url: url)", source)
        self.assertIn("Bearer \\(authorizationToken)", source)
        self.assertIn('forHTTPHeaderField: "Authorization"', source)
        self.assertIn("URLSession.shared.webSocketTask(with: request)", source)

    def test_view_model_keeps_runpod_key_local_and_passes_it_to_socket_client(self) -> None:
        source = (CORE_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertFalse((APP_ROOT / "RecitationViewModel.swift").exists())
        self.assertIn("@Published public var runPodAPIKeyText", source)
        self.assertIn("private var runPodAuthorizationToken", source)
        self.assertIn("authorizationToken: runPodAuthorizationToken", source)

    def test_content_view_exposes_prototype_only_runpod_key_field_in_settings(self) -> None:
        source = (APP_ROOT / "ContentView.swift").read_text(encoding="utf-8")

        self.assertIn("private struct SettingsSheet", source)
        self.assertIn('SecureField("RunPod API key"', source)
        self.assertIn("prototype-only direct RunPod", source)

    def test_view_model_maps_simulator_socket_errors_to_actionable_guidance(self) -> None:
        source = (CORE_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertIn("errorMessage(for: error, backendPreset: backendPreset)", source)
        self.assertIn("Start the local Simulator backend", source)
        self.assertIn("Socket is not connected", source)

    def test_view_model_uses_websocket_transport_for_all_presets(self) -> None:
        source = (CORE_ROOT / "RecitationViewModel.swift").read_text(encoding="utf-8")

        self.assertIn("try await socketClient.connect", source)
        self.assertIn("await self?.sendAudioChunk", source)


if __name__ == "__main__":
    unittest.main()
