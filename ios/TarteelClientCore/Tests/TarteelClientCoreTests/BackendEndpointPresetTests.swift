import Foundation
import Testing
@testable import TarteelClientCore

struct BackendEndpointPresetTests {
    @Test func simulatorPresetUsesLocalhostWebSocketURL() {
        #expect(BackendEndpointPreset.simulator.defaultURLText == "ws://127.0.0.1:8000/ws/recitation")
    }

    @Test func customPresetKeepsRunPodWebSocketURL() {
        let runpodWebSocketURL = "wss://0qudx1ctbmw1xc-8000.proxy.runpod.net/ws/recitation"

        #expect(
            BackendEndpointPreset.custom.recordingURLText(currentURLText: runpodWebSocketURL)
                == runpodWebSocketURL
        )
    }

    @Test func selectedSurahScopeIsAppendedToSimulatorRecordingURL() {
        #expect(
            BackendEndpointPreset.simulator.recordingURLText(
                currentURLText: BackendEndpointPreset.simulator.defaultURLText,
                recitationScope: .selectedSurah(id: 108)
            )
                == "ws://127.0.0.1:8000/ws/recitation?scope=108"
        )
    }

    @Test func selectedSurahScopeReplacesExistingScopeAndPreservesOtherQueryItems() {
        let runpodWebSocketURL = "wss://0qudx1ctbmw1xc-8000.proxy.runpod.net/ws/recitation?scope=4&debug=1"

        #expect(
            BackendEndpointPreset.custom.recordingURLText(
                currentURLText: runpodWebSocketURL,
                recitationScope: .selectedSurah(id: 108)
            )
                == "wss://0qudx1ctbmw1xc-8000.proxy.runpod.net/ws/recitation?debug=1&scope=108"
        )
    }

    @Test func autoDetectionRemovesExistingScopeAndPreservesOtherQueryItems() {
        let runpodWebSocketURL = "wss://0qudx1ctbmw1xc-8000.proxy.runpod.net/ws/recitation?scope=108&debug=1"

        #expect(
            BackendEndpointPreset.custom.recordingURLText(
                currentURLText: runpodWebSocketURL,
                recitationScope: .autoDetect
            )
                == "wss://0qudx1ctbmw1xc-8000.proxy.runpod.net/ws/recitation?debug=1"
        )
    }

    @Test func selectedSurahScopeNormalizesBareRunPodHostBeforeAppendingScope() {
        let runpodHost = "0qudx1ctbmw1xc-8000.proxy.runpod.net"

        #expect(
            BackendEndpointPreset.custom.recordingURLText(
                currentURLText: runpodHost,
                recitationScope: .selectedSurah(id: 108)
            )
                == "wss://0qudx1ctbmw1xc-8000.proxy.runpod.net/ws/recitation?scope=108"
        )
    }

    @Test func selectedSurahScopeNormalizesBareRunPodServerlessHostBeforeAppendingScope() {
        let runpodServerlessHost = "abc123.api.runpod.ai"

        #expect(
            BackendEndpointPreset.custom.recordingURLText(
                currentURLText: runpodServerlessHost,
                recitationScope: .selectedSurah(id: 108)
            )
                == "wss://abc123.api.runpod.ai/ws/recitation?scope=108"
        )
    }

    @Test func customPresetAddsWSSSchemeAndRecitationPathToRunPodHost() {
        let runpodHost = "0qudx1ctbmw1xc-8000.proxy.runpod.net"

        #expect(
            BackendEndpointPreset.custom.recordingURLText(currentURLText: runpodHost)
                == "wss://0qudx1ctbmw1xc-8000.proxy.runpod.net/ws/recitation"
        )
    }

    @Test func onlyCustomPresetAllowsURLTextEditing() {
        #expect(!BackendEndpointPreset.simulator.allowsURLTextEditing)
        #expect(BackendEndpointPreset.custom.allowsURLTextEditing)
    }

    @Test func customPresetKeepsExistingURLText() {
        let runpodURL = "ws://203.0.113.10:8000/ws/recitation"

        #expect(BackendEndpointPreset.custom.urlText(currentCustomURLText: runpodURL) == runpodURL)
    }
}
