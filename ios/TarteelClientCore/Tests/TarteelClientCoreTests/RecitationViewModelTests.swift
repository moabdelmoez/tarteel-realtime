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
        viewModel.runPodAPIKeyText = "  test-token  "

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
    var customBackendURLText: String
    var recitationMode: RecitationMode
    var selectedSurahID: Int

    init(
        backendPreset: BackendEndpointPreset = .simulator,
        customBackendURLText: String = "",
        recitationMode: RecitationMode = .autoDetect,
        selectedSurahID: Int = 108
    ) {
        self.backendPreset = backendPreset
        self.customBackendURLText = customBackendURLText
        self.recitationMode = recitationMode
        self.selectedSurahID = selectedSurahID
    }
}
