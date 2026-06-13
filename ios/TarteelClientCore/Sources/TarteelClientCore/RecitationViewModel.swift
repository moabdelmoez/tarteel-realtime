import Combine
import Foundation

public struct RecitationEventHistoryItem: Equatable, Identifiable, Sendable {
    public let id: Int
    public let typeText: String
    public let detailText: String
    public let ayahRef: String?
    public let transcript: String
    public let chunkSequence: Int?
    public let repeatCount: Int
    private let collapseKey: RecitationEventHistoryCollapseKey

    public init(event: RecitationEvent, id: Int, repeatCount: Int = 1) {
        self.id = id
        self.typeText = event.type.rawValue
        self.detailText = event.reason ?? event.type.rawValue
        self.ayahRef = event.ayahRef ?? event.startRef
        self.transcript = event.transcript
        self.chunkSequence = event.chunkSequence
        self.repeatCount = repeatCount
        self.collapseKey = Self.collapseKey(for: event)
    }

    public var repeatBadgeText: String? {
        repeatCount > 1 ? "x\(repeatCount)" : nil
    }

    fileprivate func canCollapse(with event: RecitationEvent) -> Bool {
        collapseKey == Self.collapseKey(for: event)
    }

    fileprivate func repeated(with event: RecitationEvent) -> RecitationEventHistoryItem {
        RecitationEventHistoryItem(event: event, id: id, repeatCount: repeatCount + 1)
    }

    private static func collapseKey(for event: RecitationEvent) -> RecitationEventHistoryCollapseKey {
        switch event.type {
        case .wrong:
            return RecitationEventHistoryCollapseKey(
                type: event.type,
                reason: event.reason,
                ayahRef: event.ayahRef ?? event.startRef,
                expectedRef: event.expectedRef,
                recognizedWord: event.recognizedWord
            )
        case .progress, .locked, .lockCandidate, .locating, .uncertain:
            return RecitationEventHistoryCollapseKey(
                type: event.type,
                reason: event.reason,
                ayahRef: event.ayahRef ?? event.startRef,
                expectedRef: nil,
                recognizedWord: nil
            )
        }
    }
}

private struct RecitationEventHistoryCollapseKey: Equatable, Sendable {
    let type: RecitationEventType
    let reason: String?
    let ayahRef: String?
    let expectedRef: String?
    let recognizedWord: String?
}

public struct BackendDropFeedback: Equatable, Sendable {
    public let message: String
    public let detailText: String?
    public let isError: Bool

    public init(message: String, detailText: String? = nil, isError: Bool) {
        self.message = message
        self.detailText = detailText
        self.isError = isError
    }
}

@MainActor
public final class RecitationViewModel: ObservableObject {
    @Published public private(set) var state = RecitationSessionState()
    @Published public private(set) var isRecording = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var backendPreset = BackendEndpointPreset.simulator
    @Published public private(set) var customBackendProvider = BackendProvider.runPod
    @Published public private(set) var modalASRModel = ModalASRModel.nemoFastConformerQuranAR
    @Published public private(set) var recitationMode = RecitationMode.autoDetect
    @Published public private(set) var connectionStatus = "Idle"
    @Published public private(set) var recentEventHistory: [RecitationEventHistoryItem] = []
    @Published public private(set) var backendURLValidationMessage: String?
    @Published public private(set) var backendBearerTokenPersistenceMessage: String?
    @Published public private(set) var backendDropFeedback: BackendDropFeedback?
    @Published public var backendURLText = BackendEndpointPreset.simulator.defaultURLText {
        didSet {
            if backendPreset == .custom {
                customBackendURLText = backendURLText
                preferencesStore.customBackendURLText = backendURLText
            }
            validateBackendURLText()
        }
    }
    @Published public var selectedSurahID = 108 {
        didSet {
            preferencesStore.selectedSurahID = selectedSurahID
        }
    }
    @Published public var backendBearerTokenText = "" {
        didSet {
            persistBackendBearerTokenIfNeeded()
        }
    }

    private let socketClient: BackendSocketing
    private let audioStreamer: AudioStreaming
    private let voiceActivityDetector: VoiceActivityDetecting
    private var preferencesStore: RecitationPreferencesStoring
    private let backendBearerTokenStore: BackendBearerTokenStoring
    private var isLoadingBackendBearerToken = false
    private var sequenceNumber = 0
    private var customBackendURLText = ""
    private var isStartingRecording = false
    private var audioSendTask: Task<Void, Never>?
    private var audioQueueGeneration = 0
    private var eventHistoryID = 0

    public init(
        socketClient: BackendSocketing? = nil,
        audioStreamer: AudioStreaming,
        voiceActivityDetector: VoiceActivityDetecting,
        preferencesStore: RecitationPreferencesStoring = UserDefaultsRecitationPreferencesStore(),
        backendBearerTokenStore: BackendBearerTokenStoring = VolatileBackendBearerTokenStore()
    ) {
        self.socketClient = socketClient ?? BackendWebSocketClient()
        self.audioStreamer = audioStreamer
        self.voiceActivityDetector = voiceActivityDetector
        self.preferencesStore = preferencesStore
        self.backendBearerTokenStore = backendBearerTokenStore

        let storedPreset = preferencesStore.backendPreset
        let storedProvider = preferencesStore.customBackendProvider
        let storedCustomURLText = preferencesStore.customBackendURLText
        backendPreset = storedPreset
        customBackendProvider = storedProvider
        modalASRModel = preferencesStore.modalASRModel
        customBackendURLText = storedCustomURLText
        recitationMode = preferencesStore.recitationMode
        selectedSurahID = preferencesStore.selectedSurahID
        switch storedPreset {
        case .simulator:
            backendURLText = storedPreset.defaultURLText
        case .coreML:
            backendURLText = storedPreset.defaultURLText
        case .custom:
            backendURLText = storedCustomURLText
        }
        validateBackendURLText()
        loadBackendBearerToken(for: customBackendProvider)
    }

    @available(*, deprecated, renamed: "backendBearerTokenText")
    public var runPodAPIKeyText: String {
        get { backendBearerTokenText }
        set { backendBearerTokenText = newValue }
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
        case .coreML:
            backendURLText = preset.defaultURLText
        case .custom:
            backendURLText = customBackendURLText
            loadBackendBearerToken(for: customBackendProvider)
        }
        validateBackendURLText()
    }

    public func selectCustomBackendProvider(_ provider: BackendProvider) {
        customBackendProvider = provider
        preferencesStore.customBackendProvider = provider
        loadBackendBearerToken(for: provider)
        validateBackendURLText()
    }

    public func selectModalCustomBackendProviderForSettings() {
        guard customBackendProvider != .modal else { return }
        selectCustomBackendProvider(.modal)
    }

    public func selectModalASRModel(_ model: ModalASRModel) {
        modalASRModel = model
        preferencesStore.modalASRModel = model
        validateBackendURLText()
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

    private var backendAuthorizationToken: String? {
        guard backendPreset == .custom else { return nil }
        return Self.canonicalBackendBearerToken(from: backendBearerTokenText)
    }

    private var backendBearerTokenValidationMessage: String? {
        guard backendPreset == .custom,
              customBackendProvider == .modal,
              backendAuthorizationToken == nil else {
            return nil
        }
        return Self.missingModalBearerTokenMessage
    }

    private func loadBackendBearerToken(for provider: BackendProvider) {
        isLoadingBackendBearerToken = true
        defer {
            isLoadingBackendBearerToken = false
        }

        do {
            backendBearerTokenText = try backendBearerTokenStore.token(for: provider) ?? ""
            backendBearerTokenPersistenceMessage = nil
        } catch {
            backendBearerTokenText = ""
            backendBearerTokenPersistenceMessage = "Could not read saved backend token. Paste it again before recording."
        }
    }

    private func persistBackendBearerTokenIfNeeded() {
        guard !isLoadingBackendBearerToken, backendPreset == .custom else { return }

        let tokenToStore = Self.canonicalBackendBearerToken(from: backendBearerTokenText)
        do {
            try backendBearerTokenStore.setToken(tokenToStore, for: customBackendProvider)
            backendBearerTokenPersistenceMessage = nil
        } catch {
            backendBearerTokenPersistenceMessage = "Token will be used for this session only. Keychain update failed."
        }
    }

    public var canStartRecording: Bool {
        !isRecording
            && !isStartingRecording
            && validatedCurrentBackendURLText() != nil
            && backendBearerTokenValidationMessage == nil
    }

    public var recordingActionTitle: String {
        if isStartingRecording {
            return "Connecting"
        }
        return isRecording ? "Stop Recitation" : "Start Recitation"
    }

    public var recordingActionSystemImage: String {
        if isStartingRecording {
            return "waveform.badge.magnifyingglass"
        }
        return isRecording ? "xmark.circle.fill" : "mic.circle.fill"
    }

    public var recordingActionHelp: String {
        if isStartingRecording {
            return "Connecting to the selected backend"
        }
        if isRecording {
            return "Stop the current recitation stream"
        }
        if let backendBearerTokenValidationMessage {
            return backendBearerTokenValidationMessage
        }
        return backendURLValidationMessage ?? "Start streaming microphone audio"
    }

    public var shareableSessionSummary: String {
        let events = recentEventHistory.map { item in
            let ref = item.ayahRef ?? "none"
            let repeatText = item.repeatBadgeText.map { " \($0)" } ?? ""
            return "- \(item.typeText)\(repeatText) \(ref): \(item.transcript)"
        }.joined(separator: "\n")

        return """
        Tarteel realtime session
        Connection: \(connectionStatus)
        Latest ayah: \(state.debugAyahText)
        Next expected: \(state.debugNextExpectedText)
        Latest ayah text: \(state.debugAyahBodyText)
        Transcript: \(state.debugTranscriptText)

        Recent events:
        \(events.isEmpty ? "- none" : events)
        """
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

    public func startRecording() async {
        guard !isStartingRecording, !isRecording else { return }
        isStartingRecording = true
        defer {
            isStartingRecording = false
        }

        errorMessage = nil
        recentEventHistory = []
        eventHistoryID = 0
        connectionStatus = "Connecting"
        sequenceNumber = 0
        audioSendTask?.cancel()
        audioSendTask = nil
        audioQueueGeneration += 1
        let generation = audioQueueGeneration
        await voiceActivityDetector.reset()
        guard isAudioQueueActive(generation: generation) else { return }
        state = RecitationSessionState(
            phase: .connecting,
            headline: "Connecting",
            detail: "Preparing microphone"
        )

        do {
            let urlText = backendPreset.recordingURLText(
                currentURLText: backendURLText,
                recitationScope: recitationScopeSelection,
                provider: customBackendProvider,
                modalASRModel: modalASRModel
            )
            guard backendPreset == .coreML || Self.isValidWebSocketURLText(urlText) else {
                backendURLValidationMessage = Self.invalidBackendURLMessage
                throw RecitationViewModelError.invalidBackendURL
            }
            backendURLValidationMessage = nil
            if urlText != backendURLText {
                backendURLText = urlText
            }
            if let backendBearerTokenValidationMessage {
                throw RecitationViewModelError.blocked(backendBearerTokenValidationMessage)
            }
            guard let backendURL = URL(string: urlText) else {
                throw RecitationViewModelError.invalidBackendURL
            }

            try await socketClient.connect(
                url: backendURL,
                authorizationToken: backendAuthorizationToken
            ) { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.isAudioQueueActive(generation: generation) else { return }
                    let reducerStart = Date()
                    self.recordHistoryItem(for: event)
                    let currentState = self.state
                    let nextState = currentState.applying(event)
                    let stateChanged = nextState != currentState
                    if nextState != currentState {
                        self.state = nextState
                    }
                    if self.connectionStatus != "Receiving events" {
                        self.connectionStatus = "Receiving events"
                    }
                    if self.backendPreset == .coreML {
                        CoreMLFastConformerDiagnostics.logLatencyUIEvent(
                            event: event,
                            reducerMilliseconds: Date().timeIntervalSince(reducerStart) * 1000.0,
                            stateChanged: stateChanged
                        )
                    }
                }
            }
            guard isAudioQueueActive(generation: generation) else {
                socketClient.disconnect()
                return
            }
            connectionStatus = "Connected"

            try await audioStreamer.start { [weak self] pcm, sampleRate in
                Task { @MainActor in
                    self?.enqueueAudioChunk(pcm: pcm, sampleRate: sampleRate)
                }
            }
            guard isAudioQueueActive(generation: generation) else {
                audioStreamer.stop()
                socketClient.disconnect()
                return
            }

            isRecording = true
            connectionStatus = "Streaming"
            state = RecitationSessionState(
                phase: .listening,
                headline: "Listening",
                detail: "Start reciting"
            )
        } catch {
            guard isAudioQueueActive(generation: generation) else { return }
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
        let latencyTrace = backendPreset == .coreML
            ? AudioChunkLatencyTrace()
            : nil
        audioSendTask = Task { [weak self, previousTask] in
            _ = await previousTask?.result
            guard !Task.isCancelled else { return }
            await self?.sendAudioChunk(
                sequenceNumber: chunkSequence,
                pcm: pcm,
                sampleRate: sampleRate,
                generation: generation,
                latencyTrace: latencyTrace
            )
        }
    }

    private func sendAudioChunk(
        sequenceNumber: Int,
        pcm: Data,
        sampleRate: Int,
        generation: Int,
        latencyTrace: AudioChunkLatencyTrace?
    ) async {
        guard isAudioQueueActive(generation: generation) else { return }
        var latencyTrace = latencyTrace?.markingQueuedForSend()
        let voiceActivity = await voiceActivityDetector.process(
            pcm: pcm,
            sampleRate: sampleRate
        )
        latencyTrace = latencyTrace?.markingVoiceActivityFinished()
        guard isAudioQueueActive(generation: generation) else { return }
        let payload = AudioChunkPayload(
            sequenceNumber: sequenceNumber,
            pcm: pcm,
            sampleRateHz: sampleRate,
            voiceActivity: voiceActivity,
            latencyTrace: latencyTrace
        )

        do {
            try await socketClient.send(payload)
            if let finishedTrace = latencyTrace?.markingSendFinished(),
               backendPreset == .coreML {
                CoreMLFastConformerDiagnostics.logLatencyClientChunk(
                    sequenceNumber: sequenceNumber,
                    trace: finishedTrace,
                    sampleRateHz: sampleRate,
                    pcmByteCount: pcm.count,
                    voiceActivity: voiceActivity
                )
            }
        } catch {
            guard isAudioQueueActive(generation: generation) else { return }
            await stopRecording()
            errorMessage = errorMessage(for: error, backendPreset: backendPreset)
            connectionStatus = "Error"
        }
    }

    private func isAudioQueueActive(generation: Int) -> Bool {
        generation == audioQueueGeneration && (isRecording || isStartingRecording)
    }

    public func stopRecording() async {
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

    public func validateBackendURLText() {
        guard backendPreset != .coreML else {
            backendURLValidationMessage = nil
            return
        }

        guard backendPreset == .custom else {
            backendURLValidationMessage = nil
            return
        }

        let text = backendURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            backendURLValidationMessage = "Enter a backend WebSocket URL before recording."
            return
        }

        guard validatedCurrentBackendURLText() != nil else {
            backendURLValidationMessage = "Use a ws:// or wss:// backend URL."
            return
        }

        backendURLValidationMessage = nil
    }

    @discardableResult
    public func applyDroppedBackendText(_ text: String) -> String? {
        guard !isRecording, !isStartingRecording else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = Self.inferredBackendProvider(for: trimmed)
        let normalized = BackendEndpointPreset.custom.recordingURLText(
            currentURLText: trimmed,
            provider: provider
        )
        guard Self.isValidWebSocketURLText(normalized) else {
            backendURLValidationMessage = "Drop a ws://, wss://, Modal, or RunPod backend URL."
            backendDropFeedback = BackendDropFeedback(
                message: "Drop a ws://, wss://, Modal, or RunPod backend URL.",
                isError: true
            )
            return nil
        }

        selectBackendPreset(.custom)
        selectCustomBackendProvider(provider)
        backendURLText = normalized
        validateBackendURLText()
        backendDropFeedback = BackendDropFeedback(
            message: "Backend set to \(provider.label)",
            detailText: normalized,
            isError: false
        )
        return normalized
    }

    private func recordHistoryItem(for event: RecitationEvent) {
        if let first = recentEventHistory.first, first.canCollapse(with: event) {
            recentEventHistory[0] = first.repeated(with: event)
            return
        }

        eventHistoryID += 1
        let item = RecitationEventHistoryItem(event: event, id: eventHistoryID)
        recentEventHistory.insert(item, at: 0)
        if recentEventHistory.count > 5 {
            recentEventHistory.removeLast(recentEventHistory.count - 5)
        }
    }

    private func validatedCurrentBackendURLText() -> String? {
        let normalized = backendPreset.recordingURLText(
            currentURLText: backendURLText,
            recitationScope: recitationScopeSelection,
            provider: customBackendProvider,
            modalASRModel: modalASRModel
        )
        if backendPreset == .coreML {
            return normalized
        }
        guard Self.isValidWebSocketURLText(normalized) else { return nil }
        return normalized
    }

    private static func inferredBackendProvider(for text: String) -> BackendProvider {
        let lowercasedText = text.lowercased()
        if lowercasedText.contains(".modal.run") {
            return .modal
        }
        if lowercasedText.contains(".proxy.runpod.net") || lowercasedText.contains(".api.runpod.ai") {
            return .runPod
        }
        return .generic
    }

    private static func isValidWebSocketURLText(_ text: String) -> Bool {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    private static let invalidBackendURLMessage = "Enter a valid backend URL."
    private static let missingModalBearerTokenMessage = "Enter the Modal bearer token in Settings before recording."
    private static let modalBadServerResponseMessage = "Modal rejected the WebSocket request. Check the Modal bearer token in Settings and try again."

    private func errorMessage(for error: Error, backendPreset: BackendEndpointPreset) -> String {
        if backendPreset == .coreML,
           let coreMLError = error as? CoreMLFastConformerError,
           coreMLError == .invalidModelOutput {
            return "CoreML ASR returned invalid model output. On iOS, run this model on a physical Apple Neural Engine device rather than Simulator."
        }

        let message = error.localizedDescription
        if backendPreset == .custom,
           customBackendProvider == .modal,
           Self.isBadServerResponseMessage(message) {
            return Self.modalBadServerResponseMessage
        }

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

    private static func isBadServerResponseMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("bad response")
            || message.localizedCaseInsensitiveContains("server rejected")
            || message.contains("403")
    }

    private static func canonicalBackendBearerToken(from text: String) -> String? {
        var token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("authorization:") {
            token = String(token.dropFirst("authorization:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token.isEmpty ? nil : token
    }
}

enum RecitationViewModelError: LocalizedError {
    case invalidBackendURL
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            return "Enter a valid backend URL."
        case .blocked(let message):
            return message
        }
    }
}
