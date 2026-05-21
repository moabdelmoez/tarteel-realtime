import Foundation

public struct LiveKitRecitationToken: Codable, Equatable, Sendable {
    public let url: String
    public let room: String
    public let identity: String
    public let sessionId: String
    public let role: String
    public let token: String

    public init(
        url: String,
        room: String,
        identity: String,
        sessionId: String,
        role: String,
        token: String
    ) {
        self.url = url
        self.room = room
        self.identity = identity
        self.sessionId = sessionId
        self.role = role
        self.token = token
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case room
        case identity
        case sessionId = "session_id"
        case role
        case token
    }
}
