import Foundation

public enum VoiceActivityEvent: String, Codable, Equatable, Sendable {
    case speechStart = "speech_start"
    case speechEnd = "speech_end"
}

public struct VoiceActivityPayload: Codable, Equatable, Sendable {
    public let probability: Double
    public let isSpeechActive: Bool
    public let event: VoiceActivityEvent?

    public init(
        probability: Double,
        isSpeechActive: Bool,
        event: VoiceActivityEvent?
    ) {
        self.probability = probability
        self.isSpeechActive = isSpeechActive
        self.event = event
    }

    private enum CodingKeys: String, CodingKey {
        case probability
        case isSpeechActive = "is_speech_active"
        case event
    }
}
