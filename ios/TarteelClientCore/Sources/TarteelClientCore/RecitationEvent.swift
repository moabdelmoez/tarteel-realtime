import Foundation

public enum RecitationEventType: String, Codable, Sendable {
    case locating
    case lockCandidate = "lock_candidate"
    case locked
    case progress
    case wrong
    case uncertain
}

public struct RecitationEvent: Codable, Equatable, Sendable {
    public let type: RecitationEventType
    public let transcript: String
    public let confidence: Double
    public let chunkSequence: Int?
    public let reason: String?
    public let sessionId: String?
    public let candidateRefs: [String]
    public let ayahText: String?
    public let ayahRef: String?
    public let startRef: String?
    public let nextExpectedRef: String?
    public let consumedWords: Int
    public let expectedRef: String?
    public let expectedWord: String?
    public let recognizedWord: String?

    public init(
        type: RecitationEventType,
        transcript: String,
        confidence: Double,
        chunkSequence: Int?,
        reason: String?,
        sessionId: String? = nil,
        candidateRefs: [String],
        ayahText: String? = nil,
        ayahRef: String?,
        startRef: String?,
        nextExpectedRef: String?,
        consumedWords: Int,
        expectedRef: String?,
        expectedWord: String?,
        recognizedWord: String?
    ) {
        self.type = type
        self.transcript = transcript
        self.confidence = confidence
        self.chunkSequence = chunkSequence
        self.reason = reason
        self.sessionId = sessionId
        self.candidateRefs = candidateRefs
        self.ayahText = ayahText
        self.ayahRef = ayahRef
        self.startRef = startRef
        self.nextExpectedRef = nextExpectedRef
        self.consumedWords = consumedWords
        self.expectedRef = expectedRef
        self.expectedWord = expectedWord
        self.recognizedWord = recognizedWord
    }

    public var isBlockingCorrection: Bool {
        type == .wrong
    }

    public var isWaitingForAudioBuffer: Bool {
        reason == "waiting_for_audio_buffer"
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case transcript
        case confidence
        case chunkSequence = "chunk_sequence"
        case reason
        case sessionId = "session_id"
        case candidateRefs = "candidate_refs"
        case ayahText = "ayah_text"
        case ayahRef = "ayah_ref"
        case startRef = "start_ref"
        case nextExpectedRef = "next_expected_ref"
        case consumedWords = "consumed_words"
        case expectedRef = "expected_ref"
        case expectedWord = "expected_word"
        case recognizedWord = "recognized_word"
    }
}
