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
    public let headline: String
    public let detail: String
    public let lastEventType: RecitationEventType?
    public let lastEventReason: String?
    public let lastTranscript: String
    public let lastChunkSequence: Int?

    public init(
        phase: RecitationPhase = .idle,
        currentAyahRef: String? = nil,
        headline: String = "Ready",
        detail: String = "Tap the mic to begin",
        lastEventType: RecitationEventType? = nil,
        lastEventReason: String? = nil,
        lastTranscript: String = "",
        lastChunkSequence: Int? = nil
    ) {
        self.phase = phase
        self.currentAyahRef = currentAyahRef
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

    public var debugTranscriptText: String {
        lastTranscript.isEmpty ? "none" : lastTranscript
    }

    public func applying(_ event: RecitationEvent) -> RecitationSessionState {
        if event.isWaitingForAudioBuffer {
            return bufferingState(for: event)
        }

        switch event.type {
        case .locked:
            let ref = event.ayahRef ?? event.startRef ?? "unknown"
            return RecitationSessionState(
                phase: .listening,
                currentAyahRef: event.ayahRef,
                headline: "Locked on \(ref)",
                detail: event.transcript,
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .progress:
            return RecitationSessionState(
                phase: .listening,
                currentAyahRef: currentAyahRef,
                headline: "Continue",
                detail: event.transcript,
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .wrong:
            return RecitationSessionState(
                phase: .needsCorrection,
                currentAyahRef: currentAyahRef,
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
                headline: "Keep reciting",
                detail: event.transcript,
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .lockCandidate:
            return RecitationSessionState(
                phase: .connecting,
                currentAyahRef: currentAyahRef,
                headline: "Finding your place",
                detail: event.candidateRefs.joined(separator: ", "),
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        case .locating:
            return RecitationSessionState(
                phase: .connecting,
                currentAyahRef: currentAyahRef,
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
                headline: "Listening",
                detail: "Keep reciting",
                lastEventType: event.type,
                lastEventReason: event.reason,
                lastTranscript: event.transcript,
                lastChunkSequence: event.chunkSequence
            )
        }

        return RecitationSessionState(
            phase: .connecting,
            currentAyahRef: currentAyahRef,
            headline: "Gathering audio",
            detail: "Keep reciting",
            lastEventType: event.type,
            lastEventReason: event.reason,
            lastTranscript: event.transcript,
            lastChunkSequence: event.chunkSequence
        )
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
}
