import Foundation

public struct RecitationPreferencesDefaults: Equatable, Sendable {
    public let backendPreset: BackendEndpointPreset
    public let customBackendProvider: BackendProvider
    public let customBackendURLText: String
    public let recitationMode: RecitationMode
    public let selectedSurahID: Int

    public init(
        backendPreset: BackendEndpointPreset = .simulator,
        customBackendProvider: BackendProvider = .runPod,
        customBackendURLText: String = "",
        recitationMode: RecitationMode = .autoDetect,
        selectedSurahID: Int = 108
    ) {
        self.backendPreset = backendPreset
        self.customBackendProvider = customBackendProvider
        self.customBackendURLText = customBackendURLText
        self.recitationMode = recitationMode
        self.selectedSurahID = selectedSurahID
    }

    public static let simulator = RecitationPreferencesDefaults()

    public static let modalPrimary = RecitationPreferencesDefaults(
        backendPreset: .custom,
        customBackendProvider: .modal,
        customBackendURLText: "wss://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation",
        recitationMode: .autoDetect,
        selectedSurahID: 108
    )
}

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
    private let fallbackValues: RecitationPreferencesDefaults

    public init(
        defaults: UserDefaults = .standard,
        fallbackValues: RecitationPreferencesDefaults = .simulator
    ) {
        self.defaults = defaults
        self.fallbackValues = fallbackValues
    }

    public var backendPreset: BackendEndpointPreset {
        get {
            guard let rawValue = defaults.string(forKey: Key.backendPreset),
                  let preset = BackendEndpointPreset(rawValue: rawValue) else {
                return fallbackValues.backendPreset
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
                return fallbackValues.customBackendProvider
            }
            return provider
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.customBackendProvider)
        }
    }

    public var customBackendURLText: String {
        get { defaults.string(forKey: Key.customBackendURLText) ?? fallbackValues.customBackendURLText }
        set { defaults.set(newValue, forKey: Key.customBackendURLText) }
    }

    public var recitationMode: RecitationMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.recitationMode),
                  let mode = RecitationMode(rawValue: rawValue) else {
                return fallbackValues.recitationMode
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.recitationMode)
        }
    }

    public var selectedSurahID: Int {
        get {
            guard defaults.object(forKey: Key.selectedSurahID) != nil else {
                return fallbackValues.selectedSurahID
            }
            let value = defaults.integer(forKey: Key.selectedSurahID)
            return value == 0 ? fallbackValues.selectedSurahID : value
        }
        set {
            defaults.set(newValue, forKey: Key.selectedSurahID)
        }
    }
}
