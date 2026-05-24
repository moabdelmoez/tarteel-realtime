import Foundation

public enum RecitationScopeSelection: Hashable, Sendable {
    case autoDetect
    case selectedSurah(id: Int)

    public var queryValue: String? {
        switch self {
        case .autoDetect:
            return nil
        case let .selectedSurah(id):
            return "\(id)"
        }
    }
}
