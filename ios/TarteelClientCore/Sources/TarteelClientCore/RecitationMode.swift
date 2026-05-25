import Foundation

public enum RecitationMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case autoDetect
    case selectedSurah

    public var id: String { rawValue }
}
