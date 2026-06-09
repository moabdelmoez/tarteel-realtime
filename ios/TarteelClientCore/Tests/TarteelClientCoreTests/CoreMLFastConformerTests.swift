import CoreML
import Foundation
import Testing
@testable import TarteelClientCore

@MainActor
struct CoreMLFastConformerTests {
    @Test func ctcDecoderDropsBlankAndCollapsesConsecutiveTokens() throws {
        let decoder = CoreMLFastConformerCTCDecoder(tokens: [
            0: "<unk>",
            1: "▁قُل",
            2: "ْ",
            3: "▁هُوَ",
        ])

        let result = decoder.decode(tokenIDs: [1, 1, 2, 1024, 3, 3])

        #expect(result.text == "قُلْ هُوَ")
        #expect(result.emittedTokenIDs == [1, 2, 3])
    }

    @Test func ctcDecoderCanPreserveSentencePieceBoundaryForStreamingAppend() throws {
        let decoder = CoreMLFastConformerCTCDecoder(tokens: [
            1: "▁قُلْ",
            2: "▁هُوَ",
        ])

        let standalone = decoder.decode(tokenIDs: [2])
        let continuation = decoder.decode(tokenIDs: [2], trimsWhitespace: false)

        #expect(standalone.text == "هُوَ")
        #expect(continuation.text == " هُوَ")
    }

    @Test func diagnosticsBufferingCadenceLogsFirstChunkAndEveryTenChunks() {
        #expect(CoreMLFastConformerDiagnostics.shouldLogBuffering(chunkSequence: 0))
        #expect(!CoreMLFastConformerDiagnostics.shouldLogBuffering(chunkSequence: 1))
        #expect(CoreMLFastConformerDiagnostics.shouldLogBuffering(chunkSequence: 10))
        #expect(!CoreMLFastConformerDiagnostics.shouldLogBuffering(chunkSequence: 11))
    }

    @Test func fixtureWAVLoaderDownmixesStereoPCM16() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("stereo.wav")
        try makePCM16WAV(
            sampleRateHz: 44_100,
            channelCount: 2,
            frames: [
                [1_000, -1_000],
                [3_000, 1_000],
            ]
        ).write(to: url)

        let audio = try CoreMLFastConformerFixtureAudio.loadWAV(from: url)

        #expect(audio.sampleRateHz == 44_100)
        #expect(audio.sourceChannelCount == 2)
        #expect(audio.frameCount == 2)
        #expect(samples(fromPCM16: audio.pcm16Mono) == [0, 2_000])
    }

    @Test func fixtureReportSummaryShowsWindowAndCumulativeTranscript() {
        let report = CoreMLFastConformerFixtureReport(
            audioPath: "/tmp/108001.wav",
            sampleRateHz: 16_000,
            sourceChannelCount: 1,
            frameCount: 32_000,
            windows: [
                CoreMLFastConformerFixtureWindow(
                    windowIndex: 0,
                    chunkSequence: 13,
                    inferenceMilliseconds: 31.25,
                    confidence: 0.875,
                    emittedTokenCount: 3,
                    transcript: "اللَّهُ",
                    cumulativeTranscript: "اللَّهُ"
                ),
            ]
        )

        let summary = report.textSummary()

        #expect(summary.contains("audio: /tmp/108001.wav"))
        #expect(summary.contains("duration_seconds: 2.000"))
        #expect(summary.contains("final_transcript: اللَّهُ"))
        #expect(summary.contains("window=0 chunk_sequence=13 inference_ms=31.2 confidence=0.8750 emitted_tokens=3"))
        #expect(summary.contains("cumulative=\"اللَّهُ\""))
    }

    @Test func fixtureScoringNormalizesArabicAndReportsMissingPrefix() {
        let score = CoreMLFastConformerFixtureScore.score(
            expectedText: "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ",
            actualText: "أَعْطَيْنَاكَ الْكَوْثَرَ"
        )

        #expect(score.normalizedExpectedText == "انا اعطيناك الكوثر")
        #expect(score.normalizedActualText == "اعطيناك الكوثر")
        #expect(abs(score.wordMatchScore - (2.0 / 3.0)) < 0.0001)
        #expect(abs(score.wordErrorRate - (1.0 / 3.0)) < 0.0001)
        #expect(score.missingWords == ["انا"])
        #expect(score.extraWords == [])
    }

    @Test func fixtureReportCanAttachExpectedManifestEntry() {
        let report = CoreMLFastConformerFixtureReport(
            audioPath: "/tmp/108001.wav",
            sampleRateHz: 16_000,
            sourceChannelCount: 1,
            frameCount: 16_000,
            windows: [
                CoreMLFastConformerFixtureWindow(
                    windowIndex: 0,
                    chunkSequence: 13,
                    inferenceMilliseconds: 20.0,
                    confidence: 0.9,
                    emittedTokenCount: 2,
                    transcript: "أَعْطَيْنَاكَ الْكَوْثَرَ",
                    cumulativeTranscript: "أَعْطَيْنَاكَ الْكَوْثَرَ"
                ),
            ]
        )
        let expectation = CoreMLFastConformerFixtureExpectation(
            audioFile: "108001.wav",
            ayahRef: "108:1",
            expectedText: "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ"
        )

        let scoredReport = report.scored(with: expectation)
        let summary = scoredReport.textSummary()

        #expect(scoredReport.expectation == expectation)
        #expect(scoredReport.score?.missingWords == ["انا"])
        #expect(summary.contains("ayah_ref: 108:1"))
        #expect(summary.contains("expected_text: إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ"))
        #expect(summary.contains("normalized_word_score: 0.667"))
        #expect(summary.contains("missing_words: انا"))
    }

    @Test func localAudioReplayStreamerEmitsLiveSized16KChunks() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("mono16k.wav")
        try makePCM16WAV(
            sampleRateHz: 16_000,
            channelCount: 1,
            frames: [
                [1],
                [2],
                [3],
                [4],
                [5],
            ]
        ).write(to: url)
        let streamer = try LocalAudioReplayStreamer(
            audioURL: url,
            chunkSampleCount: 2
        )
        nonisolated(unsafe) var emittedSamples: [[Int16]] = []
        nonisolated(unsafe) var emittedSampleRates: [Int] = []

        try await streamer.start { data, sampleRate in
            emittedSamples.append(samples(fromPCM16: data))
            emittedSampleRates.append(sampleRate)
        }
        await streamer.replay()

        #expect(emittedSamples == [[1, 2], [3, 4], [5]])
        #expect(emittedSampleRates == [16_000, 16_000, 16_000])
    }

    @Test func localAudioReplayConfigurationParsesFixtureLaunchArguments() throws {
        let configuration = try #require(LocalAudioReplayConfiguration(arguments: [
            "/Applications/TarteelPrototype.app/TarteelPrototype",
            "--tarteel-replay-audio",
            "108001.wav",
            "--tarteel-replay-surah",
            "108",
        ]))

        #expect(configuration.audioArgument == "108001.wav")
        #expect(configuration.selectedSurahID == 108)
    }

    @Test func fixtureManifestLooksUpExpectationsByAudioFilename() throws {
        let manifest = CoreMLFastConformerFixtureManifest(entries: [
            CoreMLFastConformerFixtureExpectation(
                audioFile: "108001.wav",
                ayahRef: "108:1",
                expectedText: "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ"
            ),
        ])

        let expectation = try manifest.expectation(forAudioPath: "/tmp/local_audio/108001.wav")

        #expect(expectation.ayahRef == "108:1")
    }

    @Test func localQuranSessionLocksAndProgressesScopedCoreMLTranscript() {
        var session = CoreMLLocalQuranSession(scope: .selectedSurah(id: 108))

        let locked = session.event(
            transcript: "أَعْطَيْنَاكَ الْكَوْثَرَ",
            confidence: 0.91,
            chunkSequence: 7
        )
        let progressed = session.event(
            transcript: "أَعْطَيْنَاكَ الْكَوْثَرَ فَصَلِّرََبِّكَ وَانْحَرْ",
            confidence: 0.88,
            chunkSequence: 15
        )

        #expect(locked.type == .locked)
        #expect(locked.reason == "coreml_local_span_match")
        #expect(locked.ayahRef == "108:1")
        #expect(locked.ayahText == "إنا أعطيناك الكوثر")
        #expect(locked.startRef == "108:1:2")
        #expect(locked.candidateRefs == ["108:1"])
        #expect(progressed.type == .progress)
        #expect(progressed.reason == "coreml_local_tolerant_match")
        #expect(progressed.ayahRef == "108:2")
        #expect(progressed.ayahText == "فصل لربك وانحر")
        #expect(progressed.nextExpectedRef == "108:3:1")
    }

    @Test func localQuranSessionCanUseTanzilCorpusBeyondMVPAyahs() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        112|1|قل هو الله أحد
        114|2|ملك الناس
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 114),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "مَلِكِ النَّاسِ",
            confidence: 0.93,
            chunkSequence: 4
        )

        #expect(locked.type == .locked)
        #expect(locked.reason == "coreml_local_span_match")
        #expect(locked.ayahRef == "114:2")
        #expect(locked.ayahText == "ملك الناس")
        #expect(locked.startRef == "114:2:1")
    }

    @Test func tanzilCorpusRejectsMalformedRows() throws {
        do {
            _ = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
            1|1|بسم الله الرحمن الرحيم
            malformed row
            """)
            Issue.record("Expected malformed Tanzil rows to throw.")
        } catch let error as CoreMLLocalQuranCorpusError {
            #expect(error == .invalidLine(lineNumber: 2, line: "malformed row"))
        } catch {
            Issue.record("Expected CoreMLLocalQuranCorpusError, got \(error).")
        }
    }

    @Test func localPinnedTanzilCorpusParsesWhenPresent() throws {
        guard let url = localPinnedTanzilCorpusURL() else { return }

        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilURL: url)

        #expect(corpus.count == 6_236)
        #expect(corpus.first?.ref == "1:1")
        #expect(corpus.last?.ref == "114:6")
    }

    @Test func routingSocketUsesCoreMLClientForCoreMLScheme() async throws {
        let local = CapturingSocket()
        let remote = CapturingSocket()
        let router = RoutingBackendSocketClient(
            remote: remote,
            coreML: local
        )
        let url = try #require(URL(string: BackendEndpointPreset.coreML.defaultURLText))

        try await router.connect(url: url, authorizationToken: "secret") { _ in }
        try await router.send(AudioChunkPayload(sequenceNumber: 0, pcm: Data([1, 2]), sampleRateHz: 16_000))

        #expect(local.connectedURL == url)
        #expect(local.authorizationToken == nil)
        #expect(local.sentPayloads.map(\.sequenceNumber) == [0])
        #expect(remote.connectedURL == nil)
    }

    @Test func routingSocketUsesRemoteClientForWebSocketScheme() async throws {
        let local = CapturingSocket()
        let remote = CapturingSocket()
        let router = RoutingBackendSocketClient(
            remote: remote,
            coreML: local
        )
        let url = try #require(URL(string: "wss://example.test/ws/recitation"))

        try await router.connect(url: url, authorizationToken: "secret") { _ in }
        try await router.send(AudioChunkPayload(sequenceNumber: 1, pcm: Data([3, 4]), sampleRateHz: 16_000))

        #expect(remote.connectedURL == url)
        #expect(remote.authorizationToken == "secret")
        #expect(remote.sentPayloads.map(\.sequenceNumber) == [1])
        #expect(local.connectedURL == nil)
    }
}

@MainActor
private final class CapturingSocket: BackendSocketing {
    private(set) var connectedURL: URL?
    private(set) var authorizationToken: String?
    private(set) var sentPayloads: [AudioChunkPayload] = []

    func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        connectedURL = url
        self.authorizationToken = authorizationToken
    }

    func send(_ payload: AudioChunkPayload) async throws {
        sentPayloads.append(payload)
    }

    func disconnect() {}
}

private func makePCM16WAV(sampleRateHz: Int, channelCount: Int, frames: [[Int16]]) -> Data {
    var data = Data()
    data.appendASCII("RIFF")
    data.appendUInt32LE(UInt32(36 + frames.count * channelCount * 2))
    data.appendASCII("WAVE")
    data.appendASCII("fmt ")
    data.appendUInt32LE(16)
    data.appendUInt16LE(1)
    data.appendUInt16LE(UInt16(channelCount))
    data.appendUInt32LE(UInt32(sampleRateHz))
    data.appendUInt32LE(UInt32(sampleRateHz * channelCount * 2))
    data.appendUInt16LE(UInt16(channelCount * 2))
    data.appendUInt16LE(16)
    data.appendASCII("data")
    data.appendUInt32LE(UInt32(frames.count * channelCount * 2))
    for frame in frames {
        for sample in frame {
            data.appendInt16LE(sample)
        }
    }
    return data
}

private func samples(fromPCM16 data: Data) -> [Int16] {
    var samples: [Int16] = []
    data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        let int16Buffer = baseAddress.bindMemory(to: Int16.self, capacity: data.count / 2)
        for index in 0..<(data.count / 2) {
            samples.append(Int16(littleEndian: int16Buffer[index]))
        }
    }
    return samples
}

private func localPinnedTanzilCorpusURL() -> URL? {
    let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let worktreeRoot = packageRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let rootWorkspace = worktreeRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let candidates = [
        worktreeRoot,
        rootWorkspace,
    ].map {
        $0.appendingPathComponent("data/tanzil/quran-simple-clean.txt")
    }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt16LE(_ value: Int16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
