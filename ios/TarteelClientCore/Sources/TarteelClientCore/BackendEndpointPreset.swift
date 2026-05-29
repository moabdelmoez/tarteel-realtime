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
        normalizedRecordingURLText(
            currentURLText: currentURLText,
            recitationScope: nil,
            provider: .runPod
        )
    }

    public func recordingURLText(
        currentURLText: String,
        provider: BackendProvider
    ) -> String {
        normalizedRecordingURLText(
            currentURLText: currentURLText,
            recitationScope: nil,
            provider: provider
        )
    }

    public func recordingURLText(
        currentURLText: String,
        recitationScope: RecitationScopeSelection
    ) -> String {
        normalizedRecordingURLText(
            currentURLText: currentURLText,
            recitationScope: recitationScope,
            provider: .runPod
        )
    }

    public func recordingURLText(
        currentURLText: String,
        recitationScope: RecitationScopeSelection,
        provider: BackendProvider
    ) -> String {
        normalizedRecordingURLText(
            currentURLText: currentURLText,
            recitationScope: recitationScope,
            provider: provider
        )
    }

    private func normalizedRecordingURLText(
        currentURLText: String,
        recitationScope: RecitationScopeSelection?,
        provider: BackendProvider
    ) -> String {
        let urlText: String
        switch self {
        case .simulator:
            urlText = defaultURLText
        case .custom:
            urlText = Self.webSocketURLText(from: currentURLText, provider: provider)
        }

        return Self.urlText(urlText, applying: recitationScope)
    }

    private static func webSocketURLText(from text: String, provider: BackendProvider) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let schemeReadyText = addWSSIfProviderHostNeedsIt(trimmed, provider: provider)
        guard var components = URLComponents(string: schemeReadyText) else {
            return schemeReadyText
        }

        if components.scheme == "http" {
            components.scheme = "ws"
        } else if components.scheme == "https" {
            components.scheme = "wss"
        }

        if provider.shouldAppendRecitationPath(to: components.host) && components.path.isEmpty {
            components.path = "/ws/recitation"
        }

        return components.string ?? schemeReadyText
    }

    private static func addWSSIfProviderHostNeedsIt(_ text: String, provider: BackendProvider) -> String {
        guard !text.contains("://"), provider.hostNeedsWebSocketScheme(text) else {
            return text
        }
        return "wss://\(text)"
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

public enum BackendProvider: String, CaseIterable, Hashable, Identifiable, Sendable {
    case generic
    case runPod
    case modal

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .generic:
            return "Generic"
        case .runPod:
            return "RunPod"
        case .modal:
            return "Modal"
        }
    }

    public var tokenFieldLabel: String {
        switch self {
        case .generic:
            return "Bearer token"
        case .runPod:
            return "RunPod API key"
        case .modal:
            return "Modal bearer token"
        }
    }

    public var tokenHelpText: String {
        switch self {
        case .generic:
            return "Optional memory-only bearer token for the selected backend."
        case .runPod:
            return "Prototype-only direct RunPod token. This value is not saved."
        case .modal:
            return "Memory-only Modal backend bearer token. This value is not saved."
        }
    }

    fileprivate func hostNeedsWebSocketScheme(_ text: String) -> Bool {
        switch self {
        case .generic:
            return false
        case .runPod:
            return Self.isRunPodHostText(text)
        case .modal:
            return Self.isModalHostText(text)
        }
    }

    fileprivate func shouldAppendRecitationPath(to host: String?) -> Bool {
        guard let host else { return false }
        switch self {
        case .generic:
            return false
        case .runPod:
            return Self.isRunPodHostText(host)
        case .modal:
            return Self.isModalHostText(host)
        }
    }

    private static func isRunPodHostText(_ text: String) -> Bool {
        text.contains(".proxy.runpod.net") || text.contains(".api.runpod.ai")
    }

    private static func isModalHostText(_ text: String) -> Bool {
        text.contains(".modal.run")
    }
}
