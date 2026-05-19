import Foundation
import Testing
@testable import TarteelClientCore

struct BackendEndpointPresetTests {
    @Test func simulatorPresetUsesLocalhostWebSocketURL() {
        #expect(BackendEndpointPreset.simulator.defaultURLText == "ws://127.0.0.1:8000/ws/recitation")
    }

    @Test func liveKitPresetUsesLocalhostTokenURL() {
        #expect(BackendEndpointPreset.liveKitLocal.defaultURLText == "http://127.0.0.1:8000/livekit/recitation-token")
        #expect(BackendEndpointPreset.liveKitLocal.label == "LiveKit")
    }

    @Test func customPresetKeepsExistingURLText() {
        let runpodURL = "ws://203.0.113.10:8000/ws/recitation"

        #expect(BackendEndpointPreset.custom.urlText(currentCustomURLText: runpodURL) == runpodURL)
    }
}
