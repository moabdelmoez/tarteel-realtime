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
        #expect(locked.nextExpectedRef == "80:3:1")
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
        #expect(locked.nextExpectedRef == "80:4:1")
    }

    @Test func localQuranSessionProgressesForwardThroughNoisySurah80CumulativeTranscript() throws {
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
        #expect(progressed.type == .progress)
        #expect(progressed.reason == "coreml_local_ordered_forward_progress")
        #expect(progressed.ayahRef == "80:8")
        #expect(progressed.startRef == "80:8:1")
        #expect(progressed.nextExpectedRef == "80:9:1")
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
