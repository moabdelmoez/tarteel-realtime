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
    private let liveKitClient: LiveKitRecitationClient
    private let voiceActivityDetector: VoiceActivityDetector
    private var sequenceNumber = 0
    private var customBackendURLText = ""

    init(
        socketClient: BackendWebSocketClient = BackendWebSocketClient(),
        audioStreamer: MicrophoneAudioStreamer = MicrophoneAudioStreamer(),
        liveKitClient: LiveKitRecitationClient? = nil,
        voiceActivityDetector: VoiceActivityDetector = VoiceActivityDetector()
    ) {
        self.socketClient = socketClient
        self.audioStreamer = audioStreamer
        self.liveKitClient = liveKitClient ?? LiveKitRecitationClient()
        self.voiceActivityDetector = voiceActivityDetector
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
        sequenceNumber = 0
        await voiceActivityDetector.reset()
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

            if backendPreset == .liveKitLocal {
                try await startLiveKitRecording(tokenURL: backendURL)
                return
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
            errorMessage = errorMessage(for: error, backendPreset: backendPreset)
            connectionStatus = "Error"
        }
    }

    private func sendAudioChunk(pcm: Data, sampleRate: Int) async {
        let voiceActivity = await voiceActivityDetector.process(
            pcm: pcm,
            sampleRate: sampleRate
        )
        let payload = AudioChunkPayload(
            sequenceNumber: sequenceNumber,
            pcm: pcm,
            sampleRateHz: sampleRate,
            voiceActivity: voiceActivity
        )
        sequenceNumber += 1

        do {
            try await socketClient.send(payload)
        } catch {
            stopRecording()
            errorMessage = errorMessage(for: error, backendPreset: backendPreset)
            connectionStatus = "Error"
        }
    }

    private func publishLiveKitAudioChunk(pcm: Data, sampleRate: Int) async {
        let voiceActivity = await voiceActivityDetector.process(
            pcm: pcm,
            sampleRate: sampleRate
        )
        let currentSequenceNumber = sequenceNumber
        sequenceNumber += 1

        do {
            try await liveKitClient.publishAudio(
                pcm: pcm,
                sampleRate: sampleRate,
                sequenceNumber: currentSequenceNumber,
                voiceActivity: voiceActivity
            )
        } catch {
            stopRecording()
            errorMessage = errorMessage(for: error, backendPreset: backendPreset)
            connectionStatus = "Error"
        }
    }

    private func stopRecording() {
        audioStreamer.stop()
        socketClient.disconnect()
        liveKitClient.disconnect()
        Task { await voiceActivityDetector.reset() }
        isRecording = false
        connectionStatus = "Stopped"
        state = RecitationSessionState(
            phase: .stopped,
            headline: "Stopped",
            detail: "Tap the mic to begin again"
        )
    }

    private func startLiveKitRecording(tokenURL: URL) async throws {
        connectionStatus = "Fetching LiveKit token"
        let token = try await fetchLiveKitToken(from: tokenURL)

        try await liveKitClient.connect(token: token) { [weak self] event in
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

        try await audioStreamer.start { [weak self] pcm, sampleRate in
            Task { @MainActor in
                await self?.publishLiveKitAudioChunk(pcm: pcm, sampleRate: sampleRate)
            }
        }

        isRecording = true
        connectionStatus = "LiveKit streaming"
        state = RecitationSessionState(
            phase: .listening,
            headline: "Listening",
            detail: "Start reciting"
        )
    }

    private func fetchLiveKitToken(from url: URL) async throws -> LiveKitRecitationToken {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw RecitationViewModelError.liveKitTokenRequestFailed
        }
        return try JSONDecoder().decode(LiveKitRecitationToken.self, from: data)
    }

    private func errorMessage(for error: Error, backendPreset: BackendEndpointPreset) -> String {
        let message = error.localizedDescription
        guard backendPreset == .simulator else {
            return message
        }

        if message.contains("Socket is not connected")
            || message.localizedCaseInsensitiveContains("connection refused")
            || message.localizedCaseInsensitiveContains("could not connect") {
            return "Start the local Simulator backend on 127.0.0.1:8000, then try again."
        }

        return message
    }
}

enum RecitationViewModelError: LocalizedError {
    case invalidBackendURL
    case liveKitTokenRequestFailed

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            return "Enter a valid backend URL."
        case .liveKitTokenRequestFailed:
            return "Could not fetch a LiveKit recitation token."
        }
    }
}
