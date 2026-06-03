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

public protocol BackendBearerTokenStoring: AnyObject {
    func token(for provider: BackendProvider) throws -> String?
    func setToken(_ token: String?, for provider: BackendProvider) throws
}

public final class VolatileBackendBearerTokenStore: BackendBearerTokenStoring {
    private var tokens: [BackendProvider: String]

    public init(tokens: [BackendProvider: String] = [:]) {
        self.tokens = tokens
    }

    public func token(for provider: BackendProvider) throws -> String? {
        tokens[provider]
    }

    public func setToken(_ token: String?, for provider: BackendProvider) throws {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedToken.isEmpty {
            tokens.removeValue(forKey: provider)
        } else {
            tokens[provider] = trimmedToken
        }
    }
}
