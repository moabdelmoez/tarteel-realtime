import Combine
import Foundation

@MainActor
final class RecitationViewModel: ObservableObject {
    @Published private(set) var state = RecitationSessionState()
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var backendPreset = BackendEndpointPreset.simulator
    @Published private(set) var connectionStatus = "Idle"
    @Published var backendURLText = BackendEndpointPreset.simulator.defaultURLText

    private let socketClient: BackendWebSocketClient
    private let audioStreamer: MicrophoneAudioStreamer
    private var sequenceNumber = 0
    private var customBackendURLText = ""

    init(
        socketClient: BackendWebSocketClient = BackendWebSocketClient(),
        audioStreamer: MicrophoneAudioStreamer = MicrophoneAudioStreamer()
    ) {
        self.socketClient = socketClient
        self.audioStreamer = audioStreamer
    }

    func selectBackendPreset(_ preset: BackendEndpointPreset) {
        if backendPreset == .custom {
            customBackendURLText = backendURLText
        }

        backendPreset = preset
        backendURLText = preset.urlText(currentCustomURLText: customBackendURLText)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }

        Task {
            await startRecording()
        }
    }

    private func startRecording() async {
        errorMessage = nil
        connectionStatus = "Connecting"
        state = RecitationSessionState(
            phase: .connecting,
            headline: "Connecting",
            detail: "Preparing microphone"
        )

        do {
            let urlText = backendPreset.urlText(currentCustomURLText: backendURLText)
            guard let backendURL = URL(string: urlText) else {
                throw RecitationViewModelError.invalidBackendURL
            }

            try await socketClient.connect(url: backendURL) { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    let currentState = self.state
                    let nextState = currentState.applying(event)
                    if nextState != currentState {
                        self.state = nextState
                    }
                    if self.connectionStatus != "Receiving events" {
                        self.connectionStatus = "Receiving events"
                    }
                }
            }
            connectionStatus = "Connected"

            try await audioStreamer.start { [weak self] pcm, sampleRate in
                Task { @MainActor in
                    await self?.sendAudioChunk(pcm: pcm, sampleRate: sampleRate)
                }
            }

            isRecording = true
            connectionStatus = "Streaming"
            state = RecitationSessionState(
                phase: .listening,
                headline: "Listening",
                detail: "Start reciting"
            )
        } catch {
            stopRecording()
            errorMessage = error.localizedDescription
            connectionStatus = "Error"
        }
    }

    private func sendAudioChunk(pcm: Data, sampleRate: Int) async {
        let payload = AudioChunkPayload(
            sequenceNumber: sequenceNumber,
            pcm: pcm,
            sampleRateHz: sampleRate
        )
        sequenceNumber += 1

        do {
            try await socketClient.send(payload)
        } catch {
            stopRecording()
            errorMessage = error.localizedDescription
            connectionStatus = "Error"
        }
    }

    private func stopRecording() {
        audioStreamer.stop()
        socketClient.disconnect()
        isRecording = false
        connectionStatus = "Stopped"
        state = RecitationSessionState(
            phase: .stopped,
            headline: "Stopped",
            detail: "Tap the mic to begin again"
        )
    }
}

enum RecitationViewModelError: LocalizedError {
    case invalidBackendURL

    var errorDescription: String? {
        "Enter a valid WebSocket URL."
    }
}
