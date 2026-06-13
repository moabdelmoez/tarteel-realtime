import Foundation

enum CoreMLLocalQuranEventReason: String, CaseIterable, Sendable {
    case noWords = "coreml_local_no_words"
    case insufficientContext = "coreml_local_insufficient_context"
    case noMatch = "coreml_local_no_match"
    case orderedNoMatch = "coreml_local_ordered_no_match"
    case spanMatch = "coreml_local_span_match"
    case tolerantMatch = "coreml_local_tolerant_match"
    case orderedProgress = "coreml_local_ordered_progress"
    case orderedForwardProgress = "coreml_local_ordered_forward_progress"
    case orderedAnchorProgress = "coreml_local_ordered_anchor_progress"
    case nextAyahTailSkipProgress = "coreml_local_next_ayah_tail_skip_progress"
    case shortAyahSuffixProgress = "coreml_local_short_ayah_suffix_progress"
    case shortAyahFinalWordProgress = "coreml_local_short_ayah_final_word_progress"
    case openingBasmalaLock = "coreml_local_opening_basmala_lock"
    case openingContentLock = "coreml_local_opening_content_lock"
    case openingPrefaceNoMatch = "coreml_local_opening_preface_no_match"
    case openingSparseContentLock = "coreml_local_opening_sparse_content_lock"
    case openingFusedLock = "coreml_local_opening_fused_lock"
    case sequenceAnchorLock = "coreml_local_sequence_anchor_lock"
    case anchorLock = "coreml_local_anchor_lock"
    case prefixLock = "coreml_local_prefix_lock"
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
    private static let nextAyahTailSkipMinimumCurrentAyahWords = 8
    private static let nextAyahTailSkipMinimumCompletedCoverage = 0.70
    private static let nextAyahTailSkipMaximumRemainingWords = 6
    private static let nextAyahTailSkipMinimumMatchedWords = 4
    private static let nextAyahTailSkipMinimumScore = 0.78
    private static let nextAyahTailSkipMaximumStartWordIndex = 4
    private static let orderedAnchorProgressMaximumWords = 6
    private static let orderedAnchorProgressMinimumStrongMatches = 2
    private static let shortAyahSuffixMaximumExpectedWords = 4
    private static let shortAyahSuffixMinimumWords = 2
    private static let shortAyahSuffixMaximumRecentWords = 4
    private static let shortAyahSuffixMinimumMeanScore = 0.70
    private static let shortAyahFinalWordExpectedWords = 4
    private static let shortAyahFinalWordMinimumCharacters = 5
    private static let shortAyahFinalWordMaximumRecentWords = 6
    private static let shortAyahFinalWordMinimumScore = 0.86
    private static let openingBasmalaWords = ["بسم", "الله", "الرحمن", "الرحيم"]
    private static let openingBasmalaMinimumWords = 2
    private static let openingBasmalaMinimumMeanScore = 0.72
    private static let openingSparseContentMinimumStrongMatches = 3
    private static let openingSparseContentMinimumMeanScore = 0.74
    private static let openingFusedMinimumOpeningMatches = 2
    private static let openingFusedMaximumFirstAyahWords = 8
    private static let openingFusedMinimumCharacters = 8
    private static let openingFusedMaximumCharacters = 72
    private static let openingFusedMinimumMeanScore = 0.72

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
           let match = shortAyahFinalWordProgressMatch(recognizedWords: recognizedWords) {
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

        if currentAyahIndex != nil,
           let match = nextAyahTailSkipProgressMatch(recognizedWords: recognizedWords) {
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
                reason: recognizedWords.isEmpty ? .noWords : .orderedNoMatch,
                candidateRefs: orderedCandidateRefs()
            )
        }

        guard recognizedWords.count >= Self.minimumRecognizedWords else {
            return RecitationEvent.coreMLTranscript(
                transcript: transcript,
                confidence: confidence,
                chunkSequence: chunkSequence,
                reason: recognizedWords.isEmpty ? .noWords : .insufficientContext
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
                reason: .openingPrefaceNoMatch,
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
            .filter { $0.score >= Self.tolerantMatchThreshold || $0.reason == .spanMatch }
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
            reason: .noMatch,
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

        if let fusedOpeningMatch = selectedSurahOpeningFusedMatch(normalizedTranscript: normalizedTranscript) {
            return lockInitialSelectedSurahMatch(
                fusedOpeningMatch,
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
            reason: .noMatch,
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
                        reason: .openingBasmalaLock,
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
        )?.with(reason: .openingContentLock)
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
            reason: .openingSparseContentLock,
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

    private func selectedSurahOpeningFusedMatch(normalizedTranscript: String) -> CoreMLLocalQuranMatch? {
        guard allowsAnchorLock,
              let firstAyahIndex = ayahs.indices.first else {
            return nil
        }

        let ayah = ayahs[firstAyahIndex]
        let expectedWords = Self.words(in: ayah.normalizedText)
        let basmalaPrefixLength = Self.openingBasmalaPrefixLength(in: expectedWords)
        guard basmalaPrefixLength >= Self.openingBasmalaMinimumWords,
              basmalaPrefixLength < expectedWords.count,
              expectedWords.count <= Self.openingFusedMaximumFirstAyahWords else {
            return nil
        }

        return Self.openingFusedMatch(
            ayah: ayah,
            ayahIndex: firstAyahIndex,
            expectedWords: expectedWords,
            contentStartIndex: basmalaPrefixLength,
            normalizedTranscript: normalizedTranscript
        )
    }

    private static func openingFusedMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        expectedWords: [String],
        contentStartIndex: Int,
        normalizedTranscript: String
    ) -> CoreMLLocalQuranMatch? {
        let actualCharacters = compactCharacters(normalizedTranscript)
        guard actualCharacters.count >= openingFusedMinimumCharacters,
              actualCharacters.count <= openingFusedMaximumCharacters,
              expectedWords.indices.contains(contentStartIndex) else {
            return nil
        }

        let matches = expectedWords.indices.compactMap { expectedIndex -> (expectedIndex: Int, score: Double)? in
            guard let score = openingFusedWordScore(
                expected: expectedWords[expectedIndex],
                actualCharacters: actualCharacters,
                isContentWord: expectedIndex >= contentStartIndex
            ) else {
                return nil
            }
            return (expectedIndex, score)
        }

        let openingMatches = matches.filter { $0.expectedIndex < contentStartIndex }
        let contentMatches = matches.filter { $0.expectedIndex >= contentStartIndex }
        guard openingMatches.count >= openingFusedMinimumOpeningMatches,
              let lastContentMatch = contentMatches.max(by: { $0.expectedIndex < $1.expectedIndex }) else {
            return nil
        }

        let evidence = openingMatches + contentMatches
        let meanScore = evidence.reduce(0.0) { $0 + $1.score } / Double(evidence.count)
        guard meanScore >= openingFusedMinimumMeanScore else {
            return nil
        }

        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            score: meanScore,
            reason: .openingFusedLock,
            startWordIndex: 1,
            matchedWords: lastContentMatch.expectedIndex + 1
        )
    }

    private static func openingFusedWordScore(
        expected: String,
        actualCharacters: [Character],
        isContentWord: Bool
    ) -> Double? {
        let expectedVariants = anchorWordSimilarityVariants(compactCharacters(expected))
        let minimumPrefixLength = isContentWord ? 3 : 2
        var best: Double?

        for expectedCharacters in expectedVariants where expectedCharacters.count >= minimumPrefixLength {
            if containsContiguous(expectedCharacters, in: actualCharacters) {
                best = max(best ?? 0, 1.0)
                continue
            }

            let maximumPrefix = min(expectedCharacters.count, actualCharacters.count)
            guard maximumPrefix >= minimumPrefixLength else { continue }
            for prefixLength in stride(from: maximumPrefix, through: minimumPrefixLength, by: -1) {
                let prefix = Array(expectedCharacters.prefix(prefixLength))
                guard containsContiguous(prefix, in: actualCharacters) else { continue }
                let coverage = Double(prefixLength) / Double(expectedCharacters.count)
                guard coverage >= 0.50 else { continue }
                best = max(best ?? 0, 0.68 + (0.24 * coverage))
                break
            }
        }

        return best
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
            reason: .sequenceAnchorLock,
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
                guard match.score >= Self.tolerantMatchThreshold || match.reason == .spanMatch else {
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
            reason: .prefixLock,
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
            reason: .anchorLock,
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
            guard match.score >= Self.tolerantMatchThreshold || match.reason == .spanMatch else {
                return nil
            }
            return match.with(reason: .orderedProgress)
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

    private func shortAyahFinalWordProgressMatch(recognizedWords: [String]) -> CoreMLLocalQuranMatch? {
        guard let nextExpectedRef,
              allowsAnchorLock,
              nextExpectedRef.wordIndex == 1,
              !recognizedWords.isEmpty,
              let ayahIndex = ayahs.firstIndex(where: { $0.ref == nextExpectedRef.ayahRef }) else {
            return nil
        }

        let candidateWords = recentPostLockWords(from: recognizedWords)
        guard !candidateWords.isEmpty else { return nil }
        return Self.shortAyahFinalWordProgressMatch(
            ayah: ayahs[ayahIndex],
            ayahIndex: ayahIndex,
            recognizedWords: candidateWords
        )
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

    private func nextAyahTailSkipProgressMatch(recognizedWords: [String]) -> CoreMLLocalQuranMatch? {
        guard let nextExpectedRef,
              allowsAnchorLock,
              !recognizedWords.isEmpty,
              let currentIndex = ayahs.firstIndex(where: { $0.ref == nextExpectedRef.ayahRef }) else {
            return nil
        }

        let currentWords = Self.words(in: ayahs[currentIndex].normalizedText)
        guard currentWords.count >= Self.nextAyahTailSkipMinimumCurrentAyahWords,
              nextExpectedRef.wordIndex <= currentWords.count else {
            return nil
        }

        let completedWords = max(nextExpectedRef.wordIndex - 1, 0)
        let remainingWords = max(currentWords.count - completedWords, 0)
        let completedCoverage = Double(completedWords) / Double(currentWords.count)
        guard completedCoverage >= Self.nextAyahTailSkipMinimumCompletedCoverage,
              remainingWords <= Self.nextAyahTailSkipMaximumRemainingWords else {
            return nil
        }

        let nextIndex = ayahs.index(after: currentIndex)
        guard ayahs.indices.contains(nextIndex) else { return nil }
        let candidateWords = boundedPostLockWords(from: recognizedWords)
        guard !candidateWords.isEmpty else { return nil }
        return Self.nextAyahTailSkipProgressMatch(
            ayah: ayahs[nextIndex],
            ayahIndex: nextIndex,
            recognizedWords: candidateWords
        )
    }

    private static func nextAyahTailSkipProgressMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String]
    ) -> CoreMLLocalQuranMatch? {
        guard let match = orderedAnchorProgressMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            recognizedWords: recognizedWords,
            minimumStartWordIndex: 1
        ),
              match.startWordIndex <= nextAyahTailSkipMaximumStartWordIndex,
              match.matchedWords >= nextAyahTailSkipMinimumMatchedWords,
              match.score >= nextAyahTailSkipMinimumScore else {
            return nil
        }
        return match.with(reason: .nextAyahTailSkipProgress)
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
            reason: .orderedAnchorProgress,
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
                reason: .shortAyahSuffixProgress,
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

    private static func shortAyahFinalWordProgressMatch(
        ayah: CoreMLLocalQuranAyah,
        ayahIndex: Int,
        recognizedWords: [String]
    ) -> CoreMLLocalQuranMatch? {
        let expectedWords = words(in: ayah.normalizedText)
        guard expectedWords.count == shortAyahFinalWordExpectedWords,
              let expectedFinalWord = expectedWords.last,
              compactCharacters(expectedFinalWord).count >= shortAyahFinalWordMinimumCharacters,
              !recognizedWords.isEmpty else {
            return nil
        }

        let recentWords = Array(recognizedWords.suffix(shortAyahFinalWordMaximumRecentWords))
        let scores = recentWords.map {
            shortAyahSuffixWordScore(expected: expectedFinalWord, actual: $0)
        }
        guard let bestScore = scores.max(),
              bestScore >= shortAyahFinalWordMinimumScore else {
            return nil
        }

        return CoreMLLocalQuranMatch(
            ayah: ayah,
            ayahIndex: ayahIndex,
            score: bestScore,
            reason: .shortAyahFinalWordProgress,
            startWordIndex: expectedWords.count,
            matchedWords: 1
        )
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
            reason: .orderedForwardProgress,
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
            reason: .tolerantMatch,
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
                reason: .spanMatch,
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
                reason: .spanMatch,
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

    private static func containsContiguous(_ needle: [Character], in haystack: [Character]) -> Bool {
        guard !needle.isEmpty,
              needle.count <= haystack.count else {
            return false
        }

        if needle.count == haystack.count {
            return needle == haystack
        }

        for startIndex in 0...(haystack.count - needle.count) {
            let endIndex = startIndex + needle.count
            if Array(haystack[startIndex..<endIndex]) == needle {
                return true
            }
        }
        return false
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
    let reason: CoreMLLocalQuranEventReason
    let startWordIndex: Int
    let matchedWords: Int

    func with(reason: CoreMLLocalQuranEventReason) -> CoreMLLocalQuranMatch {
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

private extension RecitationEvent {
    static func coreMLTranscript(
        transcript: String,
        confidence: Double,
        chunkSequence: Int,
        reason: CoreMLLocalQuranEventReason,
        candidateRefs: [String] = []
    ) -> RecitationEvent {
        RecitationEvent(
            type: .locating,
            transcript: transcript,
            confidence: confidence,
            chunkSequence: chunkSequence,
            reason: reason.rawValue,
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
            reason: match.reason.rawValue,
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
