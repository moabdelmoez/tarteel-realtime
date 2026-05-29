import Foundation

public protocol RecitationPreferencesStoring {
    var backendPreset: BackendEndpointPreset { get set }
    var customBackendProvider: BackendProvider { get set }
    var customBackendURLText: String { get set }
    var recitationMode: RecitationMode { get set }
    var selectedSurahID: Int { get set }
}

public struct UserDefaultsRecitationPreferencesStore: RecitationPreferencesStoring {
    private enum Key {
        static let backendPreset = "tarteel.backendPreset"
        static let customBackendProvider = "tarteel.customBackendProvider"
        static let customBackendURLText = "tarteel.customBackendURLText"
        static let recitationMode = "tarteel.recitationMode"
        static let selectedSurahID = "tarteel.selectedSurahID"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var backendPreset: BackendEndpointPreset {
        get {
            guard let rawValue = defaults.string(forKey: Key.backendPreset),
                  let preset = BackendEndpointPreset(rawValue: rawValue) else {
                return .simulator
            }
            return preset
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.backendPreset)
        }
    }

    public var customBackendProvider: BackendProvider {
        get {
            guard let rawValue = defaults.string(forKey: Key.customBackendProvider),
                  let provider = BackendProvider(rawValue: rawValue) else {
                return .runPod
            }
            return provider
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.customBackendProvider)
        }
    }

    public var customBackendURLText: String {
        get { defaults.string(forKey: Key.customBackendURLText) ?? "" }
        set { defaults.set(newValue, forKey: Key.customBackendURLText) }
    }

    public var recitationMode: RecitationMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.recitationMode),
                  let mode = RecitationMode(rawValue: rawValue) else {
                return .autoDetect
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.recitationMode)
        }
    }

    public var selectedSurahID: Int {
        get {
            let value = defaults.integer(forKey: Key.selectedSurahID)
            return value == 0 ? 108 : value
        }
        set {
            defaults.set(newValue, forKey: Key.selectedSurahID)
        }
    }
}
