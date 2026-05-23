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

    public var allowsURLTextEditing: Bool {
        switch self {
        case .simulator:
            return false
        case .custom:
            return true
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

    public func recordingURLText(currentURLText: String) -> String {
        switch self {
        case .simulator:
            return defaultURLText
        case .custom:
            return Self.webSocketURLText(from: currentURLText)
        }
    }

    private static func webSocketURLText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let schemeReadyText = addWSSForRunPodHostIfNeeded(trimmed)
        guard var components = URLComponents(string: schemeReadyText) else {
            return schemeReadyText
        }

        if components.scheme == "http" {
            components.scheme = "ws"
        } else if components.scheme == "https" {
            components.scheme = "wss"
        }

        if components.host?.contains(".proxy.runpod.net") == true && components.path.isEmpty {
            components.path = "/ws/recitation"
        }

        return components.string ?? schemeReadyText
    }

    private static func addWSSForRunPodHostIfNeeded(_ text: String) -> String {
        guard !text.contains("://"), text.contains(".proxy.runpod.net") else {
            return text
        }
        return "wss://\(text)"
    }
}
