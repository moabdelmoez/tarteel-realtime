import Foundation
import XCTest
@testable import TarteelClientCore

@MainActor
final class RecitationViewModelTests: XCTestCase {
    func testStartingRecordingConnectsToScopedRunPodURLAndBearerToken() async throws {
        let socket = FakeSocket()
        let audio = FakeAudioStreamer()
        let vad = FakeVoiceActivityDetector()
        let preferences = FakePreferencesStore(
            backendPreset: .custom,
            customBackendProvider: .runPod,
            customBackendURLText: "https://abc123.api.runpod.ai/ws/recitation?existing=1",
            recitationMode: .selectedSurah,
            selectedSurahID: 108
        )
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: vad,
            preferencesStore: preferences
        )
        viewModel.backendBearerTokenText = "  test-token  "

        await viewModel.startRecording()

        XCTAssertEqual(
            socket.connectedURL?.absoluteString,
            "wss://abc123.api.runpod.ai/ws/recitation?existing=1&scope=108"
        )
        XCTAssertEqual(socket.authorizationToken, "test-token")
        XCTAssertTrue(audio.didStart)
        XCTAssertEqual(viewModel.connectionStatus, "Streaming")
        XCTAssertTrue(viewModel.isRecording)
    }

    func testStartingRecordingConnectsToScopedModalURLAndBearerToken() async throws {
        let socket = FakeSocket()
        let audio = FakeAudioStreamer()
        let vad = FakeVoiceActivityDetector()
        let preferences = FakePreferencesStore(
            backendPreset: .custom,
            customBackendProvider: .modal,
            customBackendURLText: "workspace--tarteel-realtime-asr-fastapi-app.modal.run",
            recitationMode: .selectedSurah,
            selectedSurahID: 108
        )
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: vad,
            preferencesStore: preferences
        )
        viewModel.backendBearerTokenText = " modal-token "

        await viewModel.startRecording()

        XCTAssertEqual(
            socket.connectedURL?.absoluteString,
            "wss://workspace--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation?scope=108"
        )
        XCTAssertEqual(socket.authorizationToken, "modal-token")
        XCTAssertTrue(audio.didStart)
    }

    func testLoadsStoredBearerTokenForInitialCustomProvider() {
        let tokenStore = FakeBearerTokenStore(tokens: [.modal: "stored-modal-token"])
        let viewModel = RecitationViewModel(
            socketClient: FakeSocket(),
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore(
                backendPreset: .custom,
                customBackendProvider: .modal,
                customBackendURLText: "wss://example.modal.run/ws/recitation"
            ),
            backendBearerTokenStore: tokenStore
        )

        XCTAssertEqual(viewModel.backendBearerTokenText, "stored-modal-token")
        XCTAssertNil(viewModel.backendBearerTokenPersistenceMessage)
    }

    func testSwitchingCustomProviderLoadsProviderSpecificStoredToken() {
        let tokenStore = FakeBearerTokenStore(tokens: [
            .runPod: "stored-runpod-token",
            .modal: "stored-modal-token",
        ])
        let viewModel = RecitationViewModel(
            socketClient: FakeSocket(),
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore(
                backendPreset: .custom,
                customBackendProvider: .runPod,
                customBackendURLText: "wss://example.test/ws/recitation"
            ),
            backendBearerTokenStore: tokenStore
        )

        XCTAssertEqual(viewModel.backendBearerTokenText, "stored-runpod-token")

        viewModel.selectCustomBackendProvider(.modal)

        XCTAssertEqual(viewModel.backendBearerTokenText, "stored-modal-token")
        XCTAssertEqual(viewModel.customBackendProvider, .modal)
    }

    func testEditingBearerTokenPersistsTrimmedTokenForCurrentProvider() {
        let tokenStore = FakeBearerTokenStore()
        let viewModel = RecitationViewModel(
            socketClient: FakeSocket(),
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore(
                backendPreset: .custom,
                customBackendProvider: .modal,
                customBackendURLText: "wss://example.modal.run/ws/recitation"
            ),
            backendBearerTokenStore: tokenStore
        )

        viewModel.backendBearerTokenText = "  new-modal-token  "

        XCTAssertEqual(tokenStore.tokens[.modal], "new-modal-token")
        XCTAssertNil(viewModel.backendBearerTokenPersistenceMessage)
    }

    func testClearingBearerTokenDeletesStoredTokenForCurrentProvider() {
        let tokenStore = FakeBearerTokenStore(tokens: [.modal: "stored-modal-token"])
        let viewModel = RecitationViewModel(
            socketClient: FakeSocket(),
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore(
                backendPreset: .custom,
                customBackendProvider: .modal,
                customBackendURLText: "wss://example.modal.run/ws/recitation"
            ),
            backendBearerTokenStore: tokenStore
        )

        viewModel.backendBearerTokenText = " "

        XCTAssertNil(tokenStore.tokens[.modal])
        XCTAssertNil(viewModel.backendBearerTokenPersistenceMessage)
    }

    func testTokenStorageWriteFailureKeepsTypedTokenForCurrentSession() {
        let tokenStore = ThrowingBearerTokenStore()
        let viewModel = RecitationViewModel(
            socketClient: FakeSocket(),
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore(
                backendPreset: .custom,
                customBackendProvider: .modal,
                customBackendURLText: "wss://example.modal.run/ws/recitation"
            ),
            backendBearerTokenStore: tokenStore
        )

        viewModel.backendBearerTokenText = "modal-token"

        XCTAssertEqual(viewModel.backendBearerTokenText, "modal-token")
        XCTAssertEqual(
            viewModel.backendBearerTokenPersistenceMessage,
            "Token will be used for this session only. Keychain update failed."
        )
    }

    func testDuplicateToggleWhileConnectingOnlyStartsOneSocketConnection() async throws {
        let socket = SuspendedConnectSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        viewModel.toggleRecording()
        await socket.waitForConnectCount(1)
        viewModel.toggleRecording()
        await drainScheduledTasks()

        XCTAssertEqual(socket.connectCallCount, 1)

        await socket.releaseAllConnections()
        await drainScheduledTasks()
    }

    func testRecordingActionReflectsConnectingStateBeforeStreaming() async throws {
        let socket = SuspendedConnectSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        viewModel.toggleRecording()
        await socket.waitForConnectCount(1)

        XCTAssertEqual(viewModel.recordingActionTitle, "Connecting")
        XCTAssertEqual(viewModel.recordingActionSystemImage, "waveform.badge.magnifyingglass")
        XCTAssertFalse(viewModel.canStartRecording)

        await socket.releaseAllConnections()
        await drainScheduledTasks()
    }

    func testStopWhileConnectIsSuspendedKeepsSessionStopped() async throws {
        let socket = SuspendedConnectSocket()
        let audio = FakeAudioStreamer()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        let startTask = Task {
            await viewModel.startRecording()
        }
        await socket.waitForConnectCount(1)
        await viewModel.stopRecording()
        await socket.releaseAllConnections()
        await startTask.value
        await drainScheduledTasks()

        XCTAssertFalse(audio.didStart)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(viewModel.connectionStatus, "Stopped")
        XCTAssertEqual(viewModel.state.phase, .stopped)
    }

    func testAudioChunksIncludeVADPayloadAndIncrementSequence() async throws {
        let socket = FakeSocket()
        let audio = FakeAudioStreamer()
        let vad = FakeVoiceActivityDetector()
        let expectedVoiceActivity = [
            VoiceActivityPayload(probability: 0.7, isSpeechActive: true, event: .speechStart),
            VoiceActivityPayload(probability: 0.2, isSpeechActive: false, event: .speechEnd),
        ]
        vad.payloads = expectedVoiceActivity
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: vad,
            preferencesStore: FakePreferencesStore()
        )

        await viewModel.startRecording()
        await audio.emit(pcm: Data([0x01, 0x02]), sampleRate: 16_000)
        await audio.emit(pcm: Data([0x03, 0x04]), sampleRate: 16_000)

        XCTAssertEqual(socket.sentPayloads.map(\.sequenceNumber), [0, 1])
        XCTAssertEqual(socket.sentPayloads.map(\.voiceActivity), expectedVoiceActivity)
    }

    func testAudioChunksWaitForPreviousVADAndKeepCaptureOrderSequences() async throws {
        let socket = FakeSocket()
        let audio = FakeAudioStreamer()
        let vad = FirstChunkSuspendingVoiceActivityDetector()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: vad,
            preferencesStore: FakePreferencesStore()
        )

        await viewModel.startRecording()
        await audio.emit(pcm: Data([0x01]), sampleRate: 16_000)
        await vad.waitForProcessCount(1)
        await audio.emit(pcm: Data([0x02]), sampleRate: 16_000)
        await drainScheduledTasks()

        let processCountWhileFirstChunkIsSuspended = await vad.currentProcessCount()
        XCTAssertEqual(processCountWhileFirstChunkIsSuspended, 1)
        XCTAssertEqual(socket.sentPayloads.count, 0)

        await vad.releaseFirstProcess()
        await vad.waitForProcessCount(2)
        await drainScheduledTasks()

        XCTAssertEqual(socket.sentPayloads.map(\.sequenceNumber), [0, 1])
        XCTAssertEqual(socket.sentPayloads.map(\.pcm), [Data([0x01]), Data([0x02])])
    }

    func testStaleQueuedAudioSendFailureAfterRestartDoesNotStopNewSession() async throws {
        let socket = FailingSuspendedSendSocket()
        let firstAudio = FakeAudioStreamer()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: firstAudio,
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        await viewModel.startRecording()
        await firstAudio.emit(pcm: Data([0x01]), sampleRate: 16_000)
        await socket.waitForSendCount(1)
        await viewModel.stopRecording()
        await viewModel.startRecording()

        await socket.failSuspendedSends()
        await drainScheduledTasks()

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(viewModel.connectionStatus, "Streaming")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(socket.disconnectCount, 1)
    }

    func testSocketEventsReduceRecitationSessionState() async throws {
        let socket = FakeSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        await viewModel.startRecording()
        await socket.emit(
            RecitationEvent(
                type: .locked,
                transcript: "raw transcript",
                confidence: 0.9,
                chunkSequence: 4,
                reason: "unique_match",
                candidateRefs: [],
                ayahText: "قُلْ هُوَ اللَّهُ أَحَدٌ",
                ayahRef: "112:1",
                startRef: "112:1:1",
                nextExpectedRef: nil,
                consumedWords: 4,
                expectedRef: nil,
                expectedWord: nil,
                recognizedWord: nil
            )
        )

        XCTAssertEqual(viewModel.state.currentAyahRef, "112:1")
        XCTAssertEqual(viewModel.state.currentAyahText, "قُلْ هُوَ اللَّهُ أَحَدٌ")
        XCTAssertEqual(viewModel.state.lastEventType, .locked)
        XCTAssertEqual(viewModel.connectionStatus, "Receiving events")
    }

    func testRecentEventHistoryKeepsNewestFiveEventsAndShareSummary() async throws {
        let socket = FakeSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )
        await viewModel.startRecording()

        for sequence in 0..<7 {
            await socket.emit(
                RecitationEvent(
                    type: sequence == 0 ? .locked : .progress,
                    transcript: "transcript \(sequence)",
                    confidence: 0.9,
                    chunkSequence: sequence,
                    reason: "test_event",
                    candidateRefs: [],
                    ayahText: "ayah \(sequence)",
                    ayahRef: "112:\(sequence + 1)",
                    startRef: "112:\(sequence + 1):1",
                    nextExpectedRef: nil,
                    consumedWords: 1,
                    expectedRef: nil,
                    expectedWord: nil,
                    recognizedWord: nil
                )
            )
        }

        XCTAssertEqual(viewModel.recentEventHistory.count, 5)
        XCTAssertEqual(viewModel.recentEventHistory.first?.chunkSequence, 6)
        XCTAssertEqual(viewModel.recentEventHistory.last?.chunkSequence, 2)
        XCTAssertTrue(viewModel.shareableSessionSummary.contains("Connection: Receiving events"))
        XCTAssertTrue(viewModel.shareableSessionSummary.contains("112:7"))
        XCTAssertTrue(viewModel.shareableSessionSummary.contains("transcript 6"))
    }

    func testRecentEventHistoryCollapsesRepeatedUncertainEvents() async throws {
        let socket = FakeSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )
        await viewModel.startRecording()

        for sequence in 0..<8 {
            await socket.emit(
                RecitationEvent(
                    type: .uncertain,
                    transcript: "",
                    confidence: 0.0,
                    chunkSequence: sequence,
                    reason: "waiting_for_audio_buffer",
                    candidateRefs: [],
                    ayahRef: nil,
                    startRef: nil,
                    nextExpectedRef: nil,
                    consumedWords: 0,
                    expectedRef: nil,
                    expectedWord: nil,
                    recognizedWord: nil
                )
            )
        }

        XCTAssertEqual(viewModel.recentEventHistory.count, 1)
        XCTAssertEqual(viewModel.recentEventHistory.first?.typeText, "uncertain")
        XCTAssertEqual(viewModel.recentEventHistory.first?.repeatCount, 8)
        XCTAssertEqual(viewModel.recentEventHistory.first?.chunkSequence, 7)
    }

    func testRecentEventHistoryCollapsesRepeatedProgressForSameAyah() async throws {
        let socket = FakeSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )
        await viewModel.startRecording()

        for sequence in 0..<4 {
            await socket.emit(
                RecitationEvent(
                    type: .progress,
                    transcript: "progress transcript \(sequence)",
                    confidence: 0.7,
                    chunkSequence: sequence,
                    reason: "tolerant_progression",
                    candidateRefs: [],
                    ayahText: "ayah one",
                    ayahRef: "60:1",
                    startRef: "60:1:1",
                    nextExpectedRef: nil,
                    consumedWords: 1,
                    expectedRef: nil,
                    expectedWord: nil,
                    recognizedWord: nil
                )
            )
        }

        XCTAssertEqual(viewModel.recentEventHistory.count, 1)
        XCTAssertEqual(viewModel.recentEventHistory.first?.typeText, "progress")
        XCTAssertEqual(viewModel.recentEventHistory.first?.ayahRef, "60:1")
        XCTAssertEqual(viewModel.recentEventHistory.first?.repeatCount, 4)
        XCTAssertEqual(viewModel.recentEventHistory.first?.chunkSequence, 3)
        XCTAssertEqual(viewModel.recentEventHistory.first?.transcript, "progress transcript 3")
    }

    func testRecentEventHistoryKeepsNewAyahProgressAsSeparateRows() async throws {
        let socket = FakeSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )
        await viewModel.startRecording()

        for sequence in 0..<3 {
            await socket.emit(
                RecitationEvent(
                    type: .progress,
                    transcript: "progress transcript \(sequence)",
                    confidence: 0.8,
                    chunkSequence: sequence,
                    reason: "tolerant_progression",
                    candidateRefs: [],
                    ayahText: "ayah \(sequence)",
                    ayahRef: "60:\(sequence + 1)",
                    startRef: "60:\(sequence + 1):1",
                    nextExpectedRef: nil,
                    consumedWords: 1,
                    expectedRef: nil,
                    expectedWord: nil,
                    recognizedWord: nil
                )
            )
        }

        XCTAssertEqual(viewModel.recentEventHistory.count, 3)
        XCTAssertEqual(viewModel.recentEventHistory.map(\.ayahRef), ["60:3", "60:2", "60:1"])
        XCTAssertEqual(viewModel.recentEventHistory.map(\.repeatCount), [1, 1, 1])
    }

    func testStaleSocketEventAfterStopDoesNotMutateStoppedState() async throws {
        let socket = ConnectionCapturingSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        await viewModel.startRecording()
        await viewModel.stopRecording()
        await socket.emit(
            event: RecitationEvent(
                type: .locked,
                transcript: "old transcript",
                confidence: 0.9,
                chunkSequence: 7,
                reason: "stale",
                candidateRefs: [],
                ayahText: "old ayah",
                ayahRef: "2:1",
                startRef: "2:1:1",
                nextExpectedRef: nil,
                consumedWords: 2,
                expectedRef: nil,
                expectedWord: nil,
                recognizedWord: nil
            ),
            connectionIndex: 0
        )

        XCTAssertEqual(viewModel.state.phase, .stopped)
        XCTAssertNil(viewModel.state.currentAyahRef)
        XCTAssertEqual(viewModel.connectionStatus, "Stopped")
    }

    func testStopDisconnectsAndResetsVAD() async throws {
        let socket = FakeSocket()
        let audio = FakeAudioStreamer()
        let vad = FakeVoiceActivityDetector()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: vad,
            preferencesStore: FakePreferencesStore()
        )

        await viewModel.startRecording()
        await viewModel.stopRecording()

        XCTAssertTrue(audio.didStop)
        XCTAssertEqual(socket.disconnectCount, 1)
        XCTAssertEqual(vad.resetCount, 2)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(viewModel.state.phase, .stopped)
    }

    func testBackendURLValidationAndDroppedURLApplication() {
        let viewModel = RecitationViewModel(
            socketClient: FakeSocket(),
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        XCTAssertNil(viewModel.applyDroppedBackendText("not a websocket url"))
        XCTAssertNotNil(viewModel.backendURLValidationMessage)

        let normalizedURL = viewModel.applyDroppedBackendText(
            "https://workspace--tarteel-realtime-asr-fastapi-app.modal.run"
        )

        XCTAssertEqual(
            normalizedURL,
            "wss://workspace--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation"
        )
        XCTAssertEqual(viewModel.backendPreset, .custom)
        XCTAssertEqual(viewModel.customBackendProvider, .modal)
        XCTAssertEqual(viewModel.backendURLText, normalizedURL)
        XCTAssertNil(viewModel.backendURLValidationMessage)
    }

    func testDroppedBackendTextPublishesMainSurfaceFeedback() {
        let viewModel = RecitationViewModel(
            socketClient: FakeSocket(),
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        XCTAssertNil(viewModel.applyDroppedBackendText("not a websocket url"))
        XCTAssertEqual(viewModel.backendDropFeedback?.message, "Drop a ws://, wss://, Modal, or RunPod backend URL.")
        XCTAssertTrue(viewModel.backendDropFeedback?.isError == true)

        let normalizedURL = viewModel.applyDroppedBackendText(
            "https://workspace--tarteel-realtime-asr-fastapi-app.modal.run"
        )

        XCTAssertEqual(
            normalizedURL,
            "wss://workspace--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation"
        )
        XCTAssertEqual(viewModel.backendDropFeedback?.message, "Backend set to Modal")
        XCTAssertEqual(viewModel.backendDropFeedback?.detailText, normalizedURL)
        XCTAssertFalse(viewModel.backendDropFeedback?.isError == true)
    }
}

@MainActor
private final class FakeSocket: BackendSocketing {
    private(set) var connectedURL: URL?
    private(set) var authorizationToken: String?
    private(set) var sentPayloads: [AudioChunkPayload] = []
    private(set) var disconnectCount = 0
    private var onEvent: (@Sendable (RecitationEvent) -> Void)?

    func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        connectedURL = url
        self.authorizationToken = authorizationToken
        self.onEvent = onEvent
    }

    func send(_ payload: AudioChunkPayload) async throws {
        sentPayloads.append(payload)
    }

    func disconnect() {
        disconnectCount += 1
    }

    func emit(_ event: RecitationEvent) async {
        onEvent?(event)
        await drainScheduledTasks()
    }
}

private final class FakeAudioStreamer: AudioStreaming, @unchecked Sendable {
    private(set) var didStart = false
    private(set) var didStop = false
    private var onChunk: (@Sendable (Data, Int) -> Void)?

    func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws {
        didStart = true
        self.onChunk = onChunk
    }

    func stop() {
        didStop = true
    }

    func emit(pcm: Data, sampleRate: Int) async {
        onChunk?(pcm, sampleRate)
        await drainScheduledTasks()
    }
}

@MainActor
private final class FailingSuspendedSendSocket: BackendSocketing {
    private(set) var disconnectCount = 0
    private var sendCount = 0
    private var sendWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var suspendedSends: [CheckedContinuation<Void, Error>] = []

    func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {}

    func send(_ payload: AudioChunkPayload) async throws {
        sendCount += 1
        resumeSatisfiedWaiters()
        try await withCheckedThrowingContinuation { continuation in
            suspendedSends.append(continuation)
        }
    }

    func disconnect() {
        disconnectCount += 1
    }

    func waitForSendCount(_ count: Int) async {
        guard sendCount < count else { return }
        await withCheckedContinuation { continuation in
            sendWaiters.append((count, continuation))
        }
    }

    func failSuspendedSends() async {
        let continuations = suspendedSends
        suspendedSends.removeAll()
        continuations.forEach { $0.resume(throwing: TestSocketError.sendFailed) }
    }

    private func resumeSatisfiedWaiters() {
        let ready = sendWaiters.filter { sendCount >= $0.0 }
        sendWaiters.removeAll { sendCount >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

@MainActor
private final class ConnectionCapturingSocket: BackendSocketing {
    private var onEvents: [@Sendable (RecitationEvent) -> Void] = []

    func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        onEvents.append(onEvent)
    }

    func send(_ payload: AudioChunkPayload) async throws {}

    func disconnect() {}

    func emit(event: RecitationEvent, connectionIndex: Int) async {
        onEvents[connectionIndex](event)
        await drainScheduledTasks()
    }
}

@MainActor
private final class SuspendedConnectSocket: BackendSocketing {
    private(set) var connectCallCount = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var connectionContinuations: [CheckedContinuation<Void, Never>] = []

    func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        connectCallCount += 1
        resumeSatisfiedWaiters()
        await withCheckedContinuation { continuation in
            connectionContinuations.append(continuation)
        }
    }

    func send(_ payload: AudioChunkPayload) async throws {}

    func disconnect() {}

    func waitForConnectCount(_ count: Int) async {
        guard connectCallCount < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func releaseAllConnections() async {
        let continuations = connectionContinuations
        connectionContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func resumeSatisfiedWaiters() {
        let ready = waiters.filter { connectCallCount >= $0.0 }
        waiters.removeAll { connectCallCount >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

private actor FirstChunkSuspendingVoiceActivityDetector: VoiceActivityDetecting {
    private(set) var processCount = 0
    private var firstProcessContinuation: CheckedContinuation<VoiceActivityPayload?, Never>?
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload? {
        processCount += 1
        resumeSatisfiedWaiters()
        if processCount == 1 {
            return await withCheckedContinuation { continuation in
                firstProcessContinuation = continuation
            }
        }
        return VoiceActivityPayload(probability: 0.2, isSpeechActive: false, event: .speechEnd)
    }

    func reset() async {}

    func waitForProcessCount(_ count: Int) async {
        guard processCount < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func currentProcessCount() -> Int {
        processCount
    }

    func releaseFirstProcess() {
        firstProcessContinuation?.resume(
            returning: VoiceActivityPayload(probability: 0.8, isSpeechActive: true, event: .speechStart)
        )
        firstProcessContinuation = nil
    }

    private func resumeSatisfiedWaiters() {
        let ready = waiters.filter { processCount >= $0.0 }
        waiters.removeAll { processCount >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

private final class FakeVoiceActivityDetector: VoiceActivityDetecting, @unchecked Sendable {
    var payloads: [VoiceActivityPayload?] = [
        VoiceActivityPayload(probability: 0.5, isSpeechActive: true, event: .speechStart)
    ]
    private(set) var resetCount = 0

    func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload? {
        if payloads.isEmpty {
            return nil
        }
        return payloads.removeFirst()
    }

    func reset() async {
        resetCount += 1
    }
}

private func drainScheduledTasks() async {
    for _ in 0..<20 {
        await Task.yield()
    }
    try? await Task.sleep(nanoseconds: 1_000_000)
}

private struct FakePreferencesStore: RecitationPreferencesStoring {
    var backendPreset: BackendEndpointPreset
    var customBackendProvider: BackendProvider
    var customBackendURLText: String
    var recitationMode: RecitationMode
    var selectedSurahID: Int

    init(
        backendPreset: BackendEndpointPreset = .simulator,
        customBackendProvider: BackendProvider = .runPod,
        customBackendURLText: String = "",
        recitationMode: RecitationMode = .autoDetect,
        selectedSurahID: Int = 108
    ) {
        self.backendPreset = backendPreset
        self.customBackendProvider = customBackendProvider
        self.customBackendURLText = customBackendURLText
        self.recitationMode = recitationMode
        self.selectedSurahID = selectedSurahID
    }
}

private final class FakeBearerTokenStore: BackendBearerTokenStoring {
    private(set) var tokens: [BackendProvider: String]

    init(tokens: [BackendProvider: String] = [:]) {
        self.tokens = tokens
    }

    func token(for provider: BackendProvider) throws -> String? {
        tokens[provider]
    }

    func setToken(_ token: String?, for provider: BackendProvider) throws {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedToken.isEmpty {
            tokens.removeValue(forKey: provider)
        } else {
            tokens[provider] = trimmedToken
        }
    }
}

private final class ThrowingBearerTokenStore: BackendBearerTokenStoring {
    func token(for provider: BackendProvider) throws -> String? {
        nil
    }

    func setToken(_ token: String?, for provider: BackendProvider) throws {
        throw TestTokenStoreError.writeFailed
    }
}

private enum TestTokenStoreError: Error {
    case writeFailed
}

private enum TestSocketError: LocalizedError {
    case sendFailed

    var errorDescription: String? {
        "send failed"
    }
}
