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
        normalizedRecordingURLText(currentURLText: currentURLText, recitationScope: nil)
    }

    public func recordingURLText(
        currentURLText: String,
        recitationScope: RecitationScopeSelection
    ) -> String {
        normalizedRecordingURLText(currentURLText: currentURLText, recitationScope: recitationScope)
    }

    private func normalizedRecordingURLText(
        currentURLText: String,
        recitationScope: RecitationScopeSelection?
    ) -> String {
        let urlText: String
        switch self {
        case .simulator:
            urlText = defaultURLText
        case .custom:
            urlText = Self.webSocketURLText(from: currentURLText)
        }

        return Self.urlText(urlText, applying: recitationScope)
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

        if isRunPodHost(components.host) && components.path.isEmpty {
            components.path = "/ws/recitation"
        }

        return components.string ?? schemeReadyText
    }

    private static func addWSSForRunPodHostIfNeeded(_ text: String) -> String {
        guard !text.contains("://"), isRunPodHostText(text) else {
            return text
        }
        return "wss://\(text)"
    }

    private static func isRunPodHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return isRunPodHostText(host)
    }

    private static func isRunPodHostText(_ text: String) -> Bool {
        text.contains(".proxy.runpod.net") || text.contains(".api.runpod.ai")
    }

    private static func urlText(
        _ text: String,
        applying recitationScope: RecitationScopeSelection?
    ) -> String {
        guard let recitationScope else { return text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return text
        }
        guard var components = URLComponents(string: text) else { return text }

        var queryItems = components.queryItems?.filter { $0.name != "scope" } ?? []
        if let scope = recitationScope.queryValue {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        return components.string ?? text
    }
}
