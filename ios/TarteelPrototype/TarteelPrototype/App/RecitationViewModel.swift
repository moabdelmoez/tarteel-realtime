import Combine
import Foundation

enum RecitationMode: String, CaseIterable, Hashable, Identifiable {
    case autoDetect
    case selectedSurah

    var id: String { rawValue }
}

@MainActor
final class RecitationViewModel: ObservableObject {
    @Published private(set) var state = RecitationSessionState()
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var backendPreset = BackendEndpointPreset.simulator
    @Published private(set) var recitationMode = RecitationMode.autoDetect
    @Published private(set) var connectionStatus = "Idle"
    @Published var backendURLText = BackendEndpointPreset.simulator.defaultURLText
    @Published var selectedSurahID = 108
    @Published var runPodAPIKeyText = ""

    private let socketClient: BackendWebSocketClient
    private let audioStreamer: MicrophoneAudioStreamer
    private let voiceActivityDetector: VoiceActivityDetector
    private var sequenceNumber = 0
    private var customBackendURLText = ""

    init(
        socketClient: BackendWebSocketClient = BackendWebSocketClient(),
        audioStreamer: MicrophoneAudioStreamer = MicrophoneAudioStreamer(),
        voiceActivityDetector: VoiceActivityDetector = VoiceActivityDetector()
    ) {
        self.socketClient = socketClient
        self.audioStreamer = audioStreamer
        self.voiceActivityDetector = voiceActivityDetector
    }

    func selectBackendPreset(_ preset: BackendEndpointPreset) {
        if backendPreset == .custom {
            customBackendURLText = backendURLText
        }

        backendPreset = preset
        switch preset {
        case .simulator:
            backendURLText = preset.defaultURLText
        case .custom:
            backendURLText = customBackendURLText
        }
    }

    func selectRecitationMode(_ mode: RecitationMode) {
        recitationMode = mode
    }

    private var recitationScopeSelection: RecitationScopeSelection {
        switch recitationMode {
        case .autoDetect:
            return .autoDetect
        case .selectedSurah:
            return .selectedSurah(id: selectedSurahID)
        }
    }

    private var runPodAuthorizationToken: String? {
        guard backendPreset == .custom else { return nil }
        let token = runPodAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
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
            let urlText = backendPreset.recordingURLText(
                currentURLText: backendURLText,
                recitationScope: recitationScopeSelection
            )
            if urlText != backendURLText {
                backendURLText = urlText
            }
            guard let backendURL = URL(string: urlText) else {
                throw RecitationViewModelError.invalidBackendURL
            }

            try await socketClient.connect(
                url: backendURL,
                authorizationToken: runPodAuthorizationToken
            ) { [weak self] event in
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

    private func stopRecording() {
        audioStreamer.stop()
        socketClient.disconnect()
        Task { await voiceActivityDetector.reset() }
        isRecording = false
        connectionStatus = "Stopped"
        state = RecitationSessionState(
            phase: .stopped,
            headline: "Stopped",
            detail: "Tap the mic to begin again"
        )
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

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            return "Enter a valid backend URL."
        }
    }
}
