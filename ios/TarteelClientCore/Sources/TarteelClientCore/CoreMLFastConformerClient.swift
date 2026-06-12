import Accelerate
@preconcurrency import CoreML
import Foundation
import OSLog

enum CoreMLFastConformerDiagnostics {
    static let logger = Logger(
        subsystem: "dev.mostafa.TarteelPrototype",
        category: "CoreMLFastConformer"
    )

    static func logConnect(url: URL) {
        logger.notice("coreml_asr_connect url=\(url.absoluteString, privacy: .public)")
    }

    static func logDisconnect() {
        logger.notice("coreml_asr_disconnect")
    }

    static func logModelLoaded(modelURL: URL, tokenCount: Int) {
        logger.notice("coreml_asr_model_loaded model=\(modelURL.lastPathComponent, privacy: .public) tokens=\(tokenCount, privacy: .public)")
    }

    static func logReset() {
        logger.notice("coreml_asr_reset")
    }

    static func logBuffering(
        chunkSequence: Int,
        bufferedSamples: Int,
        requiredSamples: Int,
        sampleRateHz: Int,
        pcmByteCount: Int
    ) {
        logger.notice(
            "coreml_asr_buffering chunk_sequence=\(chunkSequence, privacy: .public) buffered_samples=\(bufferedSamples, privacy: .public) required_samples=\(requiredSamples, privacy: .public) sample_rate_hz=\(sampleRateHz, privacy: .public) pcm_bytes=\(pcmByteCount, privacy: .public)"
        )
    }

    static func logAudioWindow(
        chunkSequence: Int,
        windowIndex: Int,
        metrics: CoreMLFastConformerAudioWindowMetrics
    ) {
        let rmsText = String(format: "%.5f", metrics.rmsAmplitude)
        let peakText = String(format: "%.5f", metrics.peakAmplitude)
        let nearSilenceText = String(format: "%.3f", metrics.nearSilenceRatio)
        let vadProbabilityText = metrics.voiceActivityMeanProbability.map {
            String(format: "%.3f", $0)
        } ?? "none"
        let vadEventText = metrics.voiceActivityLatestEvent?.rawValue ?? "none"
        logger.notice(
            "coreml_asr_audio_window chunk_sequence=\(chunkSequence, privacy: .public) window_index=\(windowIndex, privacy: .public) sample_count=\(metrics.sampleCount, privacy: .public) rms=\(rmsText, privacy: .public) peak=\(peakText, privacy: .public) near_silence_ratio=\(nearSilenceText, privacy: .public) vad_probability=\(vadProbabilityText, privacy: .public) vad_speech_chunks=\(metrics.voiceActivitySpeechChunkCount, privacy: .public) vad_observations=\(metrics.voiceActivityObservationCount, privacy: .public) vad_event=\(vadEventText, privacy: .public)"
        )
    }

    static func logWindow(
        chunkSequence: Int,
        windowIndex: Int,
        inferenceMilliseconds: Double,
        confidence: Double,
        emittedTokenCount: Int,
        transcript: String,
        cumulativeTranscript: String
    ) {
        let inferenceText = String(format: "%.1f", inferenceMilliseconds)
        let confidenceText = String(format: "%.4f", confidence)
        guard !transcript.isEmpty else {
            logger.notice(
                "coreml_asr_blank chunk_sequence=\(chunkSequence, privacy: .public) window_index=\(windowIndex, privacy: .public) inference_ms=\(inferenceText, privacy: .public) confidence=\(confidenceText, privacy: .public) emitted_tokens=\(emittedTokenCount, privacy: .public)"
            )
            return
        }
        logger.notice(
            "coreml_asr_transcript chunk_sequence=\(chunkSequence, privacy: .public) window_index=\(windowIndex, privacy: .public) inference_ms=\(inferenceText, privacy: .public) confidence=\(confidenceText, privacy: .public) emitted_tokens=\(emittedTokenCount, privacy: .public) transcript=\"\(transcript, privacy: .public)\" cumulative_transcript=\"\(cumulativeTranscript, privacy: .public)\""
        )
    }

    static func logStreamReset(
        reason: CoreMLFastConformerStreamResetReason,
        chunkSequence: Int,
        windowIndex: Int,
        blankStreak: Int,
        metrics: CoreMLFastConformerAudioWindowMetrics
    ) {
        let rmsText = String(format: "%.5f", metrics.rmsAmplitude)
        let vadProbabilityText = metrics.voiceActivityMeanProbability.map {
            String(format: "%.3f", $0)
        } ?? "none"
        logger.notice(
            "coreml_asr_stream_reset reason=\(reason.rawValue, privacy: .public) chunk_sequence=\(chunkSequence, privacy: .public) window_index=\(windowIndex, privacy: .public) blank_streak=\(blankStreak, privacy: .public) rms=\(rmsText, privacy: .public) vad_speech_chunks=\(metrics.voiceActivitySpeechChunkCount, privacy: .public) vad_probability=\(vadProbabilityText, privacy: .public)"
        )
    }

    static func shouldLogBuffering(chunkSequence: Int) -> Bool {
        chunkSequence == 0 || chunkSequence % 10 == 0
    }

    static func logInvalidOutput(reason: String, detail: String) {
        logger.error("coreml_asr_invalid_output reason=\(reason, privacy: .public) detail=\(detail, privacy: .public)")
    }

    static func logCorpusLoaded(source: String, ayahCount: Int) {
        logger.notice("coreml_asr_quran_corpus source=\(source, privacy: .public) ayahs=\(ayahCount, privacy: .public)")
    }

    static func logAudioCaptureStarted(url: URL) {
        logger.notice("coreml_asr_audio_capture_started path=\(url.path, privacy: .public)")
    }

    static func logAudioCaptureFinished(url: URL, pcmBytes: Int) {
        logger.notice("coreml_asr_audio_capture_finished path=\(url.path, privacy: .public) pcm_bytes=\(pcmBytes, privacy: .public)")
    }

    static func logAudioCaptureFailed(url: URL, error: Error) {
        logger.error("coreml_asr_audio_capture_failed path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
    }

    static func logLatencyClientChunk(
        sequenceNumber: Int,
        trace: AudioChunkLatencyTrace,
        sampleRateHz: Int,
        pcmByteCount: Int,
        voiceActivity: VoiceActivityPayload?
    ) {
        let queueText = AudioChunkLatencyTrace.format(milliseconds: trace.queueDelayMilliseconds)
        let vadText = AudioChunkLatencyTrace.format(milliseconds: trace.voiceActivityMilliseconds)
        let sendText = AudioChunkLatencyTrace.format(milliseconds: trace.sendMilliseconds)
        let totalText = AudioChunkLatencyTrace.format(milliseconds: trace.totalMilliseconds)
        let vadEventText = voiceActivity?.event?.rawValue ?? "none"
        let vadProbabilityText = voiceActivity.map {
            String(format: "%.3f", $0.probability)
        } ?? "none"
        logger.notice(
            "coreml_asr_latency_client_chunk chunk_sequence=\(sequenceNumber, privacy: .public) queue_ms=\(queueText, privacy: .public) vad_ms=\(vadText, privacy: .public) send_ms=\(sendText, privacy: .public) total_ms=\(totalText, privacy: .public) sample_rate_hz=\(sampleRateHz, privacy: .public) pcm_bytes=\(pcmByteCount, privacy: .public) vad_probability=\(vadProbabilityText, privacy: .public) vad_event=\(vadEventText, privacy: .public)"
        )
    }

    static func logLatencyModelWindow(
        chunkSequence: Int,
        windowIndex: Int,
        summary: CoreMLFastConformerWindowLatencySummary,
        inferenceMilliseconds: Double,
        emittedTokenCount: Int,
        emittedText: Bool
    ) {
        let firstText = AudioChunkLatencyTrace.format(
            milliseconds: summary.firstChunkToWindowMilliseconds
        )
        let lastText = AudioChunkLatencyTrace.format(
            milliseconds: summary.lastChunkToWindowMilliseconds
        )
        let lastVADText = AudioChunkLatencyTrace.format(
            milliseconds: summary.lastVADToWindowMilliseconds
        )
        let inferenceText = String(format: "%.1f", inferenceMilliseconds)
        logger.notice(
            "coreml_asr_latency_model_window chunk_sequence=\(chunkSequence, privacy: .public) window_index=\(windowIndex, privacy: .public) trace_count=\(summary.traceCount, privacy: .public) model_audio_ms=1120.0 first_chunk_to_window_ms=\(firstText, privacy: .public) last_chunk_to_window_ms=\(lastText, privacy: .public) last_vad_to_window_ms=\(lastVADText, privacy: .public) inference_ms=\(inferenceText, privacy: .public) emitted_tokens=\(emittedTokenCount, privacy: .public) emitted_text=\(emittedText, privacy: .public)"
        )
    }

    static func logLatencyEngine(
        chunkSequence: Int,
        transcriberMilliseconds: Double,
        locatorMilliseconds: Double?,
        totalMilliseconds: Double,
        event: RecitationEvent?
    ) {
        let transcriberText = String(format: "%.1f", transcriberMilliseconds)
        let locatorText = AudioChunkLatencyTrace.format(milliseconds: locatorMilliseconds)
        let totalText = String(format: "%.1f", totalMilliseconds)
        let eventTypeText = event?.type.rawValue ?? "waiting"
        let reasonText = event?.reason ?? "none"
        logger.notice(
            "coreml_asr_latency_engine chunk_sequence=\(chunkSequence, privacy: .public) transcriber_ms=\(transcriberText, privacy: .public) locator_ms=\(locatorText, privacy: .public) total_ms=\(totalText, privacy: .public) event_type=\(eventTypeText, privacy: .public) reason=\(reasonText, privacy: .public)"
        )
    }

    static func logLatencyUIEvent(
        event: RecitationEvent,
        reducerMilliseconds: Double,
        stateChanged: Bool
    ) {
        let reducerText = String(format: "%.1f", reducerMilliseconds)
        logger.notice(
            "coreml_asr_latency_ui_event chunk_sequence=\(event.chunkSequence ?? -1, privacy: .public) event_type=\(event.type.rawValue, privacy: .public) reason=\(event.reason ?? "none", privacy: .public) reducer_ms=\(reducerText, privacy: .public) state_changed=\(stateChanged, privacy: .public)"
        )
    }

    static func logLocalQuranEvent(_ event: RecitationEvent) {
        let confidenceText = String(format: "%.4f", event.confidence)
        logger.notice(
            "coreml_asr_locator_event type=\(event.type.rawValue, privacy: .public) reason=\(event.reason ?? "none", privacy: .public) ayah_ref=\(event.ayahRef ?? "none", privacy: .public) start_ref=\(event.startRef ?? "none", privacy: .public) next_expected_ref=\(event.nextExpectedRef ?? "none", privacy: .public) consumed_words=\(event.consumedWords, privacy: .public) chunk_sequence=\(event.chunkSequence ?? -1, privacy: .public) confidence=\(confidenceText, privacy: .public)"
        )
    }
}

enum CoreMLFastConformerStreamResetReason: String, Equatable, Sendable {
    case speechBoundary = "speech_boundary"
    case blankStreak = "blank_streak"
}

struct CoreMLFastConformerAudioWindowMetrics: Equatable, Sendable {
    static let defaultNearSilenceThreshold: Float = 0.005

    let sampleCount: Int
    let rmsAmplitude: Double
    let peakAmplitude: Double
    let nearSilenceRatio: Double
    let voiceActivityObservationCount: Int
    let voiceActivitySpeechChunkCount: Int
    let voiceActivityLatestEvent: VoiceActivityEvent?
    let voiceActivityMeanProbability: Double?

    init(
        samples: [Float],
        voiceActivity: [VoiceActivityPayload],
        nearSilenceThreshold: Float = Self.defaultNearSilenceThreshold
    ) {
        sampleCount = samples.count
        if samples.isEmpty {
            rmsAmplitude = 0
            peakAmplitude = 0
            nearSilenceRatio = 0
        } else {
            var squaredSum = 0.0
            var peak = 0.0
            var nearSilenceCount = 0
            for sample in samples {
                let amplitude = Double(abs(sample))
                squaredSum += amplitude * amplitude
                peak = max(peak, amplitude)
                if amplitude < Double(nearSilenceThreshold) {
                    nearSilenceCount += 1
                }
            }
            rmsAmplitude = sqrt(squaredSum / Double(samples.count))
            peakAmplitude = peak
            nearSilenceRatio = Double(nearSilenceCount) / Double(samples.count)
        }

        voiceActivityObservationCount = voiceActivity.count
        voiceActivitySpeechChunkCount = voiceActivity.filter(\.isSpeechActive).count
        voiceActivityLatestEvent = voiceActivity.reversed().compactMap(\.event).first
        if voiceActivity.isEmpty {
            voiceActivityMeanProbability = nil
        } else {
            let probabilitySum = voiceActivity.reduce(0.0) { $0 + $1.probability }
            voiceActivityMeanProbability = probabilitySum / Double(voiceActivity.count)
        }
    }
}

struct CoreMLFastConformerWindowLatencySummary: Equatable, Sendable {
    let firstChunkToWindowMilliseconds: Double?
    let lastChunkToWindowMilliseconds: Double?
    let lastVADToWindowMilliseconds: Double?
    let traceCount: Int

    init(
        traces: [AudioChunkLatencyTrace],
        windowReadyAtNanoseconds: UInt64
    ) {
        let orderedTraces = traces.sorted {
            $0.receivedAtNanoseconds < $1.receivedAtNanoseconds
        }
        traceCount = orderedTraces.count
        firstChunkToWindowMilliseconds = AudioChunkLatencyTrace.milliseconds(
            from: orderedTraces.first?.receivedAtNanoseconds,
            to: windowReadyAtNanoseconds
        )
        lastChunkToWindowMilliseconds = AudioChunkLatencyTrace.milliseconds(
            from: orderedTraces.last?.receivedAtNanoseconds,
            to: windowReadyAtNanoseconds
        )
        lastVADToWindowMilliseconds = AudioChunkLatencyTrace.milliseconds(
            from: orderedTraces.last?.voiceActivityFinishedAtNanoseconds,
            to: windowReadyAtNanoseconds
        )
    }
}

struct CoreMLFastConformerStreamResetPolicy: Equatable, Sendable {
    static let activeSpeechMinimumRMS = 0.012
    static let activeSpeechMinimumVADSpeechChunks = 4
    static let activeSpeechMinimumVADProbability = 0.70
    static let blankStreakThreshold = 3

    private(set) var activeSpeechBlankStreak = 0
    private(set) var lastResetBlankStreak = 0
    private var pendingSpeechBoundaryReset = false
    private var hasEmittedTranscript = false

    mutating func reset() {
        activeSpeechBlankStreak = 0
        lastResetBlankStreak = 0
        pendingSpeechBoundaryReset = false
        hasEmittedTranscript = false
    }

    mutating func resetReasonBeforePrediction(
        metrics: CoreMLFastConformerAudioWindowMetrics
    ) -> CoreMLFastConformerStreamResetReason? {
        lastResetBlankStreak = 0
        if metrics.voiceActivityLatestEvent == .speechEnd {
            pendingSpeechBoundaryReset = true
            return nil
        }
        guard pendingSpeechBoundaryReset,
              Self.isActiveSpeech(metrics) else {
            return nil
        }
        pendingSpeechBoundaryReset = false
        activeSpeechBlankStreak = 0
        return .speechBoundary
    }

    mutating func resetReasonAfterPrediction(
        metrics: CoreMLFastConformerAudioWindowMetrics,
        emittedTokenCount: Int,
        transcript: String
    ) -> CoreMLFastConformerStreamResetReason? {
        lastResetBlankStreak = 0
        if metrics.voiceActivityLatestEvent == .speechEnd {
            pendingSpeechBoundaryReset = true
            activeSpeechBlankStreak = 0
            return nil
        }

        let hasTranscriptText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasTranscriptText {
            hasEmittedTranscript = true
        }

        if emittedTokenCount > 0 || hasTranscriptText {
            activeSpeechBlankStreak = 0
            return nil
        }

        guard hasEmittedTranscript else {
            activeSpeechBlankStreak = 0
            return nil
        }

        guard Self.isActiveSpeech(metrics) else {
            activeSpeechBlankStreak = 0
            return nil
        }

        activeSpeechBlankStreak += 1
        guard activeSpeechBlankStreak >= Self.blankStreakThreshold else {
            return nil
        }

        lastResetBlankStreak = activeSpeechBlankStreak
        activeSpeechBlankStreak = 0
        return .blankStreak
    }

    private static func isActiveSpeech(_ metrics: CoreMLFastConformerAudioWindowMetrics) -> Bool {
        guard metrics.rmsAmplitude >= activeSpeechMinimumRMS else {
            return false
        }
        if metrics.voiceActivitySpeechChunkCount >= activeSpeechMinimumVADSpeechChunks {
            return true
        }
        if let meanProbability = metrics.voiceActivityMeanProbability,
           meanProbability >= activeSpeechMinimumVADProbability {
            return true
        }
        return false
    }
}

public final class RoutingBackendSocketClient: BackendSocketing {
    private let remote: BackendSocketing
    private let coreML: BackendSocketing
    private var active: BackendSocketing?

    public init(
        remote: BackendSocketing,
        coreML: BackendSocketing
    ) {
        self.remote = remote
        self.coreML = coreML
    }

    public convenience init(coreML: BackendSocketing) {
        self.init(
            remote: BackendWebSocketClient(),
            coreML: coreML
        )
    }

    public func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        disconnect()
        let useCoreML = Self.isCoreMLURL(url)
        let target = useCoreML ? coreML : remote
        active = target
        try await target.connect(
            url: url,
            authorizationToken: useCoreML ? nil : authorizationToken,
            onEvent: onEvent
        )
    }

    public func send(_ payload: AudioChunkPayload) async throws {
        try await active?.send(payload)
    }

    public func disconnect() {
        active?.disconnect()
        active = nil
    }

    private static func isCoreMLURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "coreml"
    }
}

public final class CoreMLFastConformerSocketClient: BackendSocketing {
    private let engine: CoreMLFastConformerEngine
    private var onEvent: (@Sendable (RecitationEvent) -> Void)?

    public init(bundle: Bundle = .main) {
        engine = CoreMLFastConformerEngine(resourceLocation: .bundle(bundle))
    }

    public init(modelDirectoryURL: URL) {
        engine = CoreMLFastConformerEngine(resourceLocation: .modelDirectory(modelDirectoryURL))
    }

    public func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        self.onEvent = onEvent
        CoreMLFastConformerDiagnostics.logConnect(url: url)
        try await engine.start(url: url)
    }

    public func send(_ payload: AudioChunkPayload) async throws {
        guard let onEvent else { return }
        let event = try await engine.process(payload)
        onEvent(event)
    }

    public func disconnect() {
        onEvent = nil
        CoreMLFastConformerDiagnostics.logDisconnect()
        Task {
            await engine.reset()
        }
    }
}

enum CoreMLFastConformerResourceLocation: Sendable {
    case bundle(Bundle)
    case modelDirectory(URL)
}

actor CoreMLFastConformerEngine {
    private let resourceLocation: CoreMLFastConformerResourceLocation
    private var transcriber: CoreMLFastConformerTranscriber?
    private var localSession = CoreMLLocalQuranSession()

    init(resourceLocation: CoreMLFastConformerResourceLocation) {
        self.resourceLocation = resourceLocation
    }

    func start(url: URL) async throws {
        if transcriber == nil {
            transcriber = try makeTranscriber()
        }
        transcriber?.reset()
        localSession = try makeLocalSession(scope: Self.scopeSelection(from: url))
    }

    func reset() {
        transcriber?.reset()
        localSession.reset()
    }

    func process(_ payload: AudioChunkPayload) throws -> RecitationEvent {
        guard let transcriber else {
            throw CoreMLFastConformerError.modelNotLoaded
        }

        let processStart = Date()
        let transcriberStart = Date()
        let result = try transcriber.accept(
            pcm: payload.pcm,
            sampleRateHz: payload.sampleRateHz,
            chunkSequence: payload.sequenceNumber,
            voiceActivity: payload.voiceActivity,
            latencyTrace: payload.latencyTrace
        )
        let transcriberMilliseconds = Date().timeIntervalSince(transcriberStart) * 1000.0

        guard let result else {
            CoreMLFastConformerDiagnostics.logLatencyEngine(
                chunkSequence: payload.sequenceNumber,
                transcriberMilliseconds: transcriberMilliseconds,
                locatorMilliseconds: nil,
                totalMilliseconds: Date().timeIntervalSince(processStart) * 1000.0,
                event: nil
            )
            return RecitationEvent.coreMLWaiting(chunkSequence: payload.sequenceNumber)
        }

        let locatorStart = Date()
        let event = localSession.event(
            transcript: result.transcript,
            confidence: result.confidence,
            chunkSequence: payload.sequenceNumber
        )
        let locatorMilliseconds = Date().timeIntervalSince(locatorStart) * 1000.0
        CoreMLFastConformerDiagnostics.logLatencyEngine(
            chunkSequence: payload.sequenceNumber,
            transcriberMilliseconds: transcriberMilliseconds,
            locatorMilliseconds: locatorMilliseconds,
            totalMilliseconds: Date().timeIntervalSince(processStart) * 1000.0,
            event: event
        )
        CoreMLFastConformerDiagnostics.logLocalQuranEvent(event)
        return event
    }

    private static func scopeSelection(from url: URL) -> RecitationScopeSelection {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scopeValue = components.queryItems?.first(where: { $0.name == "scope" })?.value,
              let surahID = Int(scopeValue) else {
            return .autoDetect
        }
        return .selectedSurah(id: surahID)
    }

    private func makeTranscriber() throws -> CoreMLFastConformerTranscriber {
        switch resourceLocation {
        case .bundle(let bundle):
            return try CoreMLFastConformerTranscriber(bundle: bundle)
        case .modelDirectory(let directoryURL):
            return try CoreMLFastConformerTranscriber(modelDirectoryURL: directoryURL)
        }
    }

    private func makeLocalSession(scope: RecitationScopeSelection) throws -> CoreMLLocalQuranSession {
        try CoreMLLocalQuranSession(
            scope: scope,
            corpus: CoreMLLocalQuranCorpus.preferredAyahs(for: resourceLocation)
        )
    }
}

public struct CoreMLFastConformerDecodeResult: Equatable, Sendable {
    public let text: String
    public let emittedTokenIDs: [Int]
}

public struct CoreMLFastConformerCTCDecoder: Sendable {
    public static let blankTokenID = 1024

    private let tokens: [Int: String]

    public init(tokens: [Int: String]) {
        self.tokens = tokens
    }

    public func decode(
        tokenIDs: [Int],
        previousTokenID: Int? = nil,
        trimsWhitespace: Bool = true
    ) -> CoreMLFastConformerDecodeResult {
        var lastTokenID = previousTokenID
        var emittedTokenIDs: [Int] = []
        var pieces: [String] = []

        for tokenID in tokenIDs {
            defer { lastTokenID = tokenID }
            guard tokenID != Self.blankTokenID else { continue }
            guard tokenID != lastTokenID else { continue }
            guard let piece = tokens[tokenID], piece != "<unk>" else { continue }
            emittedTokenIDs.append(tokenID)
            pieces.append(piece)
        }

        return CoreMLFastConformerDecodeResult(
            text: Self.decodeSentencePieces(pieces, trimsWhitespace: trimsWhitespace),
            emittedTokenIDs: emittedTokenIDs
        )
    }

    public static func tokens(fromTokensFile url: URL) throws -> [Int: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var tokens: [Int: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.lastIndex(of: " ") else { continue }
            let piece = String(line[..<separator])
            let idText = line[line.index(after: separator)...]
            guard let id = Int(idText) else { continue }
            tokens[id] = piece
        }
        return tokens
    }

    private static func decodeSentencePieces(_ pieces: [String], trimsWhitespace: Bool) -> String {
        let text = pieces.joined()
            .replacingOccurrences(of: "▁", with: " ")
        guard trimsWhitespace else { return text }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum CoreMLFastConformerError: LocalizedError {
    case missingModelResource
    case missingTokensResource
    case modelNotLoaded
    case invalidAudio
    case invalidModelOutput

    public var errorDescription: String? {
        switch self {
        case .missingModelResource:
            return "CoreML FastConformer model is missing from the app bundle."
        case .missingTokensResource:
            return "CoreML FastConformer tokens.txt is missing from the app bundle."
        case .modelNotLoaded:
            return "CoreML FastConformer model is not loaded."
        case .invalidAudio:
            return "CoreML FastConformer received invalid audio."
        case .invalidModelOutput:
            return "CoreML FastConformer returned an unexpected output shape."
        }
    }
}

public enum CoreMLFastConformerFixtureError: LocalizedError {
    case invalidWAV(String)
    case unsupportedWAV(String)
    case noWAVFiles(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidWAV(let reason):
            return "Invalid WAV file: \(reason)"
        case .unsupportedWAV(let reason):
            return "Unsupported WAV file: \(reason)"
        case .noWAVFiles(let url):
            return "No .wav files found in \(url.path)."
        }
    }
}

public struct CoreMLFastConformerFixtureAudio: Equatable, Sendable {
    public let sampleRateHz: Int
    public let sourceChannelCount: Int
    public let frameCount: Int
    public let pcm16Mono: Data

    public static func loadWAV(from url: URL) throws -> CoreMLFastConformerFixtureAudio {
        let data = try Data(contentsOf: url)
        guard data.count >= 12,
              data.asciiString(in: 0..<4) == "RIFF",
              data.asciiString(in: 8..<12) == "WAVE" else {
            throw CoreMLFastConformerFixtureError.invalidWAV("missing RIFF/WAVE header")
        }

        var format: WAVFormat?
        var pcmData: Data?
        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = data.asciiString(in: offset..<(offset + 4))
            let chunkSize = Int(data.uint32LE(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd <= data.count else {
                throw CoreMLFastConformerFixtureError.invalidWAV("chunk \(chunkID) exceeds file size")
            }

            if chunkID == "fmt " {
                format = try WAVFormat(data: data.subdata(in: chunkStart..<chunkEnd))
            } else if chunkID == "data" {
                pcmData = data.subdata(in: chunkStart..<chunkEnd)
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard let format else {
            throw CoreMLFastConformerFixtureError.invalidWAV("missing fmt chunk")
        }
        guard let pcmData else {
            throw CoreMLFastConformerFixtureError.invalidWAV("missing data chunk")
        }
        guard format.audioFormat == 1 else {
            throw CoreMLFastConformerFixtureError.unsupportedWAV("only PCM format is supported")
        }
        guard format.bitsPerSample == 16 else {
            throw CoreMLFastConformerFixtureError.unsupportedWAV("only 16-bit PCM is supported")
        }
        guard format.channelCount > 0 else {
            throw CoreMLFastConformerFixtureError.invalidWAV("channel count must be positive")
        }

        let bytesPerFrame = Int(format.channelCount) * 2
        guard pcmData.count % bytesPerFrame == 0 else {
            throw CoreMLFastConformerFixtureError.invalidWAV("PCM data is not aligned to whole frames")
        }

        let frameCount = pcmData.count / bytesPerFrame
        var mono = Data()
        mono.reserveCapacity(frameCount * 2)
        for frameIndex in 0..<frameCount {
            var sum = 0
            let frameOffset = frameIndex * bytesPerFrame
            for channelIndex in 0..<Int(format.channelCount) {
                let sampleOffset = frameOffset + channelIndex * 2
                sum += Int(pcmData.int16LE(at: sampleOffset))
            }
            let averaged = max(
                Int(Int16.min),
                min(Int(Int16.max), sum / Int(format.channelCount))
            )
            mono.appendInt16LE(Int16(averaged))
        }

        return CoreMLFastConformerFixtureAudio(
            sampleRateHz: Int(format.sampleRateHz),
            sourceChannelCount: Int(format.channelCount),
            frameCount: frameCount,
            pcm16Mono: mono
        )
    }

    var resampled16KPCM16: Data {
        guard sampleRateHz != 16_000 else { return pcm16Mono }
        let samples = CoreMLFastConformerTranscriber.samples(
            fromPCM16: pcm16Mono,
            sourceSampleRateHz: sampleRateHz
        )
        return Self.pcm16(fromNormalizedSamples: samples)
    }

    private static func pcm16(fromNormalizedSamples samples: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * 2)
        for sample in samples {
            let scaled = Int(round(max(-1.0, min(1.0, sample)) * 32767.0))
            data.appendInt16LE(Int16(max(Int(Int16.min), min(Int(Int16.max), scaled))))
        }
        return data
    }
}

public struct CoreMLFastConformerFixtureWindow: Codable, Equatable, Sendable {
    public let windowIndex: Int
    public let chunkSequence: Int
    public let inferenceMilliseconds: Double
    public let confidence: Double
    public let emittedTokenCount: Int
    public let transcript: String
    public let cumulativeTranscript: String

    public init(
        windowIndex: Int,
        chunkSequence: Int,
        inferenceMilliseconds: Double,
        confidence: Double,
        emittedTokenCount: Int,
        transcript: String,
        cumulativeTranscript: String
    ) {
        self.windowIndex = windowIndex
        self.chunkSequence = chunkSequence
        self.inferenceMilliseconds = inferenceMilliseconds
        self.confidence = confidence
        self.emittedTokenCount = emittedTokenCount
        self.transcript = transcript
        self.cumulativeTranscript = cumulativeTranscript
    }
}

public struct CoreMLFastConformerFixtureReport: Codable, Equatable, Sendable {
    public let audioPath: String
    public let sampleRateHz: Int
    public let sourceChannelCount: Int
    public let frameCount: Int
    public let windows: [CoreMLFastConformerFixtureWindow]
    public let expectation: CoreMLFastConformerFixtureExpectation?
    public let score: CoreMLFastConformerFixtureScore?

    public init(
        audioPath: String,
        sampleRateHz: Int,
        sourceChannelCount: Int,
        frameCount: Int,
        windows: [CoreMLFastConformerFixtureWindow],
        expectation: CoreMLFastConformerFixtureExpectation? = nil,
        score: CoreMLFastConformerFixtureScore? = nil
    ) {
        self.audioPath = audioPath
        self.sampleRateHz = sampleRateHz
        self.sourceChannelCount = sourceChannelCount
        self.frameCount = frameCount
        self.windows = windows
        self.expectation = expectation
        self.score = score
    }

    public var durationSeconds: Double {
        guard sampleRateHz > 0 else { return 0 }
        return Double(frameCount) / Double(sampleRateHz)
    }

    public var finalTranscript: String {
        windows.last(where: { !$0.cumulativeTranscript.isEmpty })?.cumulativeTranscript ?? ""
    }

    public var averageInferenceMilliseconds: Double {
        guard !windows.isEmpty else { return 0 }
        return windows.reduce(0.0) { $0 + $1.inferenceMilliseconds } / Double(windows.count)
    }

    public func scored(with expectation: CoreMLFastConformerFixtureExpectation) -> CoreMLFastConformerFixtureReport {
        CoreMLFastConformerFixtureReport(
            audioPath: audioPath,
            sampleRateHz: sampleRateHz,
            sourceChannelCount: sourceChannelCount,
            frameCount: frameCount,
            windows: windows,
            expectation: expectation,
            score: CoreMLFastConformerFixtureScore.score(
                expectedText: expectation.expectedText,
                actualText: finalTranscript
            )
        )
    }

    public func textSummary() -> String {
        var lines = [
            "audio: \(audioPath)",
            "sample_rate_hz: \(sampleRateHz)",
            "source_channels: \(sourceChannelCount)",
            "frame_count: \(frameCount)",
            "duration_seconds: \(String(format: "%.3f", durationSeconds))",
            "window_count: \(windows.count)",
            "avg_inference_ms: \(String(format: "%.1f", averageInferenceMilliseconds))",
            "final_transcript: \(finalTranscript)",
        ]
        if let expectation {
            lines.append("ayah_ref: \(expectation.ayahRef)")
            lines.append("expected_text: \(expectation.expectedText)")
        }
        if let score {
            lines.append("normalized_expected: \(score.normalizedExpectedText)")
            lines.append("normalized_actual: \(score.normalizedActualText)")
            lines.append("normalized_word_score: \(String(format: "%.3f", score.wordMatchScore))")
            lines.append("word_error_rate: \(String(format: "%.3f", score.wordErrorRate))")
            lines.append("character_error_rate: \(String(format: "%.3f", score.characterErrorRate))")
            lines.append("missing_words: \(score.missingWords.isEmpty ? "none" : score.missingWords.joined(separator: " "))")
            lines.append("extra_words: \(score.extraWords.isEmpty ? "none" : score.extraWords.joined(separator: " "))")
            let substitutionText = score.substitutions
                .map { "\($0.expectedWord)->\($0.actualWord)" }
                .joined(separator: ", ")
            lines.append("substitutions: \(substitutionText.isEmpty ? "none" : substitutionText)")
        }
        for window in windows {
            let inferenceText = String(format: "%.1f", window.inferenceMilliseconds)
            let confidenceText = String(format: "%.4f", window.confidence)
            lines.append(
                "window=\(window.windowIndex) chunk_sequence=\(window.chunkSequence) inference_ms=\(inferenceText) confidence=\(confidenceText) emitted_tokens=\(window.emittedTokenCount) transcript=\"\(window.transcript)\" cumulative=\"\(window.cumulativeTranscript)\""
            )
        }
        return lines.joined(separator: "\n")
    }
}

struct CoreMLFastConformerTranscript: Equatable, Sendable {
    let transcript: String
    let confidence: Double
    let emittedTokenIDs: [Int]
}

private struct WAVFormat {
    let audioFormat: UInt16
    let channelCount: UInt16
    let sampleRateHz: UInt32
    let bitsPerSample: UInt16

    init(data: Data) throws {
        guard data.count >= 16 else {
            throw CoreMLFastConformerFixtureError.invalidWAV("fmt chunk is too short")
        }
        audioFormat = data.uint16LE(at: 0)
        channelCount = data.uint16LE(at: 2)
        sampleRateHz = data.uint32LE(at: 4)
        bitsPerSample = data.uint16LE(at: 14)
    }
}

public struct CoreMLFastConformerFixtureRunner {
    public static let defaultLiveChunkSamples = 2_560
    public static let modelChunkSamples = 112 * 160

    private let modelDirectoryURL: URL
    private let liveChunkSamples: Int
    private let padsFinalWindow: Bool

    public init(
        modelDirectoryURL: URL,
        liveChunkSamples: Int = Self.defaultLiveChunkSamples,
        padsFinalWindow: Bool = true
    ) {
        self.modelDirectoryURL = modelDirectoryURL
        self.liveChunkSamples = liveChunkSamples
        self.padsFinalWindow = padsFinalWindow
    }

    public func run(audioURL: URL) throws -> CoreMLFastConformerFixtureReport {
        guard liveChunkSamples > 0 else {
            throw CoreMLFastConformerError.invalidAudio
        }

        let audio = try CoreMLFastConformerFixtureAudio.loadWAV(from: audioURL)
        let original16KPCM = audio.resampled16KPCM16
        let processingPCM = padsFinalWindow
            ? Self.paddedToModelWindow(pcm16: original16KPCM)
            : original16KPCM
        var windows: [CoreMLFastConformerFixtureWindow] = []
        let transcriber = try CoreMLFastConformerTranscriber(
            modelDirectoryURL: modelDirectoryURL,
            windowReporter: { windows.append($0) }
        )
        transcriber.reset()

        let chunkByteCount = liveChunkSamples * 2
        var offset = 0
        var sequence = 0
        while offset < processingPCM.count {
            let end = min(offset + chunkByteCount, processingPCM.count)
            _ = try transcriber.accept(
                pcm: processingPCM.subdata(in: offset..<end),
                sampleRateHz: 16_000,
                chunkSequence: sequence
            )
            offset = end
            sequence += 1
        }

        return CoreMLFastConformerFixtureReport(
            audioPath: audioURL.path,
            sampleRateHz: 16_000,
            sourceChannelCount: audio.sourceChannelCount,
            frameCount: original16KPCM.count / 2,
            windows: windows
        )
    }

    public func run(audioDirectoryURL: URL) throws -> [CoreMLFastConformerFixtureReport] {
        let urls = try FileManager.default
            .contentsOfDirectory(
                at: audioDirectoryURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else {
            throw CoreMLFastConformerFixtureError.noWAVFiles(audioDirectoryURL)
        }
        return try urls.map { try run(audioURL: $0) }
    }

    private static func paddedToModelWindow(pcm16: Data) -> Data {
        let sampleCount = pcm16.count / 2
        let remainder = sampleCount % modelChunkSamples
        guard remainder > 0 else { return pcm16 }
        var data = pcm16
        data.append(Data(repeating: 0, count: (modelChunkSamples - remainder) * 2))
        return data
    }
}

struct CoreMLLocalQuranSession: Sendable {
    private static let minimumRecognizedWords = 2
    private static let tolerantMatchThreshold = 0.78
    private static let anchorWordSimilarityThreshold = 0.74
    private static let minimumAnchorMatches = 5
    private static let minimumAnchorCoverage = 0.30
    private static let minimumAnchorWordCharacters = 3
    private static let sequenceAnchorMinimumMatches = 3
    private static let sequenceAnchorMinimumCoveredAyahs = 2
    private static let sequenceAnchorMaximumLookaheadAyahs = 8
    private static let prefixLockMinimumF1 = 0.72
    private static let prefixLockMinimumActualCoverage = 0.78
    private static let prefixLockMinimumExpectedCoverage = 0.60
    private static let prefixLockMinimumStartAyahCoverage = 0.45
    private static let prefixLockMaximumLookbackAyahs = 3
    private static let prefixLockMinimumCharacters = 16
    private static let prefixLockMaximumCharacters = 180
    private static let prefixLockMaximumStartAyahs = 4
    private static let initialLockMaximumFuzzyWords = 12
    private static let initialLockMaximumFuzzyCharacters = 96
    private static let initialLockMaximumFuzzyAyahs = 4
    private static let initialLockMaximumSequenceWords = 18
    private static let initialLockMaximumAnchorWords = 24
    private static let initialLockMaximumAnchorAyahs = 4
    private static let postLockMaximumRecognizedWords = 18
    private static let forwardProgressLookaheadAyahs = 2
    private static let forwardProgressMaximumRecentWords = 5
    private static let forwardProgressMinimumF1 = 0.60
    private static let forwardProgressMinimumExpectedCoverage = 0.70
    private static let orderedAnchorProgressMaximumWords = 6
    private static let orderedAnchorProgressMinimumStrongMatches = 2
    private static let shortAyahSuffixMaximumExpectedWords = 4
    private static let shortAyahSuffixMinimumWords = 2
    private static let shortAyahSuffixMaximumRecentWords = 4
    private static let shortAyahSuffixMinimumMeanScore = 0.70
    private static let openingBasmalaWords = ["بسم", "الله", "الرحمن", "الرحيم"]
    private static let openingBasmalaMinimumWords = 2
    private static let openingBasmalaMinimumMeanScore = 0.72
    private static let openingSparseContentMinimumStrongMatches = 3
    private static let openingSparseContentMinimumMeanScore = 0.74

    private let ayahs: [CoreMLLocalQuranAyah]
    private let allowsAnchorLock: Bool
    private var currentAyahIndex: Int?
    private var nextExpectedRef: CoreMLLocalQuranWordRef?
    private var lastRecognizedWords: [String] = []

    init(
        scope: RecitationScopeSelection = .autoDetect,
        corpus: [CoreMLLocalQuranAyah] = CoreMLLocalQuranCorpus.mvpAyahs
    ) {
        switch scope {
        case .autoDetect:
            ayahs = corpus
            allowsAnchorLock = false
        case .selectedSurah(let id):
            ayahs = corpus.filter { $0.surahID == id }
            allowsAnchorLock = true
        }
    }

    mutating func reset() {
        currentAyahIndex = nil
        nextExpectedRef = nil
        lastRecognizedWords = []
    }

    mutating func event(
        transcript: String,
        confidence: Double,
        chunkSequence: Int
    ) -> RecitationEvent {
        let normalizedTranscript = CoreMLArabicTextNormalizer.normalize(transcript)
        let recognizedWords = Self.words(in: normalizedTranscript)
        defer {
            if !recognizedWords.isEmpty {
                lastRecognizedWords = recognizedWords
            }
        }

        if currentAyahIndex != nil,
           let match = orderedProgressMatch(
            normalizedTranscript: normalizedTranscript,
            recognizedWords: recognizedWords
           ) {
            currentAyahIndex = match.ayahIndex
            nextExpectedRef = nextExpectedRefValue(after: match)
                .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
            return RecitationEvent.coreMLLocated(
                type: .progress,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                match: match,
                nextExpectedRef: nextExpectedRef?.rawValue
            )
        }

        if currentAyahIndex != nil,
           let match = orderedAnchorProgressMatch(recognizedWords: recognizedWords) {
            currentAyahIndex = match.ayahIndex
            nextExpectedRef = nextExpectedRefValue(after: match)
                .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
            return RecitationEvent.coreMLLocated(
                type: .progress,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                match: match,
                nextExpectedRef: nextExpectedRef?.rawValue
            )
        }

        if currentAyahIndex != nil,
           let match = shortAyahSuffixProgressMatch(recognizedWords: recognizedWords) {
            currentAyahIndex = match.ayahIndex
            nextExpectedRef = nextExpectedRefValue(after: match)
                .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
            return RecitationEvent.coreMLLocated(
                type: .progress,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                match: match,
                nextExpectedRef: nextExpectedRef?.rawValue
            )
        }

        if currentAyahIndex != nil,
           let match = orderedForwardProgressMatch(recognizedWords: recognizedWords) {
            currentAyahIndex = match.ayahIndex
            nextExpectedRef = nextExpectedRefValue(after: match)
                .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
            return RecitationEvent.coreMLLocated(
                type: .progress,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                match: match,
                nextExpectedRef: nextExpectedRef?.rawValue
            )
        }

        if currentAyahIndex != nil {
            return RecitationEvent.coreMLTranscript(
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                reason: recognizedWords.isEmpty ? "coreml_local_no_words" : "coreml_local_ordered_no_match",
                candidateRefs: orderedCandidateRefs()
            )
        }

        guard recognizedWords.count >= Self.minimumRecognizedWords else {
            return RecitationEvent.coreMLTranscript(
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                reason: recognizedWords.isEmpty ? "coreml_local_no_words" : "coreml_local_insufficient_context"
            )
        }

        let hasOpeningPreface = Self.containsOpeningPreface(recognizedWords)
        if currentAyahIndex == nil,
           allowsAnchorLock,
           let match = selectedSurahOpeningPrefaceMatch(recognizedWords: recognizedWords) {
            currentAyahIndex = match.ayahIndex
            nextExpectedRef = nextExpectedRefValue(after: match)
                .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
            return RecitationEvent.coreMLLocated(
                type: .locked,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                match: match,
                nextExpectedRef: nextExpectedRef?.rawValue
            )
        }

        if currentAyahIndex == nil,
           allowsAnchorLock,
           hasOpeningPreface,
           firstAyahHasOpeningBasmala() {
            return RecitationEvent.coreMLTranscript(
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                reason: "coreml_local_opening_preface_no_match",
                candidateRefs: ayahs.first.map { [$0.ref] } ?? []
            )
        }

        if currentAyahIndex == nil,
           allowsAnchorLock {
            return selectedSurahInitialEvent(
                normalizedTranscript: normalizedTranscript,
                recognizedWords: recognizedWords,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence
            )
        }

        let matches = ayahs.enumerated().compactMap { index, ayah in
            Self.match(
                ayah: ayah,
                ayahIndex: index,
                normalizedTranscript: normalizedTranscript,
                recognizedWords: recognizedWords,
                minimumStartWordIndex: nil
            )
        }
        let forwardMatches = matches
            .filter { $0.score >= Self.tolerantMatchThreshold || $0.reason == "coreml_local_span_match" }
            .filter { match in
                guard let currentAyahIndex else { return true }
                return match.ayahIndex >= currentAyahIndex
            }
        let viableMatches = forwardMatches.sorted { lhs, rhs in
            guard currentAyahIndex != nil else {
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.ayahIndex < rhs.ayahIndex
            }

            if lhs.ayahIndex != rhs.ayahIndex {
                return lhs.ayahIndex > rhs.ayahIndex
            }
            return lhs.score > rhs.score
        }

        if let match = viableMatches.first {
            let eventType: RecitationEventType = currentAyahIndex == nil ? .locked : .progress
            currentAyahIndex = match.ayahIndex
            nextExpectedRef = nextExpectedRefValue(after: match)
                .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
            return RecitationEvent.coreMLLocated(
                type: eventType,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                match: match,
                nextExpectedRef: nextExpectedRef?.rawValue
            )
        }

        if currentAyahIndex == nil,
           allowsAnchorLock,
           let match = selectedSurahSequenceAnchorMatch(recognizedWords: recognizedWords) {
            currentAyahIndex = match.ayahIndex
            nextExpectedRef = nextExpectedRefValue(after: match)
                .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
            return RecitationEvent.coreMLLocated(
                type: .locked,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                match: match,
                nextExpectedRef: nextExpectedRef?.rawValue
            )
        }

        if currentAyahIndex == nil,
           allowsAnchorLock,
           let match = selectedSurahAnchorMatch(recognizedWords: recognizedWords) {
            currentAyahIndex = match.ayahIndex
            nextExpectedRef = nextExpectedRefValue(after: match)
                .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
            return RecitationEvent.coreMLLocated(
                type: .locked,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                match: match,
                nextExpectedRef: nextExpectedRef?.rawValue
            )
        }

        return RecitationEvent.coreMLTranscript(
            transcript: transcript,
            confidence: confidence,
            chunkSequence: chunkSequence,
            reason: "coreml_local_no_match",
            candidateRefs: matches.prefix(3).map(\.ayah.ref)
        )
    }

    private mutating func selectedSurahInitialEvent(
        normalizedTranscript: String,
        recognizedWords: [String],
        transcript: String,
        confidence: Double,
        chunkSequence: Int
    ) -> RecitationEvent {
        if let prefixMatch = selectedSurahPrefixSpanMatch(normalizedTranscript: normalizedTranscript) {
            return lockInitialSelectedSurahMatch(
                prefixMatch,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence
            )
        }

        let spanMatches = selectedSurahSpanMatches(recognizedWords: recognizedWords)
        if let match = spanMatches.first {
            return lockInitialSelectedSurahMatch(
                match,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence
            )
        }

        if let match = selectedSurahTolerantInitialMatch(
            normalizedTranscript: normalizedTranscript,
            recognizedWords: recognizedWords
        ) {
            return lockInitialSelectedSurahMatch(
                match,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence
            )
        }

        if let match = selectedSurahSequenceAnchorInitialMatch(recognizedWords: recognizedWords) {
            return lockInitialSelectedSurahMatch(
                match,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence
            )
        }

        if let match = selectedSurahAnchorInitialMatch(recognizedWords: recognizedWords) {
            return lockInitialSelectedSurahMatch(
                match,
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence
            )
        }

        return RecitationEvent.coreMLTranscript(
            transcript: transcript,
            confidence: confidence,
            chunkSequence: chunkSequence,
            reason: "coreml_local_no_match",
            candidateRefs: spanMatches.prefix(3).map(\.ayah.ref)
        )
    }

    private mutating func lockInitialSelectedSurahMatch(
        _ match: CoreMLLocalQuranMatch,
        transcript: String,
        confidence: Double,
        chunkSequence: Int
    ) -> RecitationEvent {
        currentAyahIndex = match.ayahIndex
        nextExpectedRef = nextExpectedRefValue(after: match)
            .flatMap(CoreMLLocalQuranWordRef.init(rawValue:))
        return RecitationEvent.coreMLLocated(
            type: .locked,
            transcript: transcript,
            confidence: confidence,
            chunkSequence: chunkSequence,
            match: match,
            nextExpectedRef: nextExpectedRef?.rawValue
        )
    }

    private func firstAyahHasOpeningBasmala() -> Bool {
        guard let firstAyah = ayahs.first else { return false }
        return Self.openingBasmalaPrefixLength(
            in: Self.words(in: firstAyah.normalizedText)
        ) >= Self.openingBasmalaMinimumWords
    }

    private func selectedSurahOpeningPrefaceMatch(recognizedWords: [String]) -> CoreMLLocalQuranMatch? {
        guard allowsAnchorLock,
              let firstAyahIndex = ayahs.indices.first,
              !recognizedWords.isEmpty else {
            return nil
        }

        let ayah = ayahs[firstAyahIndex]
        let expectedWords = Self.words(in: ayah.normalizedText)
        guard !expectedWords.isEmpty else { return nil }

        let basmalaPrefixLength = Self.openingBasmalaPrefixLength(in: expectedWords)
        guard basmalaPrefixLength >= Self.openingBasmalaMinimumWords else { return nil }

        let openingWords = Self.wordsAfterOpeningPreface(recognizedWords)
        guard !openingWords.isEmpty else { return nil }

        var matches: [CoreMLLocalQuranMatch] = []

        if let match = Self.openingBasmalaMatch(
            ayah: ayah,
            ayahIndex: firstAyahIndex,
            expectedBasmalaWords: Array(expectedWords.prefix(basmalaPrefixLength)),
            recognizedWords: openingWords
        ) {
            matches.append(match)
        }

        let contentStartIndex = basmalaPrefixLength
        if contentStartIndex < expectedWords.count,
           let match = Self.openingContentMatch(
            ayah: ayah,
            ayahIndex: firstAyahIndex,
            recognizedWords: openingWords,
            contentStartIndex: contentStartIndex
           ) {
            matches.append(match)
        }

        if contentStartIndex < expectedWords.count,
           let match = Self.openingSparseContentMatch(
            ayah: ayah,
            ayahIndex: firstAyahIndex,
            recognizedWords: openingWords,
            contentStartIndex: contentStartIndex
           ) {
            matches.append(match)
        }

        return matches.sorted(by: Self.isBetterOpeningMatch).first
    }

    private static func containsOpeningPreface(_ recognizedWords: [String]) -> Bool {
        let prefixText = recognizedWords
            .prefix(8)
            .joined()
        return prefixText.contains("اعوذ")
            && (prefixText.contains("شيطان") || prefixText.contains("الشيطان"))
    }

    private static func wordsAfterOpeningPreface(_ recognizedWords: [String]) -> [String] {
        guard containsOpeningPreface(recognizedWords) else {
            return recognizedWords
        }
        guard let prefaceEndIndex = recognizedWords.firstIndex(where: { word in
            word.contains("رجيم")
        }) else {
            return []
        }
        let nextIndex = recognizedWords.index(after: prefaceEndIndex)
        guard nextIndex < recognizedWords.endIndex else {
            return []
        }
        return Array(recognizedWords[nextIndex...])
    }

    private static func openingBasmalaPrefixLength(in expectedWords: [String]) -> Int {
        let maximumCount = min(openingBasmalaWords.count, expectedWords.count)
        guard maximumCount > 0 else { return 0 }

        var matchedCount = 0
        for index in 0..<maximumCount {
            guard expectedWords[index] == openingBasmalaWords[index] else { break }
            matchedCount += 1
        }
        return matchedCount
    }

    private static func openingBasmalaMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        expectedBasmalaWords: [String],
        recognizedWords: [String]
    ) -> CoreMLLocalQuranMatch? {
        guard expectedBasmalaWords.count >= openingBasmalaMinimumWords,
              recognizedWords.count >= openingBasmalaMinimumWords else {
            return nil
        }

        var best: CoreMLLocalQuranMatch?
        for expectedStartIndex in expectedBasmalaWords.indices {
            let maximumLength = min(
                expectedBasmalaWords.count - expectedStartIndex,
                recognizedWords.count
            )
            guard maximumLength >= openingBasmalaMinimumWords else { continue }

            for length in openingBasmalaMinimumWords...maximumLength {
                for actualStartIndex in 0...(recognizedWords.count - length) {
                    let expectedSlice = Array(expectedBasmalaWords[expectedStartIndex..<(expectedStartIndex + length)])
                    let actualSlice = Array(recognizedWords[actualStartIndex..<(actualStartIndex + length)])
                    let scores = zip(expectedSlice, actualSlice).map {
                        openingWordScore(expected: $0.0, actual: $0.1)
                    }
                    let meanScore = scores.reduce(0.0, +) / Double(scores.count)
                    guard scores.allSatisfy({ $0 >= openingBasmalaMinimumMeanScore }),
                          meanScore >= openingBasmalaMinimumMeanScore else {
                        continue
                    }

                    let match = CoreMLLocalQuranMatch(
                        ayah: ayah,
                        ayahIndex: ayahIndex,
                        score: meanScore,
                        reason: "coreml_local_opening_basmala_lock",
                        startWordIndex: expectedStartIndex + 1,
                        matchedWords: length
                    )
                    if let currentBest = best {
                        if isBetterOpeningMatch(lhs: match, rhs: currentBest) {
                            best = match
                        }
                    } else {
                        best = match
                    }
                }
            }
        }
        return best
    }

    private static func openingContentMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String],
        contentStartIndex: Int
    ) -> CoreMLLocalQuranMatch? {
        guard recognizedWords.count >= orderedAnchorProgressMinimumStrongMatches else {
            return nil
        }

        return orderedAnchorProgressMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            recognizedWords: recognizedWords,
            minimumStartWordIndex: contentStartIndex + 1
        )?.with(reason: "coreml_local_opening_content_lock")
    }

    private static func openingSparseContentMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String],
        contentStartIndex: Int
    ) -> CoreMLLocalQuranMatch? {
        let expectedWords = words(in: ayah.normalizedText)
        guard expectedWords.indices.contains(contentStartIndex),
              !recognizedWords.isEmpty else {
            return nil
        }

        var matches: [(expectedIndex: Int, score: Double)] = []
        var expectedCursor = contentStartIndex
        for actualWord in recognizedWords {
            guard compactCharacters(actualWord).count >= 2,
                  let match = firstOpeningSparseContentMatch(
                    actualWord: actualWord,
                    expectedWords: expectedWords,
                    lowerBound: expectedCursor
                  ) else {
                continue
            }
            matches.append(match)
            expectedCursor = match.expectedIndex + 1
            guard expectedCursor < expectedWords.count else { break }
        }

        guard matches.count >= openingSparseContentMinimumStrongMatches,
              let first = matches.first,
              let last = matches.last else {
            return nil
        }

        let meanScore = matches.reduce(0.0) { $0 + $1.score } / Double(matches.count)
        guard meanScore >= openingSparseContentMinimumMeanScore else {
            return nil
        }

        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            score: meanScore,
            reason: "coreml_local_opening_sparse_content_lock",
            startWordIndex: first.expectedIndex + 1,
            matchedWords: last.expectedIndex - first.expectedIndex + 1
        )
    }

    private static func firstOpeningSparseContentMatch(
        actualWord: String,
        expectedWords: [String],
        lowerBound: Int
    ) -> (expectedIndex: Int, score: Double)? {
        guard lowerBound < expectedWords.count else { return nil }
        for expectedIndex in lowerBound..<expectedWords.count {
            let score = openingWordScore(expected: expectedWords[expectedIndex], actual: actualWord)
            if score >= anchorWordSimilarityThreshold {
                return (expectedIndex, score)
            }
        }
        return nil
    }

    private static func openingWordScore(expected: String, actual: String) -> Double {
        let normalScore = anchorWordSimilarity(expected: expected, actual: actual)
        if normalScore >= anchorWordSimilarityThreshold {
            return normalScore
        }

        let expectedCharacters = compactCharacters(expected)
        let actualCharacters = compactCharacters(actual)
        guard actualCharacters.count >= 2,
              expectedCharacters.starts(with: actualCharacters) else {
            return normalScore
        }

        let prefixCoverage = Double(actualCharacters.count) / Double(expectedCharacters.count)
        guard prefixCoverage >= 0.50 else { return normalScore }
        return max(normalScore, 0.68 + (0.08 * prefixCoverage))
    }

    private static func isBetterOpeningMatch(
        lhs: CoreMLLocalQuranMatch,
        rhs: CoreMLLocalQuranMatch
    ) -> Bool {
        let lhsProgressWordIndex = lhs.startWordIndex + lhs.matchedWords
        let rhsProgressWordIndex = rhs.startWordIndex + rhs.matchedWords
        if lhsProgressWordIndex != rhsProgressWordIndex {
            return lhsProgressWordIndex > rhsProgressWordIndex
        }
        if lhs.matchedWords != rhs.matchedWords {
            return lhs.matchedWords > rhs.matchedWords
        }
        if lhs.startWordIndex != rhs.startWordIndex {
            return lhs.startWordIndex < rhs.startWordIndex
        }
        return lhs.score > rhs.score
    }

    private func selectedSurahAnchorMatch(
        recognizedWords: [String],
        maximumAyahCount: Int? = nil
    ) -> CoreMLLocalQuranMatch? {
        let ayahPairs = maximumAyahCount
            .map { selectedSurahInitialAyahPairs(maximumCount: $0) }
            ?? ayahs.enumerated().map { ($0.offset, $0.element) }
        return ayahPairs
            .compactMap { index, ayah in
                Self.anchorMatch(
                    ayah: ayah,
                    ayahIndex: index,
                    recognizedWords: recognizedWords,
                    minimumStartWordIndex: nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.matchedWords != rhs.matchedWords {
                    return lhs.matchedWords > rhs.matchedWords
                }
                if lhs.startWordIndex != rhs.startWordIndex {
                    return lhs.startWordIndex < rhs.startWordIndex
                }
                return lhs.ayahIndex < rhs.ayahIndex
            }
            .first
    }

    private func selectedSurahSequenceAnchorMatch(
        recognizedWords: [String],
        maximumAyahCount: Int? = nil
    ) -> CoreMLLocalQuranMatch? {
        let searchCount = min(maximumAyahCount ?? ayahs.count, ayahs.count)
        guard searchCount > 1 else { return nil }
        let searchIndices = Array(ayahs.indices.prefix(searchCount))
        guard let lastAyahIndex = searchIndices.last else { return nil }
        let candidates = searchIndices.flatMap { startIndex -> [CoreMLLocalQuranSequenceAnchorCandidate] in
            let maximumEndIndex = min(
                ayahs.index(
                    startIndex,
                    offsetBy: Self.sequenceAnchorMaximumLookaheadAyahs,
                    limitedBy: lastAyahIndex
                ) ?? lastAyahIndex,
                lastAyahIndex
            )
            guard startIndex < maximumEndIndex else { return [] }
            return (startIndex...maximumEndIndex).compactMap { endIndex in
                Self.sequenceAnchorCandidate(
                    ayahs: ayahs,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    recognizedWords: recognizedWords
                )
            }
        }

        guard let candidate = candidates.sorted(by: Self.isBetterSequenceAnchorCandidate).first else {
            return nil
        }
        let ayah = ayahs[candidate.startAyahIndex]
        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: candidate.startAyahIndex,
            score: candidate.score,
            reason: "coreml_local_sequence_anchor_lock",
            startWordIndex: 1,
            matchedWords: Self.words(in: ayah.normalizedText).count
        )
    }

    private func selectedSurahSpanMatches(recognizedWords: [String]) -> [CoreMLLocalQuranMatch] {
        guard !recognizedWords.isEmpty else { return [] }
        return ayahs.enumerated()
            .compactMap { index, ayah in
                Self.spanMatch(
                    ayah: ayah,
                    ayahIndex: index,
                    recognizedWords: recognizedWords,
                    minimumStartWordIndex: nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.ayahIndex != rhs.ayahIndex {
                    return lhs.ayahIndex < rhs.ayahIndex
                }
                if lhs.matchedWords != rhs.matchedWords {
                    return lhs.matchedWords > rhs.matchedWords
                }
                return lhs.startWordIndex < rhs.startWordIndex
            }
    }

    private func selectedSurahTolerantInitialMatch(
        normalizedTranscript: String,
        recognizedWords: [String]
    ) -> CoreMLLocalQuranMatch? {
        guard recognizedWords.count <= Self.initialLockMaximumFuzzyWords,
              Self.compactCharacters(normalizedTranscript).count <= Self.initialLockMaximumFuzzyCharacters else {
            return nil
        }

        return selectedSurahInitialAyahPairs(maximumCount: Self.initialLockMaximumFuzzyAyahs)
            .compactMap { index, ayah -> CoreMLLocalQuranMatch? in
                let match = Self.match(
                    ayah: ayah,
                    ayahIndex: index,
                    normalizedTranscript: normalizedTranscript,
                    recognizedWords: recognizedWords,
                    minimumStartWordIndex: nil
                )
                guard match.score >= Self.tolerantMatchThreshold || match.reason == "coreml_local_span_match" else {
                    return nil
                }
                return match
            }
            .sorted(by: Self.isBetterInitialSelectedSurahMatch)
            .first
    }

    private func selectedSurahSequenceAnchorInitialMatch(recognizedWords: [String]) -> CoreMLLocalQuranMatch? {
        selectedSurahInitialWordWindows(
            recognizedWords,
            maximumCount: Self.initialLockMaximumSequenceWords
        )
        .compactMap {
            selectedSurahSequenceAnchorMatch(
                recognizedWords: $0,
                maximumAyahCount: Self.initialLockMaximumAnchorAyahs
            )
        }
        .sorted(by: Self.isBetterInitialSelectedSurahMatch)
        .first
    }

    private func selectedSurahAnchorInitialMatch(recognizedWords: [String]) -> CoreMLLocalQuranMatch? {
        selectedSurahInitialWordWindows(
            recognizedWords,
            maximumCount: Self.initialLockMaximumAnchorWords
        )
        .compactMap {
            selectedSurahAnchorMatch(
                recognizedWords: $0,
                maximumAyahCount: Self.initialLockMaximumAnchorAyahs
            )
        }
        .sorted(by: Self.isBetterInitialSelectedSurahMatch)
        .first
    }

    private func selectedSurahInitialAyahPairs(maximumCount: Int) -> [(Int, CoreMLLocalQuranAyah)] {
        let limitedCount = min(maximumCount, ayahs.count)
        guard limitedCount > 0 else { return [] }
        return ayahs.indices.prefix(limitedCount).map { ($0, ayahs[$0]) }
    }

    private func selectedSurahInitialWordWindows(
        _ recognizedWords: [String],
        maximumCount: Int
    ) -> [[String]] {
        guard !recognizedWords.isEmpty else { return [] }
        guard recognizedWords.count > maximumCount else { return [recognizedWords] }

        let prefix = Array(recognizedWords.prefix(maximumCount))
        let suffix = Array(recognizedWords.suffix(maximumCount))
        return prefix == suffix ? [prefix] : [prefix, suffix]
    }

    private func selectedSurahPrefixSpanMatch(normalizedTranscript: String) -> CoreMLLocalQuranMatch? {
        guard ayahs.count > 1 else { return nil }
        let actualCharacters = Self.compactCharacters(normalizedTranscript)
        guard actualCharacters.count >= Self.prefixLockMinimumCharacters,
              actualCharacters.count <= Self.prefixLockMaximumCharacters else {
            return nil
        }

        let lastAyahIndex = ayahs.index(before: ayahs.endIndex)
        let maximumStartIndex = min(
            ayahs.startIndex + Self.prefixLockMaximumStartAyahs,
            ayahs.endIndex
        )
        let candidates = (ayahs.startIndex..<maximumStartIndex).flatMap { startIndex -> [CoreMLLocalQuranPrefixCandidate] in
            let maximumEndIndex = min(
                ayahs.index(
                    startIndex,
                    offsetBy: Self.prefixLockMaximumLookbackAyahs,
                    limitedBy: lastAyahIndex
                ) ?? lastAyahIndex,
                lastAyahIndex
            )
            guard startIndex < maximumEndIndex else { return [] }
            return (ayahs.index(after: startIndex)...maximumEndIndex).compactMap { endIndex in
                Self.prefixCandidate(
                    ayahs: ayahs,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    actualCharacters: actualCharacters
                )
            }
        }

        guard let candidate = candidates.sorted(by: Self.isBetterPrefixCandidate).first else {
            return nil
        }
        let ayah = ayahs[candidate.startAyahIndex]
        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: candidate.startAyahIndex,
            score: candidate.score,
            reason: "coreml_local_prefix_lock",
            startWordIndex: 1,
            matchedWords: Self.words(in: ayah.normalizedText).count
        )
    }

    private static func prefixCandidate(
        ayahs: [CoreMLLocalQuranAyah],
        startIndex: Int,
        endIndex: Int,
        actualCharacters: [Character]
    ) -> CoreMLLocalQuranPrefixCandidate? {
        guard ayahs.indices.contains(startIndex),
              ayahs.indices.contains(endIndex),
              startIndex < endIndex,
              !actualCharacters.isEmpty else {
            return nil
        }

        let expectedText = ayahs[startIndex...endIndex]
            .map(\.normalizedText)
            .joined(separator: " ")
        let expectedCharacters = compactCharacters(expectedText)
        guard !expectedCharacters.isEmpty else { return nil }

        let spanLCS = longestCommonSubsequenceLength(expectedCharacters, actualCharacters)
        let actualCoverage = Double(spanLCS) / Double(actualCharacters.count)
        let expectedCoverage = Double(spanLCS) / Double(expectedCharacters.count)
        let f1 = (2.0 * Double(spanLCS)) / Double(expectedCharacters.count + actualCharacters.count)

        let startAyahCharacters = compactCharacters(ayahs[startIndex].normalizedText)
        let startAyahLCS = longestCommonSubsequenceLength(startAyahCharacters, actualCharacters)
        let startAyahCoverage = startAyahCharacters.isEmpty
            ? 0.0
            : Double(startAyahLCS) / Double(startAyahCharacters.count)

        guard f1 >= prefixLockMinimumF1,
              actualCoverage >= prefixLockMinimumActualCoverage,
              expectedCoverage >= prefixLockMinimumExpectedCoverage,
              startAyahCoverage >= prefixLockMinimumStartAyahCoverage else {
            return nil
        }

        return CoreMLLocalQuranPrefixCandidate(
            startAyahIndex: startIndex,
            endAyahIndex: endIndex,
            score: f1,
            actualCoverage: actualCoverage,
            expectedCoverage: expectedCoverage,
            startAyahCoverage: startAyahCoverage
        )
    }

    private static func isBetterPrefixCandidate(
        lhs: CoreMLLocalQuranPrefixCandidate,
        rhs: CoreMLLocalQuranPrefixCandidate
    ) -> Bool {
        if lhs.startAyahIndex != rhs.startAyahIndex {
            return lhs.startAyahIndex < rhs.startAyahIndex
        }
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.startAyahCoverage != rhs.startAyahCoverage {
            return lhs.startAyahCoverage > rhs.startAyahCoverage
        }
        if lhs.expectedCoverage != rhs.expectedCoverage {
            return lhs.expectedCoverage > rhs.expectedCoverage
        }
        return lhs.actualCoverage > rhs.actualCoverage
    }

    private static func isBetterInitialSelectedSurahMatch(
        lhs: CoreMLLocalQuranMatch,
        rhs: CoreMLLocalQuranMatch
    ) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.matchedWords != rhs.matchedWords {
            return lhs.matchedWords > rhs.matchedWords
        }
        if lhs.startWordIndex != rhs.startWordIndex {
            return lhs.startWordIndex < rhs.startWordIndex
        }
        return lhs.ayahIndex < rhs.ayahIndex
    }

    private static func sequenceAnchorCandidate(
        ayahs: [CoreMLLocalQuranAyah],
        startIndex: Int,
        endIndex: Int,
        recognizedWords: [String]
    ) -> CoreMLLocalQuranSequenceAnchorCandidate? {
        guard ayahs.indices.contains(startIndex),
              ayahs.indices.contains(endIndex),
              startIndex < endIndex,
              !recognizedWords.isEmpty else {
            return nil
        }
        let expectedAnchors = (startIndex...endIndex).flatMap { ayahIndex in
            words(in: ayahs[ayahIndex].normalizedText).map { (ayahIndex: ayahIndex, word: $0) }
        }
        let eligibleAnchorCount = expectedAnchors.filter { isAnchorWord($0.word) }.count
        guard eligibleAnchorCount >= sequenceAnchorMinimumMatches else { return nil }

        let candidates = expectedAnchors.indices.flatMap { expectedStartIndex in
            recognizedWords.indices.compactMap { actualStartIndex in
                sequenceAnchorCandidate(
                    expectedAnchors: expectedAnchors,
                    recognizedWords: recognizedWords,
                    expectedStartIndex: expectedStartIndex,
                    actualStartIndex: actualStartIndex,
                    eligibleAnchorCount: eligibleAnchorCount
                )
            }
        }
        return candidates.sorted(by: isBetterSequenceAnchorCandidate).first
    }

    private static func sequenceAnchorCandidate(
        expectedAnchors: [(ayahIndex: Int, word: String)],
        recognizedWords: [String],
        expectedStartIndex: Int,
        actualStartIndex: Int,
        eligibleAnchorCount: Int
    ) -> CoreMLLocalQuranSequenceAnchorCandidate? {
        guard expectedAnchors.indices.contains(expectedStartIndex),
              recognizedWords.indices.contains(actualStartIndex),
              isAnchorWord(expectedAnchors[expectedStartIndex].word) else {
            return nil
        }
        let firstScore = anchorWordSimilarity(
            expected: expectedAnchors[expectedStartIndex].word,
            actual: recognizedWords[actualStartIndex]
        )
        guard firstScore >= anchorWordSimilarityThreshold else { return nil }

        var matches: [(expectedIndex: Int, score: Double)] = [
            (expectedStartIndex, firstScore),
        ]
        var expectedCursor = expectedStartIndex + 1
        if actualStartIndex + 1 < recognizedWords.count {
            for actualWord in recognizedWords[(actualStartIndex + 1)...] {
                guard isAnchorWord(actualWord),
                      expectedCursor < expectedAnchors.count,
                      let match = firstSequenceAnchorMatch(
                        actualWord: actualWord,
                        expectedAnchors: expectedAnchors,
                        lowerBound: expectedCursor
                      ) else {
                    continue
                }
                matches.append((match.expectedIndex, match.score))
                expectedCursor = match.expectedIndex + 1
            }
        }

        return makeSequenceAnchorCandidate(
            matches: matches,
            expectedAnchors: expectedAnchors,
            eligibleAnchorCount: eligibleAnchorCount
        )
    }

    private static func firstSequenceAnchorMatch(
        actualWord: String,
        expectedAnchors: [(ayahIndex: Int, word: String)],
        lowerBound: Int
    ) -> (expectedIndex: Int, score: Double)? {
        guard lowerBound < expectedAnchors.count else { return nil }
        for expectedIndex in lowerBound..<expectedAnchors.count {
            let expected = expectedAnchors[expectedIndex]
            guard isAnchorWord(expected.word) else { continue }
            let score = anchorWordSimilarity(expected: expected.word, actual: actualWord)
            if score >= anchorWordSimilarityThreshold {
                return (expectedIndex, score)
            }
        }
        return nil
    }

    private static func makeSequenceAnchorCandidate(
        matches: [(expectedIndex: Int, score: Double)],
        expectedAnchors: [(ayahIndex: Int, word: String)],
        eligibleAnchorCount: Int
    ) -> CoreMLLocalQuranSequenceAnchorCandidate? {
        guard matches.count >= sequenceAnchorMinimumMatches,
              let first = matches.first,
              let last = matches.last,
              expectedAnchors.indices.contains(first.expectedIndex),
              expectedAnchors.indices.contains(last.expectedIndex),
              eligibleAnchorCount > 0 else {
            return nil
        }
        let coveredAyahs = Set(matches.map { expectedAnchors[$0.expectedIndex].ayahIndex })
        guard coveredAyahs.count >= sequenceAnchorMinimumCoveredAyahs else { return nil }

        let meanSimilarity = matches.reduce(0.0) { $0 + $1.score } / Double(matches.count)
        let coverage = Double(matches.count) / Double(eligibleAnchorCount)
        let countScore = min(Double(matches.count) / Double(sequenceAnchorMinimumMatches * 2), 1.0)
        let ayahCoverage = min(Double(coveredAyahs.count) / Double(sequenceAnchorMinimumCoveredAyahs + 1), 1.0)
        let score = (countScore * 0.35) + (meanSimilarity * 0.35) + (coverage * 0.15) + (ayahCoverage * 0.15)
        return CoreMLLocalQuranSequenceAnchorCandidate(
            startAyahIndex: expectedAnchors[first.expectedIndex].ayahIndex,
            endAyahIndex: expectedAnchors[last.expectedIndex].ayahIndex,
            anchorCount: matches.count,
            coveredAyahCount: coveredAyahs.count,
            coverage: coverage,
            score: score
        )
    }

    private static func isBetterSequenceAnchorCandidate(
        lhs: CoreMLLocalQuranSequenceAnchorCandidate,
        rhs: CoreMLLocalQuranSequenceAnchorCandidate
    ) -> Bool {
        if lhs.anchorCount != rhs.anchorCount {
            return lhs.anchorCount > rhs.anchorCount
        }
        if lhs.coveredAyahCount != rhs.coveredAyahCount {
            return lhs.coveredAyahCount > rhs.coveredAyahCount
        }
        if lhs.startAyahIndex != rhs.startAyahIndex {
            return lhs.startAyahIndex < rhs.startAyahIndex
        }
        if lhs.endAyahIndex != rhs.endAyahIndex {
            return lhs.endAyahIndex > rhs.endAyahIndex
        }
        if lhs.coverage != rhs.coverage {
            return lhs.coverage > rhs.coverage
        }
        return lhs.score > rhs.score
    }

    private static func anchorMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String],
        minimumStartWordIndex: Int?
    ) -> CoreMLLocalQuranMatch? {
        let expectedWords = words(in: ayah.normalizedText)
        let minimumStartIndex = max((minimumStartWordIndex ?? 1) - 1, 0)
        let searchableExpectedWords = expectedWords.indices.contains(minimumStartIndex)
            ? Array(expectedWords[minimumStartIndex...])
            : []
        let anchorExpectedIndices = searchableExpectedWords.indices
            .filter { isAnchorWord(searchableExpectedWords[$0]) }
        guard anchorExpectedIndices.count >= minimumAnchorMatches else { return nil }

        let candidates = anchorExpectedIndices.flatMap { expectedStartIndex in
            recognizedWords.indices.compactMap { actualStartIndex in
                anchorCandidate(
                    expectedWords: searchableExpectedWords,
                    recognizedWords: recognizedWords,
                    expectedStartIndex: expectedStartIndex,
                    actualStartIndex: actualStartIndex,
                    eligibleAnchorCount: anchorExpectedIndices.count
                )
            }
        }
        guard let candidate = candidates.sorted(by: isBetterAnchorCandidate).first else {
            return nil
        }
        guard candidate.anchorCount >= minimumAnchorMatches,
              candidate.coverage >= minimumAnchorCoverage else {
            return nil
        }

        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            score: candidate.score,
            reason: "coreml_local_anchor_lock",
            startWordIndex: minimumStartIndex + candidate.startWordIndex + 1,
            matchedWords: candidate.matchedWords
        )
    }

    private static func anchorCandidate(
        expectedWords: [String],
        recognizedWords: [String],
        expectedStartIndex: Int,
        actualStartIndex: Int,
        eligibleAnchorCount: Int
    ) -> CoreMLLocalQuranAnchorCandidate? {
        guard expectedWords.indices.contains(expectedStartIndex),
              recognizedWords.indices.contains(actualStartIndex),
              isAnchorWord(expectedWords[expectedStartIndex]) else {
            return nil
        }
        let firstScore = anchorWordSimilarity(
            expected: expectedWords[expectedStartIndex],
            actual: recognizedWords[actualStartIndex]
        )
        guard firstScore >= anchorWordSimilarityThreshold else { return nil }

        var matches: [(expectedIndex: Int, score: Double)] = [
            (expectedStartIndex, firstScore),
        ]
        var expectedCursor = expectedStartIndex + 1
        guard actualStartIndex + 1 < recognizedWords.count else {
            return makeAnchorCandidate(matches: matches, eligibleAnchorCount: eligibleAnchorCount)
        }

        for actualWord in recognizedWords[(actualStartIndex + 1)...] {
            guard isAnchorWord(actualWord),
                  expectedCursor < expectedWords.count,
                  let match = firstAnchorWordMatch(
                    actualWord: actualWord,
                    expectedWords: expectedWords,
                    lowerBound: expectedCursor
                  ) else {
                continue
            }
            matches.append((match.expectedIndex, match.score))
            expectedCursor = match.expectedIndex + 1
        }

        return makeAnchorCandidate(matches: matches, eligibleAnchorCount: eligibleAnchorCount)
    }

    private static func makeAnchorCandidate(
        matches: [(expectedIndex: Int, score: Double)],
        eligibleAnchorCount: Int
    ) -> CoreMLLocalQuranAnchorCandidate? {
        guard let first = matches.first,
              let last = matches.last,
              eligibleAnchorCount > 0 else {
            return nil
        }
        let meanSimilarity = matches.reduce(0.0) { $0 + $1.score } / Double(matches.count)
        let coverage = Double(matches.count) / Double(eligibleAnchorCount)
        let spanWordCount = last.expectedIndex - first.expectedIndex + 1
        let countScore = min(Double(matches.count) / Double(minimumAnchorMatches * 2), 1.0)
        let score = (countScore * 0.45) + (meanSimilarity * 0.35) + (coverage * 0.20)
        return CoreMLLocalQuranAnchorCandidate(
            startWordIndex: first.expectedIndex,
            matchedWords: spanWordCount,
            anchorCount: matches.count,
            coverage: coverage,
            score: score
        )
    }

    private static func firstAnchorWordMatch(
        actualWord: String,
        expectedWords: [String],
        lowerBound: Int
    ) -> (expectedIndex: Int, score: Double)? {
        guard lowerBound < expectedWords.count else { return nil }
        for expectedIndex in lowerBound..<expectedWords.count {
            let expectedWord = expectedWords[expectedIndex]
            guard isAnchorWord(expectedWord) else { continue }
            let score = anchorWordSimilarity(expected: expectedWord, actual: actualWord)
            if score >= anchorWordSimilarityThreshold {
                return (expectedIndex, score)
            }
        }
        return nil
    }

    private static func isBetterAnchorCandidate(
        lhs: CoreMLLocalQuranAnchorCandidate,
        rhs: CoreMLLocalQuranAnchorCandidate
    ) -> Bool {
        if lhs.anchorCount != rhs.anchorCount {
            return lhs.anchorCount > rhs.anchorCount
        }
        if lhs.coverage != rhs.coverage {
            return lhs.coverage > rhs.coverage
        }
        if lhs.matchedWords != rhs.matchedWords {
            return lhs.matchedWords > rhs.matchedWords
        }
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.startWordIndex < rhs.startWordIndex
    }

    private static func isAnchorWord(_ word: String) -> Bool {
        compactCharacters(word).count >= minimumAnchorWordCharacters
    }

    private static func anchorWordSimilarity(expected: String, actual: String) -> Double {
        let expectedCharacters = compactCharacters(expected)
        let actualCharacters = compactCharacters(actual)
        guard !expectedCharacters.isEmpty, !actualCharacters.isEmpty else { return 0 }
        let expectedVariants = anchorWordSimilarityVariants(expectedCharacters)
        let actualVariants = anchorWordSimilarityVariants(actualCharacters)
        var best = 0.0
        for expectedVariant in expectedVariants {
            for actualVariant in actualVariants {
                best = max(best, similarity(expected: expectedVariant, actual: actualVariant))
            }
        }
        return best
    }

    private static func anchorWordSimilarityVariants(_ characters: [Character]) -> [[Character]] {
        var variants = [characters]
        if let first = characters.first,
           (first == "و" || first == "ف"),
           characters.count > minimumAnchorWordCharacters {
            variants.append(Array(characters.dropFirst()))
        }
        return variants
    }

    private func orderedProgressMatch(
        normalizedTranscript: String,
        recognizedWords: [String]
    ) -> CoreMLLocalQuranMatch? {
        guard let nextExpectedRef else { return nil }
        let progressWords = boundedPostLockWords(from: recognizedWords)
        guard !progressWords.isEmpty else { return nil }

        let progressTranscript = progressWords.joined(separator: " ")
        let allowedIndices = orderedAyahIndices(from: nextExpectedRef)
        let matches = allowedIndices.compactMap { ayahIndex -> CoreMLLocalQuranMatch? in
            let ayah = ayahs[ayahIndex]
            let minimumStartWordIndex = ayah.ref == nextExpectedRef.ayahRef
                ? nextExpectedRef.wordIndex
                : 1
            let match = Self.match(
                ayah: ayah,
                ayahIndex: ayahIndex,
                normalizedTranscript: progressTranscript.isEmpty ? normalizedTranscript : progressTranscript,
                recognizedWords: progressWords,
                minimumStartWordIndex: minimumStartWordIndex
            )
            guard match.score >= Self.tolerantMatchThreshold || match.reason == "coreml_local_span_match" else {
                return nil
            }
            return match.with(reason: "coreml_local_ordered_progress")
        }
        return matches
            .sorted { lhs, rhs in
                if lhs.ayahIndex != rhs.ayahIndex {
                    return lhs.ayahIndex < rhs.ayahIndex
                }
                if lhs.startWordIndex != rhs.startWordIndex {
                    return lhs.startWordIndex < rhs.startWordIndex
                }
                return lhs.score > rhs.score
            }
            .first
    }

    private func orderedAnchorProgressMatch(recognizedWords: [String]) -> CoreMLLocalQuranMatch? {
        guard let nextExpectedRef,
              allowsAnchorLock,
              !recognizedWords.isEmpty else {
            return nil
        }

        let candidateWords = boundedPostLockWords(from: recognizedWords)
        guard !candidateWords.isEmpty else { return nil }
        let allowedIndices = orderedAyahIndices(from: nextExpectedRef)
        let candidates = allowedIndices.compactMap { ayahIndex -> CoreMLLocalQuranMatch? in
            let ayah = ayahs[ayahIndex]
            let minimumStartWordIndex = ayah.ref == nextExpectedRef.ayahRef
                ? nextExpectedRef.wordIndex
                : 1
            return Self.orderedAnchorProgressMatch(
                ayah: ayah,
                ayahIndex: ayahIndex,
                recognizedWords: candidateWords,
                minimumStartWordIndex: minimumStartWordIndex
            )
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.ayahIndex != rhs.ayahIndex {
                    return lhs.ayahIndex < rhs.ayahIndex
                }
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.matchedWords != rhs.matchedWords {
                    return lhs.matchedWords > rhs.matchedWords
                }
                return lhs.startWordIndex < rhs.startWordIndex
            }
            .first
    }

    private func shortAyahSuffixProgressMatch(recognizedWords: [String]) -> CoreMLLocalQuranMatch? {
        guard let nextExpectedRef,
              allowsAnchorLock,
              !recognizedWords.isEmpty else {
            return nil
        }

        let candidateWords = recentPostLockWords(from: recognizedWords)
        guard !candidateWords.isEmpty else { return nil }
        let candidateIndices = orderedAyahIndices(from: nextExpectedRef)
        let candidates = candidateIndices.compactMap { ayahIndex -> CoreMLLocalQuranMatch? in
            let ayah = ayahs[ayahIndex]
            let minimumStartWordIndex = ayah.ref == nextExpectedRef.ayahRef
                ? nextExpectedRef.wordIndex
                : 1
            return Self.shortAyahSuffixProgressMatch(
                ayah: ayah,
                ayahIndex: ayahIndex,
                recognizedWords: candidateWords,
                minimumStartWordIndex: minimumStartWordIndex
            )
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.ayahIndex != rhs.ayahIndex {
                    return lhs.ayahIndex < rhs.ayahIndex
                }
                if lhs.matchedWords != rhs.matchedWords {
                    return lhs.matchedWords > rhs.matchedWords
                }
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.startWordIndex < rhs.startWordIndex
            }
            .first
    }

    private func orderedForwardProgressMatch(recognizedWords: [String]) -> CoreMLLocalQuranMatch? {
        guard let nextExpectedRef,
              allowsAnchorLock,
              !recognizedWords.isEmpty else {
            return nil
        }

        let candidateWords = boundedPostLockWords(from: recognizedWords)
        guard !candidateWords.isEmpty else { return nil }
        let candidateIndices = orderedForwardAyahIndices(from: nextExpectedRef)
        let candidates = candidateIndices.compactMap { ayahIndex -> CoreMLLocalQuranMatch? in
            let ayah = ayahs[ayahIndex]
            let minimumStartWordIndex = ayah.ref == nextExpectedRef.ayahRef
                ? nextExpectedRef.wordIndex
                : 1
            return Self.forwardProgressMatch(
                ayah: ayah,
                ayahIndex: ayahIndex,
                recognizedWords: candidateWords,
                minimumStartWordIndex: minimumStartWordIndex
            )
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.ayahIndex != rhs.ayahIndex {
                    return lhs.ayahIndex < rhs.ayahIndex
                }
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.startWordIndex < rhs.startWordIndex
            }
            .first
    }

    private static func orderedAnchorProgressMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String],
        minimumStartWordIndex: Int?
    ) -> CoreMLLocalQuranMatch? {
        let expectedWords = words(in: ayah.normalizedText)
        let minimumStartIndex = max((minimumStartWordIndex ?? 1) - 1, 0)
        let searchableExpectedWords = expectedWords.indices.contains(minimumStartIndex)
            ? Array(expectedWords[minimumStartIndex...])
            : []
        guard searchableExpectedWords.count >= orderedAnchorProgressMinimumStrongMatches,
              recognizedWords.count >= orderedAnchorProgressMinimumStrongMatches else {
            return nil
        }

        let candidates = searchableExpectedWords.indices.flatMap { expectedStartIndex in
            recognizedWords.indices.compactMap { actualStartIndex in
                orderedAnchorProgressCandidate(
                    expectedWords: searchableExpectedWords,
                    recognizedWords: recognizedWords,
                    expectedStartIndex: expectedStartIndex,
                    actualStartIndex: actualStartIndex
                )
            }
        }
        guard let candidate = candidates.sorted(by: isBetterOrderedAnchorProgressCandidate).first else {
            return nil
        }
        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            score: candidate.score,
            reason: "coreml_local_ordered_anchor_progress",
            startWordIndex: minimumStartIndex + candidate.startWordIndex + 1,
            matchedWords: candidate.matchedWords
        )
    }

    private static func orderedAnchorProgressCandidate(
        expectedWords: [String],
        recognizedWords: [String],
        expectedStartIndex: Int,
        actualStartIndex: Int
    ) -> CoreMLLocalQuranOrderedAnchorProgressCandidate? {
        var expectedCursor = expectedStartIndex
        var actualCursor = actualStartIndex
        var strongMatches = 0
        var matchedWords = 0
        var scoreTotal = 0.0

        while expectedCursor < expectedWords.count,
              actualCursor < recognizedWords.count,
              matchedWords < orderedAnchorProgressMaximumWords {
            let expectedWord = expectedWords[expectedCursor]
            let actualWord = recognizedWords[actualCursor]
            let score = anchorWordSimilarity(expected: expectedWord, actual: actualWord)
            if score >= anchorWordSimilarityThreshold {
                strongMatches += 1
                scoreTotal += score
            } else if actualCursor == recognizedWords.index(before: recognizedWords.endIndex),
                      strongMatches >= orderedAnchorProgressMinimumStrongMatches,
                      isTrailingPrefixMatch(expected: expectedWord, actual: actualWord) {
                scoreTotal += 0.60
            } else {
                break
            }

            expectedCursor += 1
            actualCursor += 1
            matchedWords += 1
        }

        guard strongMatches >= orderedAnchorProgressMinimumStrongMatches,
              matchedWords >= orderedAnchorProgressMinimumStrongMatches else {
            return nil
        }
        let meanScore = scoreTotal / Double(matchedWords)
        let strongCoverage = Double(strongMatches) / Double(matchedWords)
        return CoreMLLocalQuranOrderedAnchorProgressCandidate(
            startWordIndex: expectedStartIndex,
            matchedWords: matchedWords,
            strongMatches: strongMatches,
            score: (meanScore * 0.80) + (strongCoverage * 0.20)
        )
    }

    private static func isBetterOrderedAnchorProgressCandidate(
        lhs: CoreMLLocalQuranOrderedAnchorProgressCandidate,
        rhs: CoreMLLocalQuranOrderedAnchorProgressCandidate
    ) -> Bool {
        if lhs.strongMatches != rhs.strongMatches {
            return lhs.strongMatches > rhs.strongMatches
        }
        if lhs.matchedWords != rhs.matchedWords {
            return lhs.matchedWords > rhs.matchedWords
        }
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.startWordIndex < rhs.startWordIndex
    }

    private static func shortAyahSuffixProgressMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String],
        minimumStartWordIndex: Int?
    ) -> CoreMLLocalQuranMatch? {
        let expectedWords = words(in: ayah.normalizedText)
        let minimumStartIndex = max((minimumStartWordIndex ?? 1) - 1, 0)
        guard expectedWords.count <= shortAyahSuffixMaximumExpectedWords,
              expectedWords.count >= shortAyahSuffixMinimumWords,
              minimumStartIndex < expectedWords.count - 1 else {
            return nil
        }

        let maximumSuffixLength = min(
            shortAyahSuffixMaximumRecentWords,
            expectedWords.count - minimumStartIndex
        )
        var best: CoreMLLocalQuranMatch?
        for suffixLength in shortAyahSuffixMinimumWords...maximumSuffixLength {
            let expectedStartIndex = expectedWords.count - suffixLength
            guard expectedStartIndex >= minimumStartIndex,
                  expectedStartIndex > 0,
                  recognizedWords.count >= suffixLength else {
                continue
            }
            let expectedSuffix = Array(expectedWords[expectedStartIndex...])
            let actualSuffix = Array(recognizedWords.suffix(suffixLength))
            let scores = zip(expectedSuffix, actualSuffix).map {
                shortAyahSuffixWordScore(expected: $0.0, actual: $0.1)
            }
            let meanScore = scores.reduce(0.0, +) / Double(scores.count)
            guard meanScore >= shortAyahSuffixMinimumMeanScore else { continue }

            let match = CoreMLLocalQuranMatch(
                ayah: ayah,
                ayahIndex: ayahIndex,
                score: meanScore,
                reason: "coreml_local_short_ayah_suffix_progress",
                startWordIndex: expectedStartIndex + 1,
                matchedWords: suffixLength
            )
            if let currentBest = best {
                if isBetterShortAyahSuffixMatch(match, than: currentBest) {
                    best = match
                }
            } else {
                best = match
            }
        }
        return best
    }

    private static func shortAyahSuffixWordScore(expected: String, actual: String) -> Double {
        let normalScore = anchorWordSimilarity(expected: expected, actual: actual)
        if normalScore >= anchorWordSimilarityThreshold {
            return normalScore
        }

        let expectedCharacters = compactCharacters(expected)
        let actualCharacters = compactCharacters(actual)
        guard actualCharacters.count >= 2,
              expectedCharacters.starts(with: actualCharacters) else {
            return normalScore
        }

        let prefixCoverage = Double(actualCharacters.count) / Double(expectedCharacters.count)
        guard prefixCoverage >= 0.5 else { return normalScore }
        return max(normalScore, 0.70 + (0.08 * prefixCoverage))
    }

    private static func isBetterShortAyahSuffixMatch(
        _ candidate: CoreMLLocalQuranMatch,
        than other: CoreMLLocalQuranMatch
    ) -> Bool {
        if candidate.matchedWords != other.matchedWords {
            return candidate.matchedWords > other.matchedWords
        }
        if candidate.score != other.score {
            return candidate.score > other.score
        }
        return candidate.startWordIndex < other.startWordIndex
    }

    private static func isTrailingPrefixMatch(expected: String, actual: String) -> Bool {
        let expectedCharacters = compactCharacters(expected)
        let actualCharacters = compactCharacters(actual)
        guard !expectedCharacters.isEmpty, !actualCharacters.isEmpty else { return false }
        return expectedCharacters.starts(with: actualCharacters)
    }

    private static func forwardProgressMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String],
        minimumStartWordIndex: Int?
    ) -> CoreMLLocalQuranMatch? {
        let expectedWords = words(in: ayah.normalizedText)
        let minimumStartIndex = max((minimumStartWordIndex ?? 1) - 1, 0)
        let searchableExpectedWords = expectedWords.indices.contains(minimumStartIndex)
            ? Array(expectedWords[minimumStartIndex...])
            : []
        let expectedCharacters = compactCharacters(searchableExpectedWords.joined(separator: " "))
        guard !expectedCharacters.isEmpty else { return nil }

        let maximumWindowSize = min(forwardProgressMaximumRecentWords, recognizedWords.count)
        var best: CoreMLLocalQuranForwardCandidate?
        for windowSize in 1...maximumWindowSize {
            let recentWords = Array(recognizedWords.suffix(windowSize))
            let actualCharacters = compactCharacters(recentWords.joined(separator: " "))
            guard !actualCharacters.isEmpty else { continue }
            let lcs = longestCommonSubsequenceLength(expectedCharacters, actualCharacters)
            let expectedCoverage = Double(lcs) / Double(expectedCharacters.count)
            let f1 = (2.0 * Double(lcs)) / Double(expectedCharacters.count + actualCharacters.count)
            guard f1 >= forwardProgressMinimumF1,
                  expectedCoverage >= forwardProgressMinimumExpectedCoverage else {
                continue
            }
            let candidate = CoreMLLocalQuranForwardCandidate(
                score: f1,
                expectedCoverage: expectedCoverage,
                windowSize: windowSize
            )
            if let currentBest = best {
                if isBetterForwardCandidate(candidate, than: currentBest) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        guard let best else { return nil }
        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            score: best.score,
            reason: "coreml_local_ordered_forward_progress",
            startWordIndex: minimumStartIndex + 1,
            matchedWords: searchableExpectedWords.count
        )
    }

    private static func isBetterForwardCandidate(
        _ candidate: CoreMLLocalQuranForwardCandidate,
        than other: CoreMLLocalQuranForwardCandidate
    ) -> Bool {
        if candidate.score != other.score {
            return candidate.score > other.score
        }
        if candidate.expectedCoverage != other.expectedCoverage {
            return candidate.expectedCoverage > other.expectedCoverage
        }
        return candidate.windowSize < other.windowSize
    }

    private func orderedCandidateRefs() -> [String] {
        guard let nextExpectedRef else { return [] }
        return orderedAyahIndices(from: nextExpectedRef).map { ayahs[$0].ref }
    }

    private func orderedAyahIndices(from ref: CoreMLLocalQuranWordRef) -> [Int] {
        guard let currentIndex = ayahs.firstIndex(where: { $0.ref == ref.ayahRef }) else {
            return []
        }
        if allowsAnchorLock {
            return [currentIndex]
        }
        let nextIndex = ayahs.index(after: currentIndex)
        if ayahs.indices.contains(nextIndex) {
            return [currentIndex, nextIndex]
        }
        return [currentIndex]
    }

    private func orderedForwardAyahIndices(from ref: CoreMLLocalQuranWordRef) -> [Int] {
        guard let currentIndex = ayahs.firstIndex(where: { $0.ref == ref.ayahRef }) else {
            return []
        }
        if allowsAnchorLock {
            return [currentIndex]
        }
        let upperBound = min(
            ayahs.index(currentIndex, offsetBy: Self.forwardProgressLookaheadAyahs, limitedBy: ayahs.endIndex) ?? ayahs.endIndex,
            ayahs.endIndex
        )
        guard currentIndex < upperBound else { return [currentIndex] }
        return Array(currentIndex..<upperBound)
    }

    private func boundedPostLockWords(from recognizedWords: [String]) -> [String] {
        guard !recognizedWords.isEmpty else { return [] }
        let progressWords = incrementalWords(from: recognizedWords)
        let candidateWords = progressWords.isEmpty ? recognizedWords : progressWords
        guard candidateWords.count > Self.postLockMaximumRecognizedWords else {
            return candidateWords
        }
        return Array(candidateWords.suffix(Self.postLockMaximumRecognizedWords))
    }

    private func recentPostLockWords(from recognizedWords: [String]) -> [String] {
        guard recognizedWords.count > Self.postLockMaximumRecognizedWords else {
            return recognizedWords
        }
        return Array(recognizedWords.suffix(Self.postLockMaximumRecognizedWords))
    }

    private func incrementalWords(from recognizedWords: [String]) -> [String] {
        guard !recognizedWords.isEmpty, !lastRecognizedWords.isEmpty else {
            return recognizedWords
        }
        let overlap = Self.overlapWordCount(previousWords: lastRecognizedWords, currentWords: recognizedWords)
        guard overlap > 0 else {
            return recognizedWords
        }
        return Array(recognizedWords.dropFirst(overlap))
    }

    private static func match(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        normalizedTranscript: String,
        recognizedWords: [String],
        minimumStartWordIndex: Int?
    ) -> CoreMLLocalQuranMatch {
        if let spanMatch = spanMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            recognizedWords: recognizedWords,
            minimumStartWordIndex: minimumStartWordIndex
        ) {
            return spanMatch
        }

        let expectedWords = words(in: ayah.normalizedText)
        let minimumStartIndex = max((minimumStartWordIndex ?? 1) - 1, 0)
        let searchableExpectedWords = expectedWords.indices.contains(minimumStartIndex)
            ? Array(expectedWords[minimumStartIndex...])
            : []

        let expectedText = searchableExpectedWords.isEmpty
            ? ayah.normalizedText
            : searchableExpectedWords.joined(separator: " ")
        let expectedCompact = compactCharacters(expectedText)
        let actualCompact = compactCharacters(normalizedTranscript)
        let compactSimilarity = bestWindowSimilarity(
            expected: expectedCompact,
            actual: actualCompact
        )
        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            score: compactSimilarity,
            reason: "coreml_local_tolerant_match",
            startWordIndex: minimumStartIndex + 1,
            matchedWords: searchableExpectedWords.isEmpty ? expectedWords.count : searchableExpectedWords.count
        )
    }

    private static func spanMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String],
        minimumStartWordIndex: Int?
    ) -> CoreMLLocalQuranMatch? {
        let expectedWords = words(in: ayah.normalizedText)
        let minimumStartIndex = max((minimumStartWordIndex ?? 1) - 1, 0)
        let searchableExpectedWords = expectedWords.indices.contains(minimumStartIndex)
            ? Array(expectedWords[minimumStartIndex...])
            : []

        if let wordStartIndex = searchableExpectedWords.firstContiguousIndex(of: recognizedWords) {
            return CoreMLLocalQuranMatch(
                ayah: ayah,
                ayahIndex: ayahIndex,
                score: 1.0,
                reason: "coreml_local_span_match",
                startWordIndex: minimumStartIndex + wordStartIndex + 1,
                matchedWords: recognizedWords.count
            )
        }
        if !searchableExpectedWords.isEmpty,
           recognizedWords.firstContiguousIndex(of: searchableExpectedWords) != nil {
            return CoreMLLocalQuranMatch(
                ayah: ayah,
                ayahIndex: ayahIndex,
                score: 1.0,
                reason: "coreml_local_span_match",
                startWordIndex: minimumStartIndex + 1,
                matchedWords: searchableExpectedWords.count
            )
        }
        return nil
    }

    private func nextExpectedRef(after match: CoreMLLocalQuranMatch) -> String? {
        let wordCount = Self.words(in: match.ayah.normalizedText).count
        let nextWordIndex = match.startWordIndex + match.matchedWords
        if nextWordIndex <= wordCount {
            return "\(match.ayah.ref):\(nextWordIndex)"
        }
        let nextAyahIndex = match.ayahIndex + 1
        guard ayahs.indices.contains(nextAyahIndex) else { return nil }
        return "\(ayahs[nextAyahIndex].ref):1"
    }

    private func nextExpectedRefValue(after match: CoreMLLocalQuranMatch) -> String? {
        nextExpectedRef(after: match)
    }

    private static func words(in normalizedText: String) -> [String] {
        normalizedText.split(separator: " ").map(String.init)
    }

    private static func overlapWordCount(previousWords: [String], currentWords: [String]) -> Int {
        let maxOverlap = min(previousWords.count, currentWords.count)
        guard maxOverlap > 0 else { return 0 }
        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(previousWords.suffix(overlap)) == Array(currentWords.prefix(overlap)) {
                return overlap
            }
        }
        return 0
    }

    private static func compactCharacters(_ normalizedText: String) -> [Character] {
        Array(normalizedText.filter { !$0.isWhitespace })
    }

    private static func bestWindowSimilarity(expected: [Character], actual: [Character]) -> Double {
        guard !expected.isEmpty, !actual.isEmpty else { return 0 }
        if actual.count <= expected.count {
            return similarity(expected: expected, actual: actual)
        }

        let lowerWindowLength = max(1, expected.count - 4)
        let upperWindowLength = min(actual.count, expected.count + 4)
        var best = 0.0
        for windowLength in lowerWindowLength...upperWindowLength {
            guard windowLength <= actual.count else { continue }
            for startIndex in 0...(actual.count - windowLength) {
                let window = Array(actual[startIndex..<(startIndex + windowLength)])
                best = max(best, similarity(expected: expected, actual: window))
            }
        }
        return best
    }

    private static func similarity(expected: [Character], actual: [Character]) -> Double {
        let denominator = max(expected.count, actual.count)
        guard denominator > 0 else { return 1 }
        let distance = editDistance(expected, actual)
        return max(0.0, 1.0 - (Double(distance) / Double(denominator)))
    }

    private static func editDistance<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        for lhsIndex in 1...lhs.count {
            current[0] = lhsIndex
            for rhsIndex in 1...rhs.count {
                if lhs[lhsIndex - 1] == rhs[rhsIndex - 1] {
                    current[rhsIndex] = previous[rhsIndex - 1]
                } else {
                    current[rhsIndex] = min(
                        previous[rhsIndex] + 1,
                        current[rhsIndex - 1] + 1,
                        previous[rhsIndex - 1] + 1
                    )
                }
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    private static func longestCommonSubsequenceLength<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: rhs.count + 1)
        var current = Array(repeating: 0, count: rhs.count + 1)
        for lhsIndex in 1...lhs.count {
            for rhsIndex in 1...rhs.count {
                if lhs[lhsIndex - 1] == rhs[rhsIndex - 1] {
                    current[rhsIndex] = previous[rhsIndex - 1] + 1
                } else {
                    current[rhsIndex] = max(previous[rhsIndex], current[rhsIndex - 1])
                }
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}

struct CoreMLLocalQuranAyah: Equatable, Sendable {
    let surahID: Int
    let ayahID: Int
    let text: String

    var ref: String {
        "\(surahID):\(ayahID)"
    }

    var normalizedText: String {
        CoreMLArabicTextNormalizer.normalize(text)
    }
}

private struct CoreMLLocalQuranWordRef: Equatable, Sendable {
    let surahID: Int
    let ayahID: Int
    let wordIndex: Int

    var ayahRef: String {
        "\(surahID):\(ayahID)"
    }

    var rawValue: String {
        "\(ayahRef):\(wordIndex)"
    }

    init(surahID: Int, ayahID: Int, wordIndex: Int) {
        self.surahID = surahID
        self.ayahID = ayahID
        self.wordIndex = wordIndex
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(surahID: parts[0], ayahID: parts[1], wordIndex: parts[2])
    }
}

private struct CoreMLLocalQuranAnchorCandidate: Equatable, Sendable {
    let startWordIndex: Int
    let matchedWords: Int
    let anchorCount: Int
    let coverage: Double
    let score: Double
}

private struct CoreMLLocalQuranPrefixCandidate: Equatable, Sendable {
    let startAyahIndex: Int
    let endAyahIndex: Int
    let score: Double
    let actualCoverage: Double
    let expectedCoverage: Double
    let startAyahCoverage: Double
}

private struct CoreMLLocalQuranSequenceAnchorCandidate: Equatable, Sendable {
    let startAyahIndex: Int
    let endAyahIndex: Int
    let anchorCount: Int
    let coveredAyahCount: Int
    let coverage: Double
    let score: Double
}

private struct CoreMLLocalQuranOrderedAnchorProgressCandidate: Equatable, Sendable {
    let startWordIndex: Int
    let matchedWords: Int
    let strongMatches: Int
    let score: Double
}

private struct CoreMLLocalQuranForwardCandidate: Equatable, Sendable {
    let score: Double
    let expectedCoverage: Double
    let windowSize: Int
}

enum CoreMLLocalQuranCorpusError: LocalizedError, Equatable {
    case emptyCorpus(source: String?)
    case invalidLine(lineNumber: Int, line: String)

    var errorDescription: String? {
        switch self {
        case .emptyCorpus(let source):
            if let source {
                return "No Quran ayahs found in \(source)."
            }
            return "No Quran ayahs found."
        case .invalidLine(let lineNumber, let line):
            return "Invalid Tanzil Quran row at line \(lineNumber): \(line)"
        }
    }
}

enum CoreMLLocalQuranCorpus {
    private static let tanzilResourceName = "quran-simple-clean"
    private static let tanzilResourceExtension = "txt"

    static let mvpAyahs: [CoreMLLocalQuranAyah] = [
        CoreMLLocalQuranAyah(
            surahID: 4,
            ayahID: 1,
            text: "يا أيها الناس اتقوا ربكم الذي خلقكم من نفس واحدة وخلق منها زوجها وبث منهما رجالا كثيرا ونساء واتقوا الله الذي تساءلون به والأرحام إن الله كان عليكم رقيبا"
        ),
        CoreMLLocalQuranAyah(
            surahID: 4,
            ayahID: 2,
            text: "وآتوا اليتامى أموالهم ولا تتبدلوا الخبيث بالطيب ولا تأكلوا أموالهم إلى أموالكم إنه كان حوبا كبيرا"
        ),
        CoreMLLocalQuranAyah(
            surahID: 4,
            ayahID: 3,
            text: "وإن خفتم ألا تقسطوا في اليتامى فانكحوا ما طاب لكم من النساء مثنى وثلاث ورباع فإن خفتم ألا تعدلوا فواحدة أو ما ملكت أيمانكم ذلك أدنى ألا تعولوا"
        ),
        CoreMLLocalQuranAyah(
            surahID: 108,
            ayahID: 1,
            text: "إنا أعطيناك الكوثر"
        ),
        CoreMLLocalQuranAyah(
            surahID: 108,
            ayahID: 2,
            text: "فصل لربك وانحر"
        ),
        CoreMLLocalQuranAyah(
            surahID: 108,
            ayahID: 3,
            text: "إن شانئك هو الأبتر"
        ),
    ]

    static func preferredAyahs(for resourceLocation: CoreMLFastConformerResourceLocation) throws -> [CoreMLLocalQuranAyah] {
        guard let tanzilURL = tanzilURL(for: resourceLocation) else {
            CoreMLFastConformerDiagnostics.logCorpusLoaded(
                source: "mvp_fallback",
                ayahCount: mvpAyahs.count
            )
            return mvpAyahs
        }
        let ayahs = try ayahs(fromTanzilURL: tanzilURL)
        CoreMLFastConformerDiagnostics.logCorpusLoaded(
            source: tanzilURL.path,
            ayahCount: ayahs.count
        )
        return ayahs
    }

    static func ayahs(fromTanzilURL url: URL) throws -> [CoreMLLocalQuranAyah] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try ayahs(fromTanzilText: text, source: url.path)
    }

    static func ayahs(
        fromTanzilText text: String,
        source: String? = nil
    ) throws -> [CoreMLLocalQuranAyah] {
        var ayahs: [CoreMLLocalQuranAyah] = []
        let lines = text.components(separatedBy: .newlines)
        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = line.split(
                separator: "|",
                maxSplits: 2,
                omittingEmptySubsequences: false
            )
            let surahText = parts.indices.contains(0)
                ? parts[0].trimmingCharacters(in: .whitespaces)
                : ""
            let ayahText = parts.indices.contains(1)
                ? parts[1].trimmingCharacters(in: .whitespaces)
                : ""
            guard parts.count == 3,
                  let surahID = Int(surahText),
                  let ayahID = Int(ayahText),
                  !parts[2].isEmpty else {
                throw CoreMLLocalQuranCorpusError.invalidLine(
                    lineNumber: offset + 1,
                    line: line
                )
            }
            ayahs.append(
                CoreMLLocalQuranAyah(
                    surahID: surahID,
                    ayahID: ayahID,
                    text: String(parts[2])
                )
            )
        }
        guard !ayahs.isEmpty else {
            throw CoreMLLocalQuranCorpusError.emptyCorpus(source: source)
        }
        return ayahs
    }

    private static func tanzilURL(for resourceLocation: CoreMLFastConformerResourceLocation) -> URL? {
        switch resourceLocation {
        case .bundle(let bundle):
            return bundle.url(
                forResource: tanzilResourceName,
                withExtension: tanzilResourceExtension
            )
        case .modelDirectory(let directoryURL):
            let url = directoryURL.appendingPathComponent(
                "\(tanzilResourceName).\(tanzilResourceExtension)"
            )
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
}

private struct CoreMLLocalQuranMatch: Equatable, Sendable {
    let ayah: CoreMLLocalQuranAyah
    let ayahIndex: Int
    let score: Double
    let reason: String
    let startWordIndex: Int
    let matchedWords: Int

    func with(reason: String) -> CoreMLLocalQuranMatch {
        CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            score: score,
            reason: reason,
            startWordIndex: startWordIndex,
            matchedWords: matchedWords
        )
    }
}

private extension Array where Element: Equatable {
    func firstContiguousIndex(of slice: [Element]) -> Int? {
        guard !slice.isEmpty, slice.count <= count else { return nil }
        for index in 0...(count - slice.count) {
            if Array(self[index..<(index + slice.count)]) == slice {
                return index
            }
        }
        return nil
    }
}

final class CoreMLFastConformerTranscriber {
    private static let modelResourceName = "fastconformer-quran-streaming"
    private static let tokensResourceName = "tokens"
    private static let chunkSamples = 112 * 160

    private let model: MLModel
    private let featureExtractor = CoreMLFastConformerFeatureExtractor()
    private let decoder: CoreMLFastConformerCTCDecoder
    private let windowReporter: ((CoreMLFastConformerFixtureWindow) -> Void)?
    private var cacheLastChannel: MLMultiArray
    private var cacheLastTime: MLMultiArray
    private var cacheLastChannelLength: MLMultiArray
    private var bufferedAudioSegments: [CoreMLFastConformerBufferedAudioSegment] = []
    private var bufferedSampleCount = 0
    private var transcript = ""
    private var previousTokenID: Int?
    private var processedWindowCount = 0
    private var streamResetPolicy = CoreMLFastConformerStreamResetPolicy()

    convenience init(
        bundle: Bundle,
        windowReporter: ((CoreMLFastConformerFixtureWindow) -> Void)? = nil
    ) throws {
        try self.init(
            modelURL: try Self.modelURL(in: bundle),
            tokensURL: try Self.tokensURL(in: bundle),
            windowReporter: windowReporter
        )
    }

    convenience init(
        modelDirectoryURL: URL,
        windowReporter: ((CoreMLFastConformerFixtureWindow) -> Void)? = nil
    ) throws {
        try self.init(
            modelURL: try Self.modelURL(inDirectory: modelDirectoryURL),
            tokensURL: try Self.tokensURL(inDirectory: modelDirectoryURL),
            windowReporter: windowReporter
        )
    }

    private init(
        modelURL: URL,
        tokensURL: URL,
        windowReporter: ((CoreMLFastConformerFixtureWindow) -> Void)?
    ) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
        let tokens = try CoreMLFastConformerCTCDecoder.tokens(fromTokensFile: tokensURL)
        decoder = CoreMLFastConformerCTCDecoder(tokens: tokens)
        self.windowReporter = windowReporter
        cacheLastChannel = try Self.zeroedMultiArray(shape: [1, 17, 70, 512], dataType: .float16)
        cacheLastTime = try Self.zeroedMultiArray(shape: [1, 17, 512, 8], dataType: .float16)
        cacheLastChannelLength = try MLMultiArray(shape: [1], dataType: .int32)
        cacheLastChannelLength[0] = 0
        CoreMLFastConformerDiagnostics.logModelLoaded(
            modelURL: modelURL,
            tokenCount: tokens.count
        )
    }

    func reset() {
        bufferedAudioSegments.removeAll(keepingCapacity: true)
        bufferedSampleCount = 0
        transcript = ""
        processedWindowCount = 0
        streamResetPolicy.reset()
        resetStreamingState()
        CoreMLFastConformerDiagnostics.logReset()
    }

    func accept(
        pcm: Data,
        sampleRateHz: Int,
        chunkSequence: Int,
        voiceActivity: VoiceActivityPayload? = nil,
        latencyTrace: AudioChunkLatencyTrace? = nil
    ) throws -> CoreMLFastConformerTranscript? {
        guard sampleRateHz > 0 else { throw CoreMLFastConformerError.invalidAudio }
        appendBufferedAudio(
            samples: Self.samples(fromPCM16: pcm, sourceSampleRateHz: sampleRateHz),
            voiceActivity: voiceActivity,
            latencyTrace: latencyTrace
        )
        if bufferedSampleCount < Self.chunkSamples,
           CoreMLFastConformerDiagnostics.shouldLogBuffering(chunkSequence: chunkSequence) {
            CoreMLFastConformerDiagnostics.logBuffering(
                chunkSequence: chunkSequence,
                bufferedSamples: bufferedSampleCount,
                requiredSamples: Self.chunkSamples,
                sampleRateHz: sampleRateHz,
                pcmByteCount: pcm.count
            )
        }

        var latestConfidence = 0.0
        var emittedText = false
        while bufferedSampleCount >= Self.chunkSamples {
            let window = popModelWindow()
            let windowReadyAtNanoseconds = AudioChunkLatencyTrace.nowNanoseconds()
            let latencySummary = CoreMLFastConformerWindowLatencySummary(
                traces: window.latencyTraces,
                windowReadyAtNanoseconds: windowReadyAtNanoseconds
            )
            let chunk = window.samples
            let windowIndex = processedWindowCount
            processedWindowCount += 1
            let audioMetrics = CoreMLFastConformerAudioWindowMetrics(
                samples: chunk,
                voiceActivity: window.voiceActivity
            )
            CoreMLFastConformerDiagnostics.logAudioWindow(
                chunkSequence: chunkSequence,
                windowIndex: windowIndex,
                metrics: audioMetrics
            )
            if let resetReason = streamResetPolicy.resetReasonBeforePrediction(metrics: audioMetrics) {
                resetStreamingState()
                CoreMLFastConformerDiagnostics.logStreamReset(
                    reason: resetReason,
                    chunkSequence: chunkSequence,
                    windowIndex: windowIndex,
                    blankStreak: streamResetPolicy.lastResetBlankStreak,
                    metrics: audioMetrics
                )
            }
            let predictionStart = Date()
            let output = try predict(samples: chunk)
            let cumulativeTranscript = output.transcript.isEmpty
                ? transcript
                : transcript + output.transcript
            let windowReport = CoreMLFastConformerFixtureWindow(
                windowIndex: windowIndex,
                chunkSequence: chunkSequence,
                inferenceMilliseconds: Date().timeIntervalSince(predictionStart) * 1000.0,
                confidence: output.confidence,
                emittedTokenCount: output.emittedTokenIDs.count,
                transcript: output.transcript,
                cumulativeTranscript: cumulativeTranscript
            )
            CoreMLFastConformerDiagnostics.logWindow(
                chunkSequence: chunkSequence,
                windowIndex: windowIndex,
                inferenceMilliseconds: windowReport.inferenceMilliseconds,
                confidence: output.confidence,
                emittedTokenCount: output.emittedTokenIDs.count,
                transcript: output.transcript,
                cumulativeTranscript: cumulativeTranscript
            )
            CoreMLFastConformerDiagnostics.logLatencyModelWindow(
                chunkSequence: chunkSequence,
                windowIndex: windowIndex,
                summary: latencySummary,
                inferenceMilliseconds: windowReport.inferenceMilliseconds,
                emittedTokenCount: output.emittedTokenIDs.count,
                emittedText: !output.transcript.isEmpty
            )
            windowReporter?(windowReport)
            if let resetReason = streamResetPolicy.resetReasonAfterPrediction(
                metrics: audioMetrics,
                emittedTokenCount: output.emittedTokenIDs.count,
                transcript: output.transcript
            ) {
                resetStreamingState()
                CoreMLFastConformerDiagnostics.logStreamReset(
                    reason: resetReason,
                    chunkSequence: chunkSequence,
                    windowIndex: windowIndex,
                    blankStreak: streamResetPolicy.lastResetBlankStreak,
                    metrics: audioMetrics
                )
            }
            if !output.transcript.isEmpty {
                transcript = cumulativeTranscript
                emittedText = true
            }
            latestConfidence = output.confidence
        }

        guard emittedText else { return nil }
        return CoreMLFastConformerTranscript(
            transcript: transcript,
            confidence: latestConfidence,
            emittedTokenIDs: []
        )
    }

    private func appendBufferedAudio(
        samples: [Float],
        voiceActivity: VoiceActivityPayload?,
        latencyTrace: AudioChunkLatencyTrace?
    ) {
        guard !samples.isEmpty else { return }
        bufferedAudioSegments.append(
            CoreMLFastConformerBufferedAudioSegment(
                samples: samples,
                voiceActivity: voiceActivity,
                latencyTrace: latencyTrace
            )
        )
        bufferedSampleCount += samples.count
    }

    private func popModelWindow() -> (
        samples: [Float],
        voiceActivity: [VoiceActivityPayload],
        latencyTraces: [AudioChunkLatencyTrace]
    ) {
        var samples: [Float] = []
        samples.reserveCapacity(Self.chunkSamples)
        var voiceActivity: [VoiceActivityPayload] = []
        var latencyTraces: [AudioChunkLatencyTrace] = []
        var remainingSamples = Self.chunkSamples

        while remainingSamples > 0, !bufferedAudioSegments.isEmpty {
            var segment = bufferedAudioSegments.removeFirst()
            let takeCount = min(remainingSamples, segment.samples.count)
            samples.append(contentsOf: segment.samples.prefix(takeCount))
            if let payload = segment.voiceActivity {
                voiceActivity.append(payload)
            }
            if let trace = segment.latencyTrace {
                latencyTraces.append(trace)
            }

            if takeCount < segment.samples.count {
                segment.samples.removeFirst(takeCount)
                bufferedAudioSegments.insert(segment, at: 0)
            }

            bufferedSampleCount -= takeCount
            remainingSamples -= takeCount
        }

        return (samples, voiceActivity, latencyTraces)
    }

    private func resetStreamingState() {
        previousTokenID = nil
        Self.zero(cacheLastChannel)
        Self.zero(cacheLastTime)
        cacheLastChannelLength[0] = 0
    }

    private func predict(samples: [Float]) throws -> CoreMLFastConformerTranscript {
        let features = try featureExtractor.features(for: samples)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "audio_signal": MLFeatureValue(multiArray: features),
            "cache_last_channel": MLFeatureValue(multiArray: cacheLastChannel),
            "cache_last_time": MLFeatureValue(multiArray: cacheLastTime),
            "cache_last_channel_len": MLFeatureValue(multiArray: cacheLastChannelLength),
        ])
        let output = try model.prediction(from: input)
        guard let logprobs = output.featureValue(for: "logprobs")?.multiArrayValue,
              let nextChannel = output.featureValue(for: "cache_last_channel_next")?.multiArrayValue,
              let nextTime = output.featureValue(for: "cache_last_time_next")?.multiArrayValue,
              let nextLength = output.featureValue(for: "cache_last_channel_len_next")?.multiArrayValue else {
            throw CoreMLFastConformerError.invalidModelOutput
        }

        cacheLastChannel = nextChannel
        cacheLastTime = nextTime
        cacheLastChannelLength = nextLength

        let tokenOutput = try tokenIDs(fromLogprobs: logprobs)
        let decoded = decoder.decode(
            tokenIDs: tokenOutput.tokenIDs,
            previousTokenID: previousTokenID,
            trimsWhitespace: transcript.isEmpty
        )
        previousTokenID = tokenOutput.tokenIDs.last
        return CoreMLFastConformerTranscript(
            transcript: decoded.text,
            confidence: tokenOutput.confidence,
            emittedTokenIDs: decoded.emittedTokenIDs
        )
    }

    private func tokenIDs(fromLogprobs logprobs: MLMultiArray) throws -> (tokenIDs: [Int], confidence: Double) {
        guard logprobs.shape.map(\.intValue) == [1, 13, 1025] else {
            CoreMLFastConformerDiagnostics.logInvalidOutput(
                reason: "unexpected_logprobs_shape",
                detail: "shape=\(logprobs.shape.map(\.intValue))"
            )
            throw CoreMLFastConformerError.invalidModelOutput
        }

        var tokenIDs: [Int] = []
        var probabilitySum = 0.0
        for timestep in 0..<13 {
            var bestID: Int?
            var bestValue = -Double.infinity
            var nonFiniteCount = 0
            for tokenID in 0..<1025 {
                let value = logprobs[[0, timestep, tokenID] as [NSNumber]].doubleValue
                guard value.isFinite else {
                    nonFiniteCount += 1
                    continue
                }
                if value > bestValue {
                    bestValue = value
                    bestID = tokenID
                }
            }
            guard let bestID else {
                CoreMLFastConformerDiagnostics.logInvalidOutput(
                    reason: "nonfinite_logprobs",
                    detail: "timestep=\(timestep) nonfinite_values=\(nonFiniteCount)"
                )
                throw CoreMLFastConformerError.invalidModelOutput
            }
            tokenIDs.append(bestID)
            probabilitySum += exp(bestValue)
        }
        return (tokenIDs, probabilitySum / 13.0)
    }

    private static func modelURL(in bundle: Bundle) throws -> URL {
        if let compiledURL = bundle.url(forResource: modelResourceName, withExtension: "mlmodelc") {
            return compiledURL
        }
        if let packageURL = bundle.url(forResource: modelResourceName, withExtension: "mlpackage") {
            return try MLModel.compileModel(at: packageURL)
        }
        throw CoreMLFastConformerError.missingModelResource
    }

    private static func modelURL(inDirectory directoryURL: URL) throws -> URL {
        let compiledURL = directoryURL.appendingPathComponent("\(modelResourceName).mlmodelc")
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            return compiledURL
        }
        let packageURL = directoryURL.appendingPathComponent("\(modelResourceName).mlpackage")
        if FileManager.default.fileExists(atPath: packageURL.path) {
            return try MLModel.compileModel(at: packageURL)
        }
        throw CoreMLFastConformerError.missingModelResource
    }

    private static func tokensURL(in bundle: Bundle) throws -> URL {
        if let url = bundle.url(forResource: tokensResourceName, withExtension: "txt") {
            return url
        }
        throw CoreMLFastConformerError.missingTokensResource
    }

    private static func tokensURL(inDirectory directoryURL: URL) throws -> URL {
        let url = directoryURL.appendingPathComponent("\(tokensResourceName).txt")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        throw CoreMLFastConformerError.missingTokensResource
    }

    fileprivate static func samples(fromPCM16 pcm: Data, sourceSampleRateHz: Int) -> [Float] {
        let sampleCount = pcm.count / 2
        guard sampleCount > 0 else { return [] }
        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)
        pcm.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let int16Buffer = baseAddress.bindMemory(to: Int16.self, capacity: sampleCount)
            for index in 0..<sampleCount {
                samples.append(Float(Int16(littleEndian: int16Buffer[index])) / 32768.0)
            }
        }
        guard sourceSampleRateHz != 16_000 else { return samples }
        return resample(samples, sourceSampleRateHz: sourceSampleRateHz)
    }

    private static func resample(_ samples: [Float], sourceSampleRateHz: Int) -> [Float] {
        guard !samples.isEmpty, sourceSampleRateHz > 0 else { return [] }
        let outputCount = max(1, Int(round(Double(samples.count) * 16_000.0 / Double(sourceSampleRateHz))))
        guard outputCount > 1 else { return [samples[0]] }
        var output: [Float] = []
        output.reserveCapacity(outputCount)
        let step = Double(sourceSampleRateHz) / 16_000.0
        for outputIndex in 0..<outputCount {
            let position = Double(outputIndex) * step
            let leftIndex = min(Int(position), samples.count - 1)
            let rightIndex = min(leftIndex + 1, samples.count - 1)
            let fraction = Float(position - Double(leftIndex))
            output.append(samples[leftIndex] + (samples[rightIndex] - samples[leftIndex]) * fraction)
        }
        return output
    }

    private static func zeroedMultiArray(shape: [NSNumber], dataType: MLMultiArrayDataType) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape, dataType: dataType)
        zero(array)
        return array
    }

    private static func zero(_ array: MLMultiArray) {
        let bytesPerElement: Int
        switch array.dataType {
        case .int8:
            bytesPerElement = 1
        case .float16:
            bytesPerElement = 2
        case .float32, .int32:
            bytesPerElement = 4
        case .double:
            bytesPerElement = 8
        @unknown default:
            bytesPerElement = 4
        }
        memset(array.dataPointer, 0, array.count * bytesPerElement)
    }
}

private struct CoreMLFastConformerBufferedAudioSegment {
    var samples: [Float]
    let voiceActivity: VoiceActivityPayload?
    let latencyTrace: AudioChunkLatencyTrace?
}

struct CoreMLFastConformerFeatureExtractor {
    private static let sampleRate = 16_000
    private static let featureCount = 80
    private static let frameCount = 112
    private static let hopLength = 160
    private static let windowLength = 400
    private static let fftSize = 512
    private static let epsilon: Float = 1e-5

    private let window: [Float]
    private let melFilters: [[Float]]

    init() {
        window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: Self.windowLength,
            isHalfWindow: false
        )
        melFilters = Self.buildMelFilters()
    }

    func features(for samples: [Float]) throws -> MLMultiArray {
        let emphasized = Self.preemphasized(samples)
        let spectrogram = Self.powerSpectrogram(
            emphasized,
            window: window
        )
        var features = Array(
            repeating: Array(repeating: Float(0), count: Self.frameCount),
            count: Self.featureCount
        )

        for frameIndex in 0..<Self.frameCount {
            for melIndex in 0..<Self.featureCount {
                let energy = vDSP.dot(spectrogram[frameIndex], melFilters[melIndex])
                features[melIndex][frameIndex] = log(max(energy, 0) + Self.epsilon)
            }
        }

        Self.normalizePerFeature(&features)
        let array = try MLMultiArray(shape: [1, 80, 112], dataType: .float16)
        for melIndex in 0..<Self.featureCount {
            for frameIndex in 0..<Self.frameCount {
                array[[0, melIndex, frameIndex] as [NSNumber]] = NSNumber(value: features[melIndex][frameIndex])
            }
        }
        return array
    }

    private static func preemphasized(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var output = Array(repeating: Float(0), count: samples.count)
        output[0] = samples[0]
        guard samples.count > 1 else { return output }
        for index in 1..<samples.count {
            output[index] = samples[index] - 0.97 * samples[index - 1]
        }
        return output
    }

    private static func powerSpectrogram(_ samples: [Float], window: [Float]) -> [[Float]] {
        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(Self.fftSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            return Array(
                repeating: Array(repeating: Float(0), count: Self.fftSize / 2 + 1),
                count: Self.frameCount
            )
        }
        defer {
            vDSP_DFT_DestroySetup(setup)
        }

        var frames: [[Float]] = []
        frames.reserveCapacity(Self.frameCount)
        for frameIndex in 0..<Self.frameCount {
            let offset = frameIndex * Self.hopLength
            var frame = Array(repeating: Float(0), count: Self.fftSize)
            for sampleIndex in 0..<Self.windowLength {
                let sourceIndex = offset + sampleIndex
                let sample = sourceIndex < samples.count ? samples[sourceIndex] : 0
                frame[sampleIndex] = sample * window[sampleIndex]
            }

            var realInput = frame
            var imaginaryInput = Array(repeating: Float(0), count: Self.fftSize)
            var realOutput = Array(repeating: Float(0), count: Self.fftSize)
            var imaginaryOutput = Array(repeating: Float(0), count: Self.fftSize)
            vDSP_DFT_Execute(
                setup,
                &realInput,
                &imaginaryInput,
                &realOutput,
                &imaginaryOutput
            )

            var power = Array(repeating: Float(0), count: Self.fftSize / 2 + 1)
            for index in 0..<power.count {
                power[index] = realOutput[index] * realOutput[index] + imaginaryOutput[index] * imaginaryOutput[index]
            }
            frames.append(power)
        }
        return frames
    }

    private static func normalizePerFeature(_ features: inout [[Float]]) {
        for melIndex in features.indices {
            let mean = vDSP.mean(features[melIndex])
            var centered = features[melIndex].map { $0 - mean }
            let variance = vDSP.mean(centered.map { $0 * $0 })
            let scale = sqrt(variance + epsilon)
            vDSP.divide(centered, scale, result: &centered)
            features[melIndex] = centered
        }
    }

    private static func buildMelFilters() -> [[Float]] {
        let fftBins = Self.fftSize / 2 + 1
        let maxMel = hzToMel(Float(Self.sampleRate) / 2)
        let melPoints = (0..<(Self.featureCount + 2)).map { index in
            melToHz(Float(index) * maxMel / Float(Self.featureCount + 1))
        }
        let fftFrequencies = (0..<fftBins).map {
            Float($0) * Float(Self.sampleRate) / Float(Self.fftSize)
        }

        return (0..<Self.featureCount).map { melIndex in
            let lower = melPoints[melIndex]
            let center = melPoints[melIndex + 1]
            let upper = melPoints[melIndex + 2]
            return fftFrequencies.map { frequency in
                if frequency <= lower || frequency >= upper {
                    return 0
                }
                if frequency <= center {
                    return (frequency - lower) / max(center - lower, .leastNonzeroMagnitude)
                }
                return (upper - frequency) / max(upper - center, .leastNonzeroMagnitude)
            }
        }
    }

    private static func hzToMel(_ frequency: Float) -> Float {
        let linearScale: Float = 200.0 / 3.0
        let minLogHz: Float = 1_000
        let minLogMel = minLogHz / linearScale
        let logStep = log(Float(6.4)) / 27.0
        if frequency < minLogHz {
            return frequency / linearScale
        }
        return minLogMel + log(frequency / minLogHz) / logStep
    }

    private static func melToHz(_ mel: Float) -> Float {
        let linearScale: Float = 200.0 / 3.0
        let minLogHz: Float = 1_000
        let minLogMel = minLogHz / linearScale
        let logStep = log(Float(6.4)) / 27.0
        if mel < minLogMel {
            return mel * linearScale
        }
        return minLogHz * exp(logStep * (mel - minLogMel))
    }
}

private extension Data {
    func asciiString(in range: Range<Int>) -> String {
        guard range.lowerBound >= 0, range.upperBound <= count else { return "" }
        return String(decoding: self[range], as: UTF8.self)
    }

    func uint16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func int16LE(at offset: Int) -> Int16 {
        Int16(bitPattern: uint16LE(at: offset))
    }

    mutating func appendInt16LE(_ value: Int16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private extension RecitationEvent {
    static func coreMLWaiting(chunkSequence: Int) -> RecitationEvent {
        RecitationEvent(
            type: .locating,
            transcript: "",
            confidence: 0,
            chunkSequence: chunkSequence,
            reason: "waiting_for_coreml_audio_buffer",
            candidateRefs: [],
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: nil,
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )
    }

    static func coreMLTranscript(
        transcript: String,
        confidence: Double,
        chunkSequence: Int,
        reason: String = "coreml_fastconformer_transcript",
        candidateRefs: [String] = []
    ) -> RecitationEvent {
        RecitationEvent(
            type: .locating,
            transcript: transcript,
            confidence: confidence,
            chunkSequence: chunkSequence,
            reason: reason,
            candidateRefs: candidateRefs,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: nil,
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )
    }

    static func coreMLLocated(
        type: RecitationEventType,
        transcript: String,
        confidence: Double,
        chunkSequence: Int,
        match: CoreMLLocalQuranMatch,
        nextExpectedRef: String?
    ) -> RecitationEvent {
        RecitationEvent(
            type: type,
            transcript: transcript,
            confidence: confidence,
            chunkSequence: chunkSequence,
            reason: match.reason,
            candidateRefs: [match.ayah.ref],
            ayahText: match.ayah.text,
            ayahRef: match.ayah.ref,
            startRef: "\(match.ayah.ref):\(match.startWordIndex)",
            nextExpectedRef: nextExpectedRef,
            consumedWords: match.matchedWords,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )
    }
}
