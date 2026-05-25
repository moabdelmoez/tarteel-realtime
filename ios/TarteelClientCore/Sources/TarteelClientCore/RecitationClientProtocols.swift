import Foundation

@MainActor
public protocol BackendSocketing: AnyObject {
    func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws
    func send(_ payload: AudioChunkPayload) async throws
    func disconnect()
}

public protocol AudioStreaming: AnyObject, Sendable {
    func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws
    func stop()
}

public protocol VoiceActivityDetecting: AnyObject, Sendable {
    func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload?
    func reset() async
}
