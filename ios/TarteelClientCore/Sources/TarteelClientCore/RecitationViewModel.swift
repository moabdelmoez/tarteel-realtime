import Combine
import Foundation

@MainActor
public final class RecitationViewModel: ObservableObject {
    @Published public private(set) var state = RecitationSessionState()
    @Published public private(set) var isRecording = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var backendPreset = BackendEndpointPreset.simulator
    @Published public private(set) var recitationMode = RecitationMode.autoDetect
    @Published public private(set) var connectionStatus = "Idle"
    @Published public var backendURLText = BackendEndpointPreset.simulator.defaultURLText {
        didSet {
            guard backendPreset == .custom else { return }
            customBackendURLText = backendURLText
            preferencesStore.customBackendURLText = backendURLText
        }
    }
    @Published public var selectedSurahID = 108 {
        didSet {
            preferencesStore.selectedSurahID = selectedSurahID
        }
    }
    @Published public var runPodAPIKeyText = ""

    private let socketClient: BackendSocketing
    private let audioStreamer: AudioStreaming
    private let voiceActivityDetector: VoiceActivityDetecting
    private var preferencesStore: RecitationPreferencesStoring
    private var sequenceNumber = 0
    private var customBackendURLText = ""
    private var isStartingRecording = false
    private var audioSendTask: Task<Void, Never>?
    private var audioQueueGeneration = 0

    public init(
        socketClient: BackendSocketing? = nil,
        audioStreamer: AudioStreaming,
        voiceActivityDetector: VoiceActivityDetecting,
        preferencesStore: RecitationPreferencesStoring = UserDefaultsRecitationPreferencesStore()
    ) {
        self.socketClient = socketClient ?? BackendWebSocketClient()
        self.audioStreamer = audioStreamer
        self.voiceActivityDetector = voiceActivityDetector
        self.preferencesStore = preferencesStore

        let storedPreset = preferencesStore.backendPreset
        let storedCustomURLText = preferencesStore.customBackendURLText
        backendPreset = storedPreset
        customBackendURLText = storedCustomURLText
        recitationMode = preferencesStore.recitationMode
        selectedSurahID = preferencesStore.selectedSurahID
        switch storedPreset {
        case .simulator:
            backendURLText = storedPreset.defaultURLText
        case .custom:
            backendURLText = storedCustomURLText
        }
    }

    public func selectBackendPreset(_ preset: BackendEndpointPreset) {
        if backendPreset == .custom {
            customBackendURLText = backendURLText
            preferencesStore.customBackendURLText = backendURLText
        }

        backendPreset = preset
        preferencesStore.backendPreset = preset
        switch preset {
        case .simulator:
            backendURLText = preset.defaultURLText
        case .custom:
            backendURLText = customBackendURLText
        }
    }

    public func selectRecitationMode(_ mode: RecitationMode) {
        recitationMode = mode
        preferencesStore.recitationMode = mode
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

    public func toggleRecording() {
        if isRecording {
            Task {
                await stopRecording()
            }
            return
        }

        guard !isStartingRecording else { return }
        Task {
            await startRecording()
        }
    }

    func startRecording() async {
        guard !isStartingRecording, !isRecording else { return }
        isStartingRecording = true
        defer {
            isStartingRecording = false
        }

        errorMessage = nil
        connectionStatus = "Connecting"
        sequenceNumber = 0
        audioSendTask?.cancel()
        audioSendTask = nil
        audioQueueGeneration += 1
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
                    self?.enqueueAudioChunk(pcm: pcm, sampleRate: sampleRate)
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
            await stopRecording()
            errorMessage = errorMessage(for: error, backendPreset: backendPreset)
            connectionStatus = "Error"
        }
    }

    private func enqueueAudioChunk(pcm: Data, sampleRate: Int) {
        let chunkSequence = sequenceNumber
        sequenceNumber += 1
        let previousTask = audioSendTask
        let generation = audioQueueGeneration
        audioSendTask = Task { [weak self, previousTask] in
            _ = await previousTask?.result
            guard !Task.isCancelled else { return }
            await self?.sendAudioChunk(
                sequenceNumber: chunkSequence,
                pcm: pcm,
                sampleRate: sampleRate,
                generation: generation
            )
        }
    }

    private func sendAudioChunk(
        sequenceNumber: Int,
        pcm: Data,
        sampleRate: Int,
        generation: Int
    ) async {
        guard isAudioQueueActive(generation: generation) else { return }
        let voiceActivity = await voiceActivityDetector.process(
            pcm: pcm,
            sampleRate: sampleRate
        )
        guard isAudioQueueActive(generation: generation) else { return }
        let payload = AudioChunkPayload(
            sequenceNumber: sequenceNumber,
            pcm: pcm,
            sampleRateHz: sampleRate,
            voiceActivity: voiceActivity
        )

        do {
            try await socketClient.send(payload)
        } catch {
            await stopRecording()
            errorMessage = errorMessage(for: error, backendPreset: backendPreset)
            connectionStatus = "Error"
        }
    }

    private func isAudioQueueActive(generation: Int) -> Bool {
        generation == audioQueueGeneration && (isRecording || isStartingRecording)
    }

    func stopRecording() async {
        audioStreamer.stop()
        audioQueueGeneration += 1
        audioSendTask?.cancel()
        audioSendTask = nil
        socketClient.disconnect()
        await voiceActivityDetector.reset()
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
