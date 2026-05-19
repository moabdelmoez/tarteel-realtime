import Foundation

public struct AudioChunkPayload: Encodable, Equatable, Sendable {
    public let sequenceNumber: Int
    public let pcm: Data
    public let sampleRateHz: Int
    public let voiceActivity: VoiceActivityPayload?

    public init(
        sequenceNumber: Int,
        pcm: Data,
        sampleRateHz: Int,
        voiceActivity: VoiceActivityPayload? = nil
    ) {
        self.sequenceNumber = sequenceNumber
        self.pcm = pcm
        self.sampleRateHz = sampleRateHz
        self.voiceActivity = voiceActivity
    }

    private enum CodingKeys: String, CodingKey {
        case sequenceNumber = "sequence_number"
        case pcmBase64 = "pcm_base64"
        case sampleRateHz = "sample_rate_hz"
        case voiceActivity = "voice_activity"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequenceNumber, forKey: .sequenceNumber)
        try container.encode(pcm.base64EncodedString(), forKey: .pcmBase64)
        try container.encode(sampleRateHz, forKey: .sampleRateHz)
        try container.encodeIfPresent(voiceActivity, forKey: .voiceActivity)
    }
}
