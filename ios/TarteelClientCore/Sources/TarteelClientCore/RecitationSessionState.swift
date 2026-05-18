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

    public init(
        phase: RecitationPhase = .idle,
        currentAyahRef: String? = nil,
        headline: String = "Ready",
        detail: String = "Tap the mic to begin"
    ) {
        self.phase = phase
        self.currentAyahRef = currentAyahRef
        self.headline = headline
        self.detail = detail
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
                detail: event.transcript
            )
        case .progress:
            return RecitationSessionState(
                phase: .listening,
                currentAyahRef: currentAyahRef,
                headline: "Continue",
                detail: event.transcript
            )
        case .wrong:
            return RecitationSessionState(
                phase: .needsCorrection,
                currentAyahRef: currentAyahRef,
                headline: "Correction needed",
                detail: correctionDetail(for: event)
            )
        case .uncertain:
            return RecitationSessionState(
                phase: .uncertain,
                currentAyahRef: currentAyahRef,
                headline: "Keep reciting",
                detail: event.transcript
            )
        case .lockCandidate:
            return RecitationSessionState(
                phase: .connecting,
                currentAyahRef: currentAyahRef,
                headline: "Finding your place",
                detail: event.candidateRefs.joined(separator: ", ")
            )
        case .locating:
            return RecitationSessionState(
                phase: .connecting,
                currentAyahRef: currentAyahRef,
                headline: "Listening",
                detail: event.transcript
            )
        }
    }

    private func bufferingState(for event: RecitationEvent) -> RecitationSessionState {
        if currentAyahRef != nil {
            return RecitationSessionState(
                phase: .listening,
                currentAyahRef: currentAyahRef,
                headline: "Listening",
                detail: "Keep reciting"
            )
        }

        return RecitationSessionState(
            phase: .connecting,
            currentAyahRef: currentAyahRef,
            headline: "Gathering audio",
            detail: "Keep reciting"
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
