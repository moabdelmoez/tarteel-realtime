import XCTest
@testable import TarteelClientCore

final class RecitationPreferencesStoreTests: XCTestCase {
    func testDefaultsWhenNoValuesArePersisted() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.defaults")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.defaults")
        let store = UserDefaultsRecitationPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.backendPreset, .simulator)
        XCTAssertEqual(store.customBackendURLText, "")
        XCTAssertEqual(store.recitationMode, .autoDetect)
        XCTAssertEqual(store.selectedSurahID, 108)
    }

    func testPersistsNonSecretSettings() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.persist")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.persist")
        var store = UserDefaultsRecitationPreferencesStore(defaults: defaults)

        store.backendPreset = .custom
        store.customBackendURLText = "wss://example.test/ws/recitation"
        store.recitationMode = .selectedSurah
        store.selectedSurahID = 4

        let reloaded = UserDefaultsRecitationPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.backendPreset, .custom)
        XCTAssertEqual(reloaded.customBackendURLText, "wss://example.test/ws/recitation")
        XCTAssertEqual(reloaded.recitationMode, .selectedSurah)
        XCTAssertEqual(reloaded.selectedSurahID, 4)
    }

    func testRunPodAPIKeyIsNotPartOfPreferencesStore() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.noSecret")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.noSecret")
        let store = UserDefaultsRecitationPreferencesStore(defaults: defaults)

        XCTAssertFalse(Mirror(reflecting: store).children.contains { $0.label == "runPodAPIKeyText" })
    }
}
