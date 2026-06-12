import Foundation

public enum RecitationPhase: String, Equatable, Sendable {
    case idle
    case connecting
    case listening
    case needsCorrection
    case uncertain
    case stopped
}

public struct RecitationSessionState: Equatable, Sendable {
    public let phase: RecitationPhase
    public let currentAyahRef: String?
    public let currentAyahText: String?
    public let nextExpectedRef: String?
    public let currentAyahWords: [String]
    public let completedWordCount: Int
    public let headline: String
    public let detail: String
    public let lastEventType: RecitationEventType?
    public let lastEventReason: String?
    public let lastTranscript: String
    public let lastChunkSequence: Int?

    public init(
        phase: RecitationPhase = .idle,
        currentAyahRef: String? = nil,
        currentAyahText: String? = nil,
        nextExpectedRef: String? = nil,
        currentAyahWords: [String] = [],
        completedWordCount: Int = 0,
        headline: String = "Ready",
        detail: String = "Tap the mic to begin",
        lastEventType: RecitationEventType? = nil,
        lastEventReason: String? = nil,
        lastTranscript: String = "",
        lastChunkSequence: Int? = nil
    ) {
        self.phase = phase
        self.currentAyahRef = currentAyahRef
        self.currentAyahText = currentAyahText
        self.nextExpectedRef = nextExpectedRef
        self.currentAyahWords = currentAyahWords
        self.completedWordCount = completedWordCount
        self.headline = headline
        self.detail = detail
        self.lastEventType = lastEventType
        self.lastEventReason = lastEventReason
        self.lastTranscript = lastTranscript
        self.lastChunkSequence = lastChunkSequence
    }

    public var debugLastEventText: String {
        guard let lastEventType else { return "none" }
        guard let lastEventReason, !lastEventReason.isEmpty else {
            return lastEventType.rawValue
        }
        return "\(lastEventType.rawValue) (\(lastEventReason))"
    }

    public var debugAyahText: String {
        currentAyahRef ?? "none"
    }

    public var debugAyahBodyText: String {
        currentAyahText ?? "none"
    }

    public var debugNextExpectedText: String {
        nextExpectedRef ?? "none"
    }

    public var debugTranscriptText: String {
        lastTranscript.isEmpty ? "none" : lastTranscript
    }

    public func applying(_ event: RecitationEvent) -> RecitationSessionState {
        if event.isWaitingForAudioBuffer {
            if currentAyahRef != nil, lastEventType != nil {
                return self
            }
            if lastEventReason == "waiting_for_audio_buffer" {
                return self
            }
            if phase == .connecting, lastEventType != nil {
                return self
            }
            return bufferingState(for: event)
        }

        switch event.type {
        case .locked:
            let ref = event.ayahRef ?? event.startRef ?? "unknown"
            let ayahText = event.ayahText ?? event.transcript
            let progress = progressFields(
                ayahRef: event.ayahRef,
                ayahText: ayahText,
                event: event
            )
            return RecitationSessionState(
                phase: .listening,
                currentAyahRef: event.ayahRef,
                currentAyahText: ayahText.isEmpty ? nil : ayahText,
                nextExpectedRef: progress.nextExpectedRef,
                currentAyahWords: progress.currentAyahWords,
                completedWordCount: progress.completedWordCount,
                headline: "Locked on \(ref)",
                detail: ayahText,
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .progress:
            let progressAyahRef = event.ayahRef ?? currentAyahRef
            let progressAyahText = event.ayahText ?? currentAyahText
            let progress = progressFields(
                ayahRef: progressAyahRef,
                ayahText: progressAyahText,
                event: event
            )
            return RecitationSessionState(
                phase: .listening,
                currentAyahRef: progressAyahRef,
                currentAyahText: progressAyahText,
                nextExpectedRef: progress.nextExpectedRef,
                currentAyahWords: progress.currentAyahWords,
                completedWordCount: progress.completedWordCount,
                headline: progressAyahRef.map { "Ayah \($0)" } ?? "Continue",
                detail: progressAyahText ?? event.transcript,
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .wrong:
            return RecitationSessionState(
                phase: .needsCorrection,
                currentAyahRef: currentAyahRef,
                currentAyahText: currentAyahText,
                nextExpectedRef: event.nextExpectedRef ?? nextExpectedRef,
                currentAyahWords: currentAyahWords,
                completedWordCount: completedWordCount,
                headline: "Correction needed",
                detail: correctionDetail(for: event),
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .uncertain:
            return RecitationSessionState(
                phase: .uncertain,
                currentAyahRef: currentAyahRef,
                currentAyahText: currentAyahText,
                nextExpectedRef: event.nextExpectedRef ?? nextExpectedRef,
                currentAyahWords: currentAyahWords,
                completedWordCount: completedWordCount,
                headline: "Keep reciting",
                detail: currentAyahText ?? event.transcript,
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .lockCandidate:
            return RecitationSessionState(
                phase: .connecting,
                currentAyahRef: currentAyahRef,
                currentAyahText: currentAyahText,
                nextExpectedRef: event.nextExpectedRef ?? nextExpectedRef,
                currentAyahWords: currentAyahWords,
                completedWordCount: completedWordCount,
                headline: "Finding your place",
                detail: event.candidateRefs.joined(separator: ", "),
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .locating:
            if currentAyahRef != nil || currentAyahText != nil {
                return RecitationSessionState(
                    phase: .listening,
                    currentAyahRef: currentAyahRef,
                    currentAyahText: currentAyahText,
                    nextExpectedRef: event.nextExpectedRef ?? nextExpectedRef,
                    currentAyahWords: currentAyahWords,
                    completedWordCount: completedWordCount,
                    headline: stableLocatedHeadline,
                    detail: currentAyahText ?? event.transcript,
                    lastEventType: event.type,
                    lastEventReason: event.reason,
                    lastTranscript: event.transcript,
                    lastChunkSequence: event.chunkSequence
                )
            }
            return RecitationSessionState(
                phase: .connecting,
                currentAyahRef: currentAyahRef,
                currentAyahText: currentAyahText,
                nextExpectedRef: event.nextExpectedRef ?? nextExpectedRef,
                currentAyahWords: currentAyahWords,
                completedWordCount: completedWordCount,
                headline: "Listening",
                detail: event.transcript,
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        }
    }

    private func bufferingState(for event: RecitationEvent) -> RecitationSessionState {
        if currentAyahRef != nil {
            return RecitationSessionState(
                phase: .listening,
                currentAyahRef: currentAyahRef,
                currentAyahText: currentAyahText,
                nextExpectedRef: event.nextExpectedRef ?? nextExpectedRef,
                currentAyahWords: currentAyahWords,
                completedWordCount: completedWordCount,
                headline: stableLocatedHeadline,
                detail: currentAyahText ?? "Keep reciting",
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        }

        return RecitationSessionState(
            phase: .connecting,
            currentAyahRef: currentAyahRef,
            currentAyahText: currentAyahText,
            nextExpectedRef: event.nextExpectedRef ?? nextExpectedRef,
            currentAyahWords: currentAyahWords,
            completedWordCount: completedWordCount,
            headline: "Gathering audio",
            detail: "Keep reciting",
            lastEventType: event.type,
            lastEventReason: event.reason,
            lastTranscript: event.transcript,
            lastChunkSequence: event.chunkSequence
        )
    }

    private var stableLocatedHeadline: String {
        if headline.hasPrefix("Ayah ") || headline.hasPrefix("Locked on ") {
            return headline
        }
        return "Listening"
    }

    private func correctionDetail(for event: RecitationEvent) -> String {
        guard let expectedWord = event.expectedWord else {
            return "Please repeat the last phrase"
        }
        guard let recognizedWord = event.recognizedWord else {
            return "Expected \(expectedWord)"
        }
        return "Expected \(expectedWord), heard \(recognizedWord)"
    }

    private func progressFields(
        ayahRef: String?,
        ayahText: String?,
        event: RecitationEvent
    ) -> (nextExpectedRef: String?, currentAyahWords: [String], completedWordCount: Int) {
        let words = Self.words(in: ayahText)
        let nextExpectedRef = event.nextExpectedRef
        let completedWordCount = Self.completedWordCount(
            ayahRef: ayahRef,
            wordCount: words.count,
            startRef: event.startRef,
            nextExpectedRef: nextExpectedRef,
            consumedWords: event.consumedWords
        )
        return (nextExpectedRef, words, completedWordCount)
    }

    private static func words(in text: String?) -> [String] {
        guard let text else { return [] }
        return text.split(separator: " ").map(String.init)
    }

    private static func completedWordCount(
        ayahRef: String?,
        wordCount: Int,
        startRef: String?,
        nextExpectedRef: String?,
        consumedWords: Int
    ) -> Int {
        guard wordCount > 0 else { return 0 }
        if ayahRefPrefix(nextExpectedRef) == ayahRef,
           let nextWordIndex = wordIndex(nextExpectedRef) {
            return min(wordCount, max(0, nextWordIndex - 1))
        }
        if ayahRefPrefix(startRef) == ayahRef,
           let startWordIndex = wordIndex(startRef),
           consumedWords > 0 {
            return min(wordCount, max(0, startWordIndex + consumedWords - 1))
        }
        if nextExpectedRef == nil || ayahRefPrefix(nextExpectedRef) != ayahRef {
            return wordCount
        }
        return 0
    }

    private static func ayahRefPrefix(_ ref: String?) -> String? {
        guard let ref else { return nil }
        let parts = ref.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0]):\(parts[1])"
    }

    private static func wordIndex(_ ref: String?) -> Int? {
        guard let ref else { return nil }
        let parts = ref.split(separator: ":")
        guard parts.count == 3 else { return nil }
        return Int(parts[2])
    }
}
