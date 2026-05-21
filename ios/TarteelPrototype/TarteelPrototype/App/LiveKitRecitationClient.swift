import Foundation

#if canImport(LiveKit)
import AVFoundation
import Darwin
import LiveKit
#endif

private let liveKitRecitationEventTopic = "tarteel.recitation.event"
private let liveKitVoiceActivityTopic = "tarteel.voice_activity"

@MainActor
final class LiveKitRecitationClient: NSObject {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var onEvent: (@Sendable (RecitationEvent) -> Void)?
    private var activeSessionId: String?

    #if canImport(LiveKit)
    private var room: Room?
    #endif

    func connect(
        token: LiveKitRecitationToken,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        self.onEvent = onEvent
        activeSessionId = token.sessionId

        #if canImport(LiveKit)
        try AudioManager.shared.setManualRenderingMode(true)
        let room = Room(delegate: self)
        try await room.connect(url: token.url, token: token.token)
        try await room.localParticipant.setMicrophone(enabled: true)
        self.room = room
        #else
        throw LiveKitRecitationClientError.sdkUnavailable
        #endif
    }

    func publishAudio(
        pcm: Data,
        sampleRate: Int,
        sequenceNumber: Int,
        voiceActivity: VoiceActivityPayload?
    ) async throws {
        #if canImport(LiveKit)
        guard let room else {
            throw LiveKitRecitationClientError.notConnected
        }

        if let voiceActivity {
            let message = LiveKitVoiceActivityMessage(
                sequenceNumber: sequenceNumber,
                sampleRateHz: sampleRate,
                voiceActivity: voiceActivity
            )
            let data = try encoder.encode(message)
            try await room.localParticipant.publish(data: data, options: DataPublishOptions(topic: liveKitVoiceActivityTopic))
        }

        guard shouldPublishAudio(for: voiceActivity) else { return }
        guard let buffer = pcm.pcm16AudioBuffer(sampleRate: sampleRate) else {
            throw LiveKitRecitationClientError.unsupportedPCM
        }
        AudioManager.shared.mixer.capture(appAudio: buffer)
        #else
        throw LiveKitRecitationClientError.sdkUnavailable
        #endif
    }

    func disconnect() {
        onEvent = nil
        activeSessionId = nil

        #if canImport(LiveKit)
        Task {
            await room?.disconnect()
            room = nil
        }
        try? AudioManager.shared.setManualRenderingMode(false)
        #endif
    }

    private func shouldPublishAudio(for voiceActivity: VoiceActivityPayload?) -> Bool {
        guard let voiceActivity else { return true }
        return voiceActivity.isSpeechActive
            || voiceActivity.event == .speechStart
            || voiceActivity.event == .speechEnd
    }

    fileprivate func receive(data: Data, topic: String) {
        guard topic == liveKitRecitationEventTopic else { return }
        guard let event = try? decoder.decode(RecitationEvent.self, from: data) else { return }
        guard event.sessionId == activeSessionId else { return }
        onEvent?(event)
    }
}

enum LiveKitRecitationClientError: LocalizedError {
    case sdkUnavailable
    case notConnected
    case unsupportedPCM

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return "LiveKit SDK is not linked yet. Add LiveKit to the app target before using the LiveKit transport."
        case .notConnected:
            return "LiveKit is not connected."
        case .unsupportedPCM:
            return "Could not publish the microphone chunk to LiveKit."
        }
    }
}

#if canImport(LiveKit)
private struct LiveKitVoiceActivityMessage: Encodable {
    let sequenceNumber: Int
    let sampleRateHz: Int
    let voiceActivity: VoiceActivityPayload

    private enum CodingKeys: String, CodingKey {
        case sequenceNumber = "sequence_number"
        case sampleRateHz = "sample_rate_hz"
        case voiceActivity = "voice_activity"
    }
}

private extension Data {
    func pcm16AudioBuffer(sampleRate: Int) -> AVAudioPCMBuffer? {
        guard sampleRate > 0, count >= MemoryLayout<Int16>.size else { return nil }
        let frameCount = count / MemoryLayout<Int16>.size
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            ),
            let channelData = buffer.int16ChannelData
        else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            memcpy(channelData[0], baseAddress, frameCount * MemoryLayout<Int16>.size)
        }
        return buffer
    }
}

extension LiveKitRecitationClient: RoomDelegate {
    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant?,
        didReceiveData data: Data,
        forTopic topic: String,
        encryptionType: EncryptionType
    ) {
        Task { @MainActor [weak self] in
            self?.receive(data: data, topic: topic)
        }
    }
}
#endif
