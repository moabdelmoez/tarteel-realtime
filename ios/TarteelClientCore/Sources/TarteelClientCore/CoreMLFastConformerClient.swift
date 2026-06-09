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

    static func shouldLogBuffering(chunkSequence: Int) -> Bool {
        chunkSequence == 0 || chunkSequence % 10 == 0
    }

    static func logInvalidOutput(reason: String, detail: String) {
        logger.error("coreml_asr_invalid_output reason=\(reason, privacy: .public) detail=\(detail, privacy: .public)")
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

        let result = try transcriber.accept(
            pcm: payload.pcm,
            sampleRateHz: payload.sampleRateHz,
            chunkSequence: payload.sequenceNumber
        )

        guard let result else {
            return RecitationEvent.coreMLWaiting(chunkSequence: payload.sequenceNumber)
        }

        return localSession.event(
            transcript: result.transcript,
            confidence: result.confidence,
            chunkSequence: payload.sequenceNumber
        )
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
    public static let defaultLiveChunkSamples = 1_360
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

    private let ayahs: [CoreMLLocalQuranAyah]
    private var currentAyahIndex: Int?

    init(
        scope: RecitationScopeSelection = .autoDetect,
        corpus: [CoreMLLocalQuranAyah] = CoreMLLocalQuranCorpus.mvpAyahs
    ) {
        switch scope {
        case .autoDetect:
            ayahs = corpus
        case .selectedSurah(let id):
            ayahs = corpus.filter { $0.surahID == id }
        }
    }

    mutating func reset() {
        currentAyahIndex = nil
    }

    mutating func event(
        transcript: String,
        confidence: Double,
        chunkSequence: Int
    ) -> RecitationEvent {
        let normalizedTranscript = CoreMLArabicTextNormalizer.normalize(transcript)
        let recognizedWords = Self.words(in: normalizedTranscript)
        guard recognizedWords.count >= Self.minimumRecognizedWords else {
            return RecitationEvent.coreMLTranscript(
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                reason: recognizedWords.isEmpty ? "coreml_local_no_words" : "coreml_local_insufficient_context"
            )
        }

        let matches = ayahs.enumerated().compactMap { index, ayah in
            Self.match(
                ayah: ayah,
                ayahIndex: index,
                normalizedTranscript: normalizedTranscript,
                recognizedWords: recognizedWords
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

        guard let match = viableMatches.first else {
            return RecitationEvent.coreMLTranscript(
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                reason: "coreml_local_no_match",
                candidateRefs: matches.prefix(3).map(\.ayah.ref)
            )
        }

        let eventType: RecitationEventType = currentAyahIndex == nil ? .locked : .progress
        currentAyahIndex = match.ayahIndex
        return RecitationEvent.coreMLLocated(
            type: eventType,
            transcript: transcript,
            confidence: confidence,
            chunkSequence: chunkSequence,
            match: match,
            nextExpectedRef: nextExpectedRef(after: match)
        )
    }

    private static func match(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        normalizedTranscript: String,
        recognizedWords: [String]
    ) -> CoreMLLocalQuranMatch {
        let expectedWords = words(in: ayah.normalizedText)
        if let wordStartIndex = expectedWords.firstContiguousIndex(of: recognizedWords) {
            return CoreMLLocalQuranMatch(
                ayah: ayah,
                ayahIndex: ayahIndex,
                score: 1.0,
                reason: "coreml_local_span_match",
                startWordIndex: wordStartIndex + 1,
                matchedWords: recognizedWords.count
            )
        }
        if recognizedWords.firstContiguousIndex(of: expectedWords) != nil {
            return CoreMLLocalQuranMatch(
                ayah: ayah,
                ayahIndex: ayahIndex,
                score: 1.0,
                reason: "coreml_local_span_match",
                startWordIndex: 1,
                matchedWords: expectedWords.count
            )
        }

        let expectedCompact = compactCharacters(ayah.normalizedText)
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
            startWordIndex: 1,
            matchedWords: expectedWords.count
        )
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

    private static func words(in normalizedText: String) -> [String] {
        normalizedText.split(separator: " ").map(String.init)
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
            return mvpAyahs
        }
        return try ayahs(fromTanzilURL: tanzilURL)
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
    private var bufferedSamples: [Float] = []
    private var transcript = ""
    private var previousTokenID: Int?
    private var processedWindowCount = 0

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
        bufferedSamples.removeAll(keepingCapacity: true)
        transcript = ""
        previousTokenID = nil
        processedWindowCount = 0
        Self.zero(cacheLastChannel)
        Self.zero(cacheLastTime)
        cacheLastChannelLength[0] = 0
        CoreMLFastConformerDiagnostics.logReset()
    }

    func accept(pcm: Data, sampleRateHz: Int, chunkSequence: Int) throws -> CoreMLFastConformerTranscript? {
        guard sampleRateHz > 0 else { throw CoreMLFastConformerError.invalidAudio }
        bufferedSamples.append(
            contentsOf: Self.samples(fromPCM16: pcm, sourceSampleRateHz: sampleRateHz)
        )
        if bufferedSamples.count < Self.chunkSamples,
           CoreMLFastConformerDiagnostics.shouldLogBuffering(chunkSequence: chunkSequence) {
            CoreMLFastConformerDiagnostics.logBuffering(
                chunkSequence: chunkSequence,
                bufferedSamples: bufferedSamples.count,
                requiredSamples: Self.chunkSamples,
                sampleRateHz: sampleRateHz,
                pcmByteCount: pcm.count
            )
        }

        var latestConfidence = 0.0
        var emittedText = false
        while bufferedSamples.count >= Self.chunkSamples {
            let chunk = Array(bufferedSamples.prefix(Self.chunkSamples))
            bufferedSamples.removeFirst(Self.chunkSamples)
            let windowIndex = processedWindowCount
            processedWindowCount += 1
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
            windowReporter?(windowReport)
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
