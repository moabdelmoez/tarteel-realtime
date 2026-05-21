import Foundation

public enum BackendEndpointPreset: String, CaseIterable, Hashable, Identifiable, Sendable {
    case simulator
    case liveKitLocal
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .simulator:
            return "Simulator"
        case .liveKitLocal:
            return "LiveKit"
        case .custom:
            return "Custom"
        }
    }

    public var defaultURLText: String {
        switch self {
        case .simulator:
            return "ws://127.0.0.1:8000/ws/recitation"
        case .liveKitLocal:
            return "http://127.0.0.1:8000/livekit/recitation-token"
        case .custom:
            return ""
        }
    }

    public var allowsURLTextEditing: Bool {
        switch self {
        case .simulator:
            return false
        case .liveKitLocal, .custom:
            return true
        }
    }

    public func urlText(currentCustomURLText: String) -> String {
        switch self {
        case .simulator:
            return defaultURLText
        case .liveKitLocal:
            return currentCustomURLText.isEmpty ? defaultURLText : currentCustomURLText
        case .custom:
            return currentCustomURLText
        }
    }
}
