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

    @Test func audioChunkLatencyTraceComputesQueueVADAndSendDurations() {
        let received = UInt64(1_000_000_000)
        let trace = AudioChunkLatencyTrace(receivedAtNanoseconds: received)
            .markingQueuedForSend(atNanoseconds: received + 25_000_000)
            .markingVoiceActivityFinished(atNanoseconds: received + 65_000_000)
            .markingSendFinished(atNanoseconds: received + 95_000_000)

        #expect(trace.queueDelayMilliseconds == 25.0)
        #expect(trace.voiceActivityMilliseconds == 40.0)
        #expect(trace.sendMilliseconds == 30.0)
        #expect(trace.totalMilliseconds == 95.0)
        #expect(AudioChunkLatencyTrace.format(milliseconds: trace.totalMilliseconds) == "95.0")
        #expect(AudioChunkLatencyTrace.format(milliseconds: nil) == "none")
    }

    @Test func audioChunkPayloadDoesNotEncodeLocalLatencyTrace() throws {
        let payload = AudioChunkPayload(
            sequenceNumber: 7,
            pcm: Data([1, 2, 3]),
            sampleRateHz: 16_000,
            voiceActivity: VoiceActivityPayload(
                probability: 0.75,
                isSpeechActive: true,
                event: .speechStart
            ),
            latencyTrace: AudioChunkLatencyTrace(receivedAtNanoseconds: 1_000)
        )

        let encoded = try JSONEncoder().encode(payload)
        let json = String(decoding: encoded, as: UTF8.self)

        #expect(json.contains("sequence_number"))
        #expect(json.contains("voice_activity"))
        #expect(!json.contains("latency"))
        #expect(!json.contains("receivedAtNanoseconds"))
    }

    @Test func modelWindowLatencySummaryUsesOldestAndNewestChunkTrace() {
        let base = UInt64(1_000_000_000)
        let oldest = AudioChunkLatencyTrace(receivedAtNanoseconds: base)
            .markingVoiceActivityFinished(atNanoseconds: base + 10_000_000)
        let newest = AudioChunkLatencyTrace(receivedAtNanoseconds: base + 960_000_000)
            .markingVoiceActivityFinished(atNanoseconds: base + 980_000_000)

        let summary = CoreMLFastConformerWindowLatencySummary(
            traces: [oldest, newest],
            windowReadyAtNanoseconds: base + 1_120_000_000
        )

        #expect(summary.firstChunkToWindowMilliseconds == 1_120.0)
        #expect(summary.lastChunkToWindowMilliseconds == 160.0)
        #expect(summary.lastVADToWindowMilliseconds == 140.0)
        #expect(summary.traceCount == 2)
    }

    @Test func audioWindowMetricsSummarizeSignalLevelAndVAD() {
        let metrics = CoreMLFastConformerAudioWindowMetrics(
            samples: [0.0, 0.5, -0.5, 0.01],
            voiceActivity: [
                VoiceActivityPayload(probability: 0.2, isSpeechActive: false, event: .speechEnd),
                VoiceActivityPayload(probability: 0.8, isSpeechActive: true, event: .speechStart),
            ],
            nearSilenceThreshold: 0.02
        )

        #expect(metrics.sampleCount == 4)
        #expect(abs(metrics.rmsAmplitude - 0.3536) < 0.0001)
        #expect(metrics.peakAmplitude == 0.5)
        #expect(metrics.nearSilenceRatio == 0.5)
        #expect(metrics.voiceActivityObservationCount == 2)
        #expect(metrics.voiceActivitySpeechChunkCount == 1)
        #expect(metrics.voiceActivityLatestEvent == .speechStart)
        #expect(metrics.voiceActivityMeanProbability == 0.5)
    }

    @Test func streamResetPolicyResetsAtSpeechBoundaryBeforeNextActiveWindow() {
        var policy = CoreMLFastConformerStreamResetPolicy()

        let ended = policy.resetReasonBeforePrediction(
            metrics: activeSpeechMetrics(event: .speechEnd)
        )
        let restarted = policy.resetReasonBeforePrediction(
            metrics: activeSpeechMetrics(event: .speechStart)
        )
        let steady = policy.resetReasonBeforePrediction(
            metrics: activeSpeechMetrics(event: nil)
        )

        #expect(ended == nil)
        #expect(restarted == .speechBoundary)
        #expect(steady == nil)
    }

    @Test func streamResetPolicyResetsAfterActiveSpeechBlankStreak() {
        var policy = CoreMLFastConformerStreamResetPolicy()

        let transcript = policy.resetReasonAfterPrediction(
            metrics: activeSpeechMetrics(event: nil),
            emittedTokenCount: 3,
            transcript: "إنا"
        )
        let first = policy.resetReasonAfterPrediction(
            metrics: activeSpeechMetrics(event: nil),
            emittedTokenCount: 0,
            transcript: ""
        )
        let second = policy.resetReasonAfterPrediction(
            metrics: activeSpeechMetrics(event: nil),
            emittedTokenCount: 0,
            transcript: ""
        )
        let third = policy.resetReasonAfterPrediction(
            metrics: activeSpeechMetrics(event: nil),
            emittedTokenCount: 0,
            transcript: ""
        )
        let afterReset = policy.resetReasonAfterPrediction(
            metrics: activeSpeechMetrics(event: nil),
            emittedTokenCount: 0,
            transcript: ""
        )

        #expect(transcript == nil)
        #expect(first == nil)
        #expect(second == nil)
        #expect(third == .blankStreak)
        #expect(afterReset == nil)
    }

    @Test func streamResetPolicyDoesNotResetStartupActiveSpeechBlanksBeforeTranscript() {
        var policy = CoreMLFastConformerStreamResetPolicy()

        let reasons = (0..<4).map { _ in
            policy.resetReasonAfterPrediction(
                metrics: activeSpeechMetrics(event: nil),
                emittedTokenCount: 0,
                transcript: ""
            )
        }

        #expect(reasons.allSatisfy { $0 == nil })
    }

    @Test func streamResetPolicyDoesNotResetForQuietBlanks() {
        var policy = CoreMLFastConformerStreamResetPolicy()

        let reasons = (0..<4).map { _ in
            policy.resetReasonAfterPrediction(
                metrics: quietMetrics(),
                emittedTokenCount: 0,
                transcript: ""
            )
        }

        #expect(reasons.allSatisfy { $0 == nil })
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

    @Test func localAudioCaptureWritesReplayableMono16KWAV() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("captured.wav")
        let capture = try LocalAudioCaptureWriter(outputURL: url)

        try capture.append(pcm16: pcm16Data([1_000, -1_000]), sampleRateHz: 16_000)
        try capture.append(pcm16: pcm16Data([2_000, -2_000, 3_000]), sampleRateHz: 16_000)
        try capture.finish()

        let audio = try CoreMLFastConformerFixtureAudio.loadWAV(from: url)
        #expect(audio.sampleRateHz == 16_000)
        #expect(audio.sourceChannelCount == 1)
        #expect(audio.frameCount == 5)
        #expect(samples(fromPCM16: audio.pcm16Mono) == [1_000, -1_000, 2_000, -2_000, 3_000])
    }

    @Test func capturingAudioStreamerRecordsExactlyForwardedChunksForReplay() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("captured-replay.wav")
        let source = ManualAudioStreamer()
        let capture = try LocalAudioCaptureWriter(outputURL: url)
        let streamer = CapturingAudioStreamer(upstream: source, captureWriter: capture)
        nonisolated(unsafe) var forwardedSamples: [[Int16]] = []

        try await streamer.start { data, _ in
            forwardedSamples.append(samples(fromPCM16: data))
        }
        await source.emit(pcm: pcm16Data([1, 2]), sampleRate: 16_000)
        await source.emit(pcm: pcm16Data([3, 4]), sampleRate: 16_000)
        streamer.stop()

        let replay = try LocalAudioReplayStreamer(audioURL: url, chunkSampleCount: 2)
        nonisolated(unsafe) var replayedSamples: [[Int16]] = []
        try await replay.start { data, _ in
            replayedSamples.append(samples(fromPCM16: data))
        }
        await replay.replay()

        #expect(forwardedSamples == [[1, 2], [3, 4]])
        #expect(replayedSamples == [[1, 2], [3, 4]])
    }

    @Test func capturingAudioStreamerReopensOutputURLForEachRecording() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("captured-repeat.wav")
        let source = ManualAudioStreamer()
        let streamer = CapturingAudioStreamer(upstream: source, outputURL: url)

        try await streamer.start { _, _ in }
        await source.emit(pcm: pcm16Data([1, 2]), sampleRate: 16_000)
        streamer.stop()

        try await streamer.start { _, _ in }
        await source.emit(pcm: pcm16Data([3, 4]), sampleRate: 16_000)
        streamer.stop()

        let audio = try CoreMLFastConformerFixtureAudio.loadWAV(from: url)
        #expect(samples(fromPCM16: audio.pcm16Mono) == [3, 4])
    }

    @Test func localAudioCaptureConfigurationParsesDeveloperLaunchArgument() throws {
        let configuration = try #require(LocalAudioCaptureConfiguration(arguments: [
            "/Applications/TarteelPrototypeMac.app/TarteelPrototypeMac",
            "--tarteel-capture-audio",
            "~/Desktop/surah59-live.wav",
        ]))

        #expect(configuration.outputArgument == "~/Desktop/surah59-live.wav")
        #expect(configuration.outputURL.path.hasSuffix("/Desktop/surah59-live.wav"))
    }

    @Test func liveChunkCadenceDividesCoreMLModelWindow() {
        #expect(CoreMLFastConformerFixtureRunner.modelChunkSamples == 112 * 160)
        #expect(CoreMLFastConformerFixtureRunner.defaultLiveChunkSamples == 2_560)
        #expect(CoreMLFastConformerFixtureRunner.modelChunkSamples % CoreMLFastConformerFixtureRunner.defaultLiveChunkSamples == 0)
        #expect(CoreMLFastConformerFixtureRunner.modelChunkSamples / CoreMLFastConformerFixtureRunner.defaultLiveChunkSamples == 7)
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
        #expect(progressed.reason == "coreml_local_ordered_progress")
        #expect(progressed.ayahRef == "108:2")
        #expect(progressed.ayahText == "فصل لربك وانحر")
        #expect(progressed.nextExpectedRef == "108:3:1")
    }

    @Test func localQuranSessionProgressesOneExpectedWordAfterLock() {
        var session = CoreMLLocalQuranSession(scope: .selectedSurah(id: 108))

        _ = session.event(
            transcript: "أَعْطَيْنَاكَ الْكَوْثَرَ",
            confidence: 0.91,
            chunkSequence: 7
        )
        let progressed = session.event(
            transcript: "أَعْطَيْنَاكَ الْكَوْثَرَ فَصَلِّ",
            confidence: 0.88,
            chunkSequence: 15
        )

        #expect(progressed.type == .progress)
        #expect(progressed.reason == "coreml_local_ordered_progress")
        #expect(progressed.ayahRef == "108:2")
        #expect(progressed.ayahText == "فصل لربك وانحر")
        #expect(progressed.startRef == "108:2:1")
        #expect(progressed.nextExpectedRef == "108:2:2")
        #expect(progressed.consumedWords == 1)
    }

    @Test func localQuranSessionLocksNoisySelectedSurahTranscript() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        99|1|إذا زلزلت الأرض زلزالها
        99|2|وأخرجت الأرض أثقالها
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 99),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "وُلَّهِ ن الشَّيْطَ الرَّجِيمَِّ إِذَا زُلْزلَتِ الْأَرْض زلَْالَهَا",
            confidence: 0.70,
            chunkSequence: 131
        )

        #expect(locked.type == .locked)
        #expect(locked.ayahRef == "99:1")
        #expect(locked.ayahText == "إذا زلزلت الأرض زلزالها")
        #expect(locked.nextExpectedRef == "99:2:1")
    }

    @Test func localQuranSessionDoesNotLockOnNoisySurah35PrefaceAlone() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        35|1|الحمد لله فاطر السماوات والأرض جاعل الملائكة رسلا أولي أجنحة مثنى وثلاث ورباع يزيد في الخلق ما يشاء إن الله على كل شيء قدير
        35|2|ما يفتح الله للناس من رحمة فلا ممسك لها وما يمسك فلا مرسل له من بعده وهو العزيز الحكيم
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 35),
            corpus: corpus
        )

        let event = session.event(
            transcript: "أَوْ لَيْنَ شَيْطًا رَِّيمٌحم",
            confidence: 0.74,
            chunkSequence: 41
        )

        #expect(event.type == .locating)
        #expect(event.ayahRef == nil)
        #expect(event.reason == "coreml_local_no_match")
    }

    @Test func localQuranSessionIgnoresIstiazaBeforeSelectedSurahBasmala() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        18|1|بسم الله الرحمن الرحيم الحمد لله الذي أنزل على عبده الكتاب ولم يجعل له عوجا ۜ
        18|2|قيما لينذر بأسا شديدا من لدنه ويبشر المؤمنين الذين يعملون الصالحات أن لهم أجرا حسنا
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 18),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "أعوذ بالله من الشيطان الرجيم الرحمن الرحيم",
            confidence: 0.74,
            chunkSequence: 34
        )

        #expect(locked.type == .locked)
        #expect(locked.reason == "coreml_local_opening_basmala_lock")
        #expect(locked.ayahRef == "18:1")
        #expect(locked.startRef == "18:1:3")
        #expect(locked.nextExpectedRef == "18:1:5")
        #expect(locked.consumedWords == 2)
    }

    @Test func localQuranSessionDoesNotLockOnIstiazaAlone() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        18|1|بسم الله الرحمن الرحيم الحمد لله الذي أنزل على عبده الكتاب ولم يجعل له عوجا ۜ
        18|2|قيما لينذر بأسا شديدا من لدنه ويبشر المؤمنين الذين يعملون الصالحات أن لهم أجرا حسنا
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 18),
            corpus: corpus
        )

        let event = session.event(
            transcript: "أعوذ بالله من الشيطان الرجيم",
            confidence: 0.82,
            chunkSequence: 20
        )

        #expect(event.type == .locating)
        #expect(event.ayahRef == nil)
        #expect(event.reason == "coreml_local_opening_preface_no_match")
    }

    @Test func localQuranSessionIgnoresIstiazaWhenBasmalaIsSkipped() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        18|1|بسم الله الرحمن الرحيم الحمد لله الذي أنزل على عبده الكتاب ولم يجعل له عوجا ۜ
        18|2|قيما لينذر بأسا شديدا من لدنه ويبشر المؤمنين الذين يعملون الصالحات أن لهم أجرا حسنا
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 18),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "أعوذ بالله من الشيطان الرجيم الحمد لله الذي أنزل",
            confidence: 0.79,
            chunkSequence: 48
        )

        #expect(locked.type == .locked)
        #expect(locked.reason == "coreml_local_opening_content_lock")
        #expect(locked.ayahRef == "18:1")
        #expect(locked.startRef == "18:1:5")
        #expect(locked.nextExpectedRef == "18:1:9")
        #expect(locked.consumedWords == 4)
    }

    @Test func localQuranSessionDoesNotJumpDeepAfterIstiazaStartupNoise() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        18|1|بسم الله الرحمن الرحيم الحمد لله الذي أنزل على عبده الكتاب ولم يجعل له عوجا ۜ
        18|2|قيما لينذر بأسا شديدا من لدنه ويبشر المؤمنين الذين يعملون الصالحات أن لهم أجرا حسنا
        18|3|ماكثين فيه أبدا
        18|4|وينذر الذين قالوا اتخذ الله ولدا
        18|43|ولم تكن له فئة ينصرونه من دون الله وما كان منتصرا
        18|44|هنالك الولاية لله الحق ۚ هو خير ثوابا وخير عقبا
        18|45|واضرب لهم مثل الحياة الدنيا كماء أنزلناه من السماء فاختلط به نبات الأرض فأصبح هشيما تذروه الرياح ۗ وكان الله على كل شيء مقتدرا
        18|46|المال والبنون زينة الحياة الدنيا ۖ والباقيات الصالحات خير عند ربك ثوابا وخير أملا
        18|47|ويوم نسير الجبال وترى الأرض بارزة وحشرناهم فلم نغادر منهم أحدا
        18|48|وعرضوا على ربك صفا لقد جئتمونا كما خلقناكم أول مرة ۚ بل زعمتم ألن نجعل لكم موعدا
        18|49|ووضع الكتاب فترى المجرمين مشفقين مما فيه ويقولون يا ويلتنا مال هذا الكتاب لا يغادر صغيرة ولا كبيرة إلا أحصاها ۚ ووجدوا ما عملوا حاضرا ۗ ولا يظلم ربك أحدا
        18|50|وإذ قلنا للملائكة اسجدوا لآدم فسجدوا إلا إبليس كان من الجن ففسق عن أمر ربه ۗ أفتتخذونه وذريته أولياء من دوني وهم لكم عدو ۚ بئس للظالمين بدلا
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 18),
            corpus: corpus
        )

        let sparseOpening = session.event(
            transcript: "أَعُوذُ بِاللَّهِ الشَيْطَان الرَّجِيمِزَلَ عَلَى عد الْكتَابَ وَيد",
            confidence: 0.27,
            chunkSequence: 104
        )
        let recoveredOpening = session.event(
            transcript: "أَعُوذُ بِاللَّهِ الشَيْطَان الرَّجِيمِزَلَ عَلَى عد الْكتَابَ وَيدلَهُ عِوَجًا",
            confidence: 0.37,
            chunkSequence: 111
        )

        #expect(sparseOpening.type == .locating)
        #expect(sparseOpening.ayahRef == nil)
        #expect(sparseOpening.reason == "coreml_local_opening_preface_no_match")
        #expect(recoveredOpening.type == .locked)
        #expect(recoveredOpening.reason == "coreml_local_opening_sparse_content_lock")
        #expect(recoveredOpening.ayahRef == "18:1")
        #expect(recoveredOpening.startRef == "18:1:9")
        #expect(recoveredOpening.nextExpectedRef == "18:2:1")
    }

    @Test func localQuranSessionAnchorLocksNoisySurah35LiveTranscript() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        35|1|الحمد لله فاطر السماوات والأرض جاعل الملائكة رسلا أولي أجنحة مثنى وثلاث ورباع يزيد في الخلق ما يشاء إن الله على كل شيء قدير
        35|2|ما يفتح الله للناس من رحمة فلا ممسك لها وما يمسك فلا مرسل له من بعده وهو العزيز الحكيم
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 35),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "أَوْ لَيْنَ شَيْطًا رَِّيمٌحم الْحَمْد لِ فَأاطِرِ سَّمَاوَاتِ وَالْأَرْضِ ج الْمَلَائِكَةِ رسَل أَجْمَحُلَاِيد الْخَلْقِ مَا يَشَاءُ إِنَّ اللَّهَ عَلَى كُلِّ شَيْء قَدِيرٌ",
            confidence: 0.83,
            chunkSequence: 167
        )

        #expect(locked.type == .locked)
        #expect(locked.reason == "coreml_local_anchor_lock")
        #expect(locked.ayahRef == "35:1")
        #expect(locked.ayahText == "الحمد لله فاطر السماوات والأرض جاعل الملائكة رسلا أولي أجنحة مثنى وثلاث ورباع يزيد في الخلق ما يشاء إن الله على كل شيء قدير")
        #expect(locked.startRef == "35:1:1")
        #expect(locked.nextExpectedRef == "35:2:1")
    }

    @Test func localQuranSessionPrefersEarlierSurah80BasmalaAnchorOverShortLaterAyah() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        80|1|بسم الله الرحمن الرحيم عبس وتولى
        80|2|أن جاءه الأعمى
        80|3|وما يدريك لعله يزكى
        80|4|أو يذكر فتنفعه الذكرى
        80|5|أما من استغنى
        80|6|فأنت له تصدى
        80|7|وما عليك ألا يزكى
        80|8|وأما من جاءك يسعى
        80|9|وهو يخشى
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 80),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "عٌ للَّ شَُسْلِ الرَّحْمَنَّحِيم عَب وَوَلَّى أَزاءَهُ الْأَعْْمََى",
            confidence: 0.7485,
            chunkSequence: 62
        )

        #expect(locked.type == .locked)
        #expect(locked.reason == "coreml_local_prefix_lock")
        #expect(locked.ayahRef == "80:1")
        #expect(locked.ayahText == "بسم الله الرحمن الرحيم عبس وتولى")
        #expect(locked.nextExpectedRef == "80:2:1")
    }

    @Test func localQuranSessionPrefixLockDoesNotDragCleanLaterSurah80StartBackward() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        80|1|بسم الله الرحمن الرحيم عبس وتولى
        80|2|أن جاءه الأعمى
        80|3|وما يدريك لعله يزكى
        80|4|أو يذكر فتنفعه الذكرى
        80|5|أما من استغنى
        80|6|فأنت له تصدى
        80|7|وما عليك ألا يزكى
        80|8|وأما من جاءك يسعى
        80|9|وهو يخشى
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 80),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "وأما من جاءك يسعى",
            confidence: 0.92,
            chunkSequence: 104
        )

        #expect(locked.type == .locked)
        #expect(locked.ayahRef == "80:8")
        #expect(locked.startRef == "80:8:1")
        #expect(locked.nextExpectedRef == "80:9:1")
    }

    @Test func localQuranSessionLocksSurah80WhenASRSkipsShortMiddleAyah() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        80|1|بسم الله الرحمن الرحيم عبس وتولى
        80|2|أن جاءه الأعمى
        80|3|وما يدريك لعله يزكى
        80|4|أو يذكر فتنفعه الذكرى
        80|5|أما من استغنى
        80|6|فأنت له تصدى
        80|7|وما عليك ألا يزكى
        80|8|وأما من جاءك يسعى
        80|9|وهو يخشى
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 80),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "َّ عَدَسََبَ تَوَلَّىَهُ يُدْرِيكَ لَعَلَّهُ يَزَّىكَّ",
            confidence: 0.8446,
            chunkSequence: 111
        )

        #expect(locked.type == .locked)
        #expect(locked.reason == "coreml_local_sequence_anchor_lock")
        #expect(locked.ayahRef == "80:1")
        #expect(locked.startRef == "80:1:1")
        #expect(locked.nextExpectedRef == "80:2:1")
    }

    @Test func localQuranSessionDoesNotSkipBeyondNextAyahThroughNoisySurah80CumulativeTranscript() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        80|1|بسم الله الرحمن الرحيم عبس وتولى
        80|2|أن جاءه الأعمى
        80|3|وما يدريك لعله يزكى
        80|4|أو يذكر فتنفعه الذكرى
        80|5|أما من استغنى
        80|6|فأنت له تصدى
        80|7|وما عليك ألا يزكى
        80|8|وأما من جاءك يسعى
        80|9|وهو يخشى
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 80),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "عٌ للَّ شَُسْلِ الرَّحْمَنَّحِيم عَب وَوَلَّى أَزاءَهُ الْأَعْْمََى",
            confidence: 0.7485,
            chunkSequence: 62
        )
        let progressed = session.event(
            transcript: "عٌ للَّ شَُسْلِ الرَّحْمَنَّحِيم عَب وَوَلَّى أَزاءَهُ الْأَعْْمََىًَاَعَلَُّونََّكََّاءَكَ يَسْعَى",
            confidence: 0.6656,
            chunkSequence: 104
        )

        #expect(locked.ayahRef == "80:1")
        #expect(progressed.ayahRef != "80:8")
        #expect(progressed.nextExpectedRef != "80:9:1")
        if let ayahRef = progressed.ayahRef {
            #expect(ayahRef == "80:2")
            #expect(progressed.nextExpectedRef == "80:3:1")
        } else {
            #expect(progressed.candidateRefs == ["80:2"])
        }
    }

    @Test func localQuranSessionDoesNotJumpFromSurah107OpeningToLaterAyahs() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        107|1|بسم الله الرحمن الرحيم أرأيت الذي يكذب بالدين
        107|2|فذلك الذي يدع اليتيم
        107|3|ولا يحض على طعام المسكين
        107|4|فويل للمصلين
        107|5|الذين هم عن صلاتهم ساهون
        107|6|الذين هم يراءون
        107|7|ويمنعون الماعون
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 107),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "بِْمِ الرَّحْمََّحِيم أَرَأَيْتَ الَّذِي كَذَِّين",
            confidence: 0.4721,
            chunkSequence: 41
        )
        let noisyLaterEvidence = session.event(
            transcript: "بِْمِ الرَّحْمََّحِيم أَرَأَيْتَ الَّذِي كَذَِّينَِلِ يَتِينِ يَقِضُّ عَلَى طَعَامِ الْمِْكِين",
            confidence: 0.5362,
            chunkSequence: 76
        )

        #expect(locked.type == .locked)
        #expect(locked.ayahRef == "107:1")
        #expect(noisyLaterEvidence.ayahRef != "107:3")
        #expect(noisyLaterEvidence.ayahRef != "107:4")
        #expect(noisyLaterEvidence.ayahRef != "107:5")
        #expect(noisyLaterEvidence.nextExpectedRef != "107:4:1")
        if noisyLaterEvidence.type == .locating {
            #expect(noisyLaterEvidence.candidateRefs == ["107:1"])
        }
    }

    @Test func localQuranSessionRequiresCurrentAyahCompletionBeforeNextAyahProgress() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        107|1|بسم الله الرحمن الرحيم أرأيت الذي يكذب بالدين
        107|2|فذلك الذي يدع اليتيم
        107|3|ولا يحض على طعام المسكين
        107|4|فويل للمصلين
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 107),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ أَرَأَيْتَ الَّذِي يُكَذِّبُ بِالدِّينِ",
            confidence: 0.92,
            chunkSequence: 48
        )
        let partialAyah2 = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ أَرَأَيْتَ الَّذِي يُكَذِّبُ بِالدِّينِ فَذَلِكَ الَّذِي",
            confidence: 0.81,
            chunkSequence: 62
        )
        let prematureAyah3 = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ أَرَأَيْتَ الَّذِي يُكَذِّبُ بِالدِّينِ فَذَلِكَ الَّذِي وَلَا يَحُضُّ عَلَى طَعَامِ الْمِسْكِينِ",
            confidence: 0.84,
            chunkSequence: 83
        )

        #expect(locked.ayahRef == "107:1")
        #expect(locked.nextExpectedRef == "107:2:1")
        #expect(partialAyah2.type == .progress)
        #expect(partialAyah2.ayahRef == "107:2")
        #expect(partialAyah2.nextExpectedRef == "107:2:3")
        #expect(prematureAyah3.type == .locating)
        #expect(prematureAyah3.reason == "coreml_local_ordered_no_match")
        #expect(prematureAyah3.ayahRef == nil)
        #expect(prematureAyah3.candidateRefs == ["107:2"])
    }

    @Test func localQuranSessionCanRecoverCurrentAyahAfterRejectingPrematureNextAyah() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        107|1|بسم الله الرحمن الرحيم أرأيت الذي يكذب بالدين
        107|2|فذلك الذي يدع اليتيم
        107|3|ولا يحض على طعام المسكين
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 107),
            corpus: corpus
        )

        _ = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ أَرَأَيْتَ الَّذِي يُكَذِّبُ بِالدِّينِ",
            confidence: 0.92,
            chunkSequence: 48
        )
        _ = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ أَرَأَيْتَ الَّذِي يُكَذِّبُ بِالدِّينِ فَذَلِكَ الَّذِي",
            confidence: 0.81,
            chunkSequence: 62
        )
        _ = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ أَرَأَيْتَ الَّذِي يُكَذِّبُ بِالدِّينِ فَذَلِكَ الَّذِي وَلَا يَحُضُّ عَلَى طَعَامِ الْمِسْكِينِ",
            confidence: 0.84,
            chunkSequence: 83
        )
        let recoveredAyah2 = session.event(
            transcript: "فَذَلِكَ الَّذِي يَدُعُّ الْيَتِيمَ",
            confidence: 0.88,
            chunkSequence: 97
        )

        #expect(recoveredAyah2.type == .progress)
        #expect(recoveredAyah2.ayahRef == "107:2")
        #expect(recoveredAyah2.startRef == "107:2:3")
        #expect(recoveredAyah2.nextExpectedRef == "107:3:1")
    }

    @Test func selectedSurahSequenceAnchorLockDoesNotAdvancePastIntermediateAyahs() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        49|1|بسم الله الرحمن الرحيم يا أيها الذين آمنوا لا تقدموا بين يدي الله ورسوله واتقوا الله إن الله سميع عليم
        49|2|يا أيها الذين آمنوا لا ترفعوا أصواتكم فوق صوت النبي ولا تجهروا له بالقول كجهر بعضكم لبعض أن تحبط أعمالكم وأنتم لا تشعرون
        49|3|إن الذين يغضون أصواتهم عند رسول الله أولئك الذين امتحن الله قلوبهم للتقوى لهم مغفرة وأجر عظيم
        49|4|إن الذين ينادونك من وراء الحجرات أكثرهم لا يعقلون
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 49),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "رَسُولِهِ أَصْوَاتَكُمْ النَّبِيِّ يَغُضُّونَ أَصْوَاتَهُمْ رَسُولِ اللَّهِ",
            confidence: 0.72,
            chunkSequence: 55
        )

        #expect(locked.type == .locked)
        #expect(locked.reason == "coreml_local_sequence_anchor_lock")
        #expect(locked.ayahRef == "49:1")
        #expect(locked.nextExpectedRef == "49:2:1")
    }

    @Test func selectedSurahPostLockLongNoisyTranscriptStaysOnCurrentAyahQuickly() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        49|1|بسم الله الرحمن الرحيم يا أيها الذين آمنوا لا تقدموا بين يدي الله ورسوله واتقوا الله إن الله سميع عليم
        49|2|يا أيها الذين آمنوا لا ترفعوا أصواتكم فوق صوت النبي ولا تجهروا له بالقول كجهر بعضكم لبعض أن تحبط أعمالكم وأنتم لا تشعرون
        49|3|إن الذين يغضون أصواتهم عند رسول الله أولئك الذين امتحن الله قلوبهم للتقوى لهم مغفرة وأجر عظيم
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 49),
            corpus: corpus
        )
        let ayah1 = "بسم الله الرحمن الرحيم يا أيها الذين آمنوا لا تقدموا بين يدي الله ورسوله واتقوا الله إن الله سميع عليم"
        let locked = session.event(
            transcript: ayah1,
            confidence: 0.92,
            chunkSequence: 55
        )

        let noisyCumulativeTranscript = Array(repeating: "ضجيج طويل غير مطابق", count: 160)
            .joined(separator: " ")
        let startedAt = Date()
        let event = session.event(
            transcript: "\(ayah1) \(noisyCumulativeTranscript)",
            confidence: 0.31,
            chunkSequence: 349
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(locked.ayahRef == "49:1")
        #expect(locked.nextExpectedRef == "49:2:1")
        #expect(event.type == .locating)
        #expect(event.reason == "coreml_local_ordered_no_match")
        #expect(event.candidateRefs == ["49:2"])
        #expect(elapsed < 0.250)
    }

    @Test func selectedSurahInitialLockKeepsLongNoisyStartupOnBoundedPath() throws {
        var rows = [
            "18|1|بسم الله الرحمن الرحيم الحمد لله الذي أنزل على عبده الكتاب ولم يجعل له عوجا",
            "18|2|قيما لينذر بأسا شديدا من لدنه ويبشر المؤمنين الذين يعملون الصالحات أن لهم أجرا حسنا",
        ]
        let longAyah = "قالوا سبحانك لا علم لنا إلا ما علمتنا إنك أنت العليم الحكيم وجعلنا الليل والنهار آيتين فمحونا آية الليل وجعلنا آية النهار مبصرة"
        for ayahID in 3...260 {
            rows.append("18|\(ayahID)|\(longAyah) \(ayahID)")
        }
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: rows.joined(separator: "\n"))
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 18),
            corpus: corpus
        )

        let startedAt = Date()
        let event = session.event(
            transcript: "الرح أَنَادكتَابُونَ وَ يَتَعْلَُونَ عِوَجًاذَبَأًا شَدِيدًا عََّتِهِمْ سَهُونَغَاءُونَهُونَ",
            confidence: 0.52,
            chunkSequence: 76
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(event.type == .locating)
        #expect(event.ayahRef == nil)
        #expect(elapsed < 0.250)
    }

    @Test func localQuranSessionRecoversLoggedSurah59NextAyahWhenASROmitsOpeningWords() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        59|1|بسم الله الرحمن الرحيم سبح لله ما في السماوات وما في الأرض وهو العزيز الحكيم
        59|2|هو الذي أخرج الذين كفروا من أهل الكتاب من ديارهم لأول الحشر ما ظننتم أن يخرجوا وظنوا أنهم مانعتهم حصونهم من الله فأتاهم الله من حيث لم يحتسبوا وقذف في قلوبهم الرعب يخربون بيوتهم بأيديهم وأيدي المؤمنين فاعتبروا يا أولي الأبصار
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 59),
            corpus: corpus
        )

        let locked = session.event(
            transcript: "بِسْمِ اللَّهِ",
            confidence: 0.8494,
            chunkSequence: 13
        )
        _ = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحِيبّحَ لِلَّهِ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ وَهُوَ الْعَزِيزُ الْحَك",
            confidence: 0.8795,
            chunkSequence: 55
        )
        _ = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحِيبّحَ لِلَّهِ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ وَهُوَ الْعَزِيزُ الْحَكِيمُ",
            confidence: 0.9652,
            chunkSequence: 62
        )
        let recovered = session.event(
            transcript: "بِسْمِ اللَّهِ الرَّحِيبّحَ لِلَّهِ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ وَهُوَ الْعَزِيزُ الْحَكِيمُ أَخْرَجَ الَّذِينَ ك",
            confidence: 0.7621,
            chunkSequence: 76
        )

        #expect(locked.ayahRef == "59:1")
        #expect(recovered.type == .progress)
        #expect(recovered.reason == "coreml_local_ordered_anchor_progress")
        #expect(recovered.ayahRef == "59:2")
        #expect(recovered.startRef == "59:2:3")
        #expect(recovered.nextExpectedRef == "59:2:6")
        #expect(recovered.consumedWords == 3)
    }

    @Test func localQuranSessionRecoversShortSurah18AyahFromSuffixWhenOpeningWordIsMissing() throws {
        let corpus = try CoreMLLocalQuranCorpus.ayahs(fromTanzilText: """
        18|1|بسم الله الرحمن الرحيم الحمد لله الذي أنزل على عبده الكتاب ولم يجعل له عوجا ۜ
        18|2|قيما لينذر بأسا شديدا من لدنه ويبشر المؤمنين الذين يعملون الصالحات أن لهم أجرا حسنا
        18|3|ماكثين فيه أبدا
        18|4|وينذر الذين قالوا اتخذ الله ولدا
        """)
        var session = CoreMLLocalQuranSession(
            scope: .selectedSurah(id: 18),
            corpus: corpus
        )

        let ayah1 = "بسم الله الرحمن الرحيم الحمد لله الذي أنزل على عبده الكتاب ولم يجعل له عوجا"
        let ayah2 = "قيما لينذر بأسا شديدا من لدنه ويبشر المؤمنين الذين يعملون الصالحات أن لهم أجرا حسنا"
        let locked = session.event(
            transcript: ayah1,
            confidence: 0.92,
            chunkSequence: 62
        )
        let progressedToAyah2 = session.event(
            transcript: "\(ayah1) \(ayah2)",
            confidence: 0.83,
            chunkSequence: 125
        )
        let singleSuffixWord = session.event(
            transcript: "\(ayah1) \(ayah2) فِي",
            confidence: 0.52,
            chunkSequence: 139
        )
        let recoveredShortAyah = session.event(
            transcript: "\(ayah1) \(ayah2) فِي أبٍ",
            confidence: 0.77,
            chunkSequence: 146
        )

        #expect(locked.ayahRef == "18:1")
        #expect(progressedToAyah2.ayahRef == "18:2")
        #expect(progressedToAyah2.nextExpectedRef == "18:3:1")
        #expect(singleSuffixWord.type == .locating)
        #expect(singleSuffixWord.reason == "coreml_local_ordered_no_match")
        #expect(recoveredShortAyah.type == .progress)
        #expect(recoveredShortAyah.reason == "coreml_local_short_ayah_suffix_progress")
        #expect(recoveredShortAyah.ayahRef == "18:3")
        #expect(recoveredShortAyah.startRef == "18:3:2")
        #expect(recoveredShortAyah.nextExpectedRef == "18:4:1")
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

private final class ManualAudioStreamer: AudioStreaming, @unchecked Sendable {
    private var onChunk: (@Sendable (Data, Int) -> Void)?

    func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws {
        self.onChunk = onChunk
    }

    func stop() {
        onChunk = nil
    }

    func emit(pcm: Data, sampleRate: Int) async {
        onChunk?(pcm, sampleRate)
        await Task.yield()
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

private func pcm16Data(_ samples: [Int16]) -> Data {
    var data = Data()
    for sample in samples {
        data.appendInt16LE(sample)
    }
    return data
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

private func activeSpeechMetrics(event: VoiceActivityEvent?) -> CoreMLFastConformerAudioWindowMetrics {
    var observations = Array(
        repeating: VoiceActivityPayload(probability: 0.86, isSpeechActive: true, event: nil),
        count: 6
    )
    observations.append(
        VoiceActivityPayload(
            probability: 0.82,
            isSpeechActive: event != .speechEnd,
            event: event
        )
    )
    return CoreMLFastConformerAudioWindowMetrics(
        samples: Array(repeating: 0.025, count: 17_920),
        voiceActivity: observations
    )
}

private func quietMetrics() -> CoreMLFastConformerAudioWindowMetrics {
    CoreMLFastConformerAudioWindowMetrics(
        samples: Array(repeating: 0.001, count: 17_920),
        voiceActivity: [
            VoiceActivityPayload(probability: 0.05, isSpeechActive: false, event: nil),
        ]
    )
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
