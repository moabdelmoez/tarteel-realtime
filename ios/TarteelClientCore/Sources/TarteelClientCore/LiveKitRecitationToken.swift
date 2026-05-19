import Foundation

public struct LiveKitRecitationToken: Codable, Equatable, Sendable {
    public let url: String
    public let room: String
    public let identity: String
    public let role: String
    public let token: String

    public init(
        url: String,
        room: String,
        identity: String,
        role: String,
        token: String
    ) {
        self.url = url
        self.room = room
        self.identity = identity
        self.role = role
        self.token = token
    }
}
