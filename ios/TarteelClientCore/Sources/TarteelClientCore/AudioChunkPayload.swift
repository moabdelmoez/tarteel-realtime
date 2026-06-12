import Dispatch
import Foundation

public struct AudioChunkLatencyTrace: Equatable, Sendable {
    public let receivedAtNanoseconds: UInt64
    public let queuedForSendAtNanoseconds: UInt64?
    public let voiceActivityFinishedAtNanoseconds: UInt64?
    public let sendFinishedAtNanoseconds: UInt64?

    public init(
        receivedAtNanoseconds: UInt64 = Self.nowNanoseconds(),
        queuedForSendAtNanoseconds: UInt64? = nil,
        voiceActivityFinishedAtNanoseconds: UInt64? = nil,
        sendFinishedAtNanoseconds: UInt64? = nil
    ) {
        self.receivedAtNanoseconds = receivedAtNanoseconds
        self.queuedForSendAtNanoseconds = queuedForSendAtNanoseconds
        self.voiceActivityFinishedAtNanoseconds = voiceActivityFinishedAtNanoseconds
        self.sendFinishedAtNanoseconds = sendFinishedAtNanoseconds
    }

    public var queueDelayMilliseconds: Double? {
        Self.milliseconds(
            from: receivedAtNanoseconds,
            to: queuedForSendAtNanoseconds
        )
    }

    public var voiceActivityMilliseconds: Double? {
        Self.milliseconds(
            from: queuedForSendAtNanoseconds,
            to: voiceActivityFinishedAtNanoseconds
        )
    }

    public var sendMilliseconds: Double? {
        Self.milliseconds(
            from: voiceActivityFinishedAtNanoseconds,
            to: sendFinishedAtNanoseconds
        )
    }

    public var totalMilliseconds: Double? {
        Self.milliseconds(
            from: receivedAtNanoseconds,
            to: sendFinishedAtNanoseconds
        )
    }

    public func markingQueuedForSend(
        atNanoseconds nanoseconds: UInt64 = Self.nowNanoseconds()
    ) -> Self {
        Self(
            receivedAtNanoseconds: receivedAtNanoseconds,
            queuedForSendAtNanoseconds: nanoseconds,
            voiceActivityFinishedAtNanoseconds: voiceActivityFinishedAtNanoseconds,
            sendFinishedAtNanoseconds: sendFinishedAtNanoseconds
        )
    }

    public func markingVoiceActivityFinished(
        atNanoseconds nanoseconds: UInt64 = Self.nowNanoseconds()
    ) -> Self {
        Self(
            receivedAtNanoseconds: receivedAtNanoseconds,
            queuedForSendAtNanoseconds: queuedForSendAtNanoseconds,
            voiceActivityFinishedAtNanoseconds: nanoseconds,
            sendFinishedAtNanoseconds: sendFinishedAtNanoseconds
        )
    }

    public func markingSendFinished(
        atNanoseconds nanoseconds: UInt64 = Self.nowNanoseconds()
    ) -> Self {
        Self(
            receivedAtNanoseconds: receivedAtNanoseconds,
            queuedForSendAtNanoseconds: queuedForSendAtNanoseconds,
            voiceActivityFinishedAtNanoseconds: voiceActivityFinishedAtNanoseconds,
            sendFinishedAtNanoseconds: nanoseconds
        )
    }

    public static func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    public static func milliseconds(from start: UInt64?, to end: UInt64?) -> Double? {
        guard let start, let end, end >= start else { return nil }
        return Double(end - start) / 1_000_000.0
    }

    public static func format(milliseconds: Double?) -> String {
        guard let milliseconds else { return "none" }
        return String(format: "%.1f", milliseconds)
    }
}

public struct AudioChunkPayload: Encodable, Equatable, Sendable {
    public let sequenceNumber: Int
    public let pcm: Data
    public let sampleRateHz: Int
    public let voiceActivity: VoiceActivityPayload?
    public let latencyTrace: AudioChunkLatencyTrace?

    public init(
        sequenceNumber: Int,
        pcm: Data,
        sampleRateHz: Int,
        voiceActivity: VoiceActivityPayload? = nil,
        latencyTrace: AudioChunkLatencyTrace? = nil
    ) {
        self.sequenceNumber = sequenceNumber
        self.pcm = pcm
        self.sampleRateHz = sampleRateHz
        self.voiceActivity = voiceActivity
        self.latencyTrace = latencyTrace
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
