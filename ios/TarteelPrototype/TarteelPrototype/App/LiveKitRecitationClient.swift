import Foundation

#if canImport(LiveKit)
import LiveKit
#endif

private let liveKitRecitationEventTopic = "tarteel.recitation.event"

final class LiveKitRecitationClient: NSObject {
    private let decoder = JSONDecoder()
    private var onEvent: (@Sendable (RecitationEvent) -> Void)?

    #if canImport(LiveKit)
    private var room: Room?
    #endif

    func connect(
        token: LiveKitRecitationToken,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        self.onEvent = onEvent

        #if canImport(LiveKit)
        let room = Room(delegate: self)
        try await room.connect(url: token.url, token: token.token)
        try await room.localParticipant.setMicrophone(enabled: true)
        self.room = room
        #else
        throw LiveKitRecitationClientError.sdkUnavailable
        #endif
    }

    func disconnect() {
        onEvent = nil

        #if canImport(LiveKit)
        Task {
            await room?.disconnect()
            room = nil
        }
        #endif
    }

    fileprivate func receive(data: Data, topic: String) {
        guard topic == liveKitRecitationEventTopic else { return }
        guard let event = try? decoder.decode(RecitationEvent.self, from: data) else { return }
        onEvent?(event)
    }
}

enum LiveKitRecitationClientError: LocalizedError {
    case sdkUnavailable

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            return "LiveKit SDK is not linked yet. Add LiveKit to the app target before using the LiveKit transport."
        }
    }
}

#if canImport(LiveKit)
extension LiveKitRecitationClient: RoomDelegate {
    func room(
        _ room: Room,
        participant: RemoteParticipant?,
        didReceiveData data: Data,
        forTopic topic: String,
        encryptionType: EncryptionType
    ) {
        receive(data: data, topic: topic)
    }
}
#endif
