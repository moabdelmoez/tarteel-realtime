import Foundation

public enum BackendEndpointPreset: String, CaseIterable, Hashable, Identifiable, Sendable {
    case simulator
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .simulator:
            return "Simulator"
        case .custom:
            return "Custom"
        }
    }

    public var defaultURLText: String {
        switch self {
        case .simulator:
            return "ws://127.0.0.1:8000/ws/recitation"
        case .custom:
            return ""
        }
    }

    public func urlText(currentCustomURLText: String) -> String {
        switch self {
        case .simulator:
            return defaultURLText
        case .custom:
            return currentCustomURLText
        }
    }
}
