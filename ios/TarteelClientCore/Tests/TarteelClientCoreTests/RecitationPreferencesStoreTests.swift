import XCTest
@testable import TarteelClientCore

final class RecitationPreferencesStoreTests: XCTestCase {
    func testDefaultsWhenNoValuesArePersisted() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.defaults")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.defaults")
        let store = UserDefaultsRecitationPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.backendPreset, .simulator)
        XCTAssertEqual(store.customBackendProvider, .runPod)
        XCTAssertEqual(store.customBackendURLText, "")
        XCTAssertEqual(store.recitationMode, .autoDetect)
        XCTAssertEqual(store.selectedSurahID, 108)
    }

    func testCanUseModalFallbackValuesWhenNoValuesArePersisted() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.modalFallback")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.modalFallback")
        let store = UserDefaultsRecitationPreferencesStore(
            defaults: defaults,
            fallbackValues: .modalPrimary
        )

        XCTAssertEqual(store.backendPreset, .custom)
        XCTAssertEqual(store.customBackendProvider, .modal)
        XCTAssertEqual(
            store.customBackendURLText,
            "wss://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation"
        )
        XCTAssertEqual(store.recitationMode, .autoDetect)
        XCTAssertEqual(store.selectedSurahID, 108)
    }

    func testCanUseCoreMLSelectedSurahFallbackValuesWhenNoValuesArePersisted() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.coreMLFallback")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.coreMLFallback")
        let store = UserDefaultsRecitationPreferencesStore(
            defaults: defaults,
            fallbackValues: .coreMLSelectedSurah108
        )

        XCTAssertEqual(store.backendPreset, .coreML)
        XCTAssertEqual(store.customBackendProvider, .runPod)
        XCTAssertEqual(store.customBackendURLText, "")
        XCTAssertEqual(store.recitationMode, .selectedSurah)
        XCTAssertEqual(store.selectedSurahID, 108)
    }

    func testVolatileStoreKeepsDeveloperReplayPreferencesInMemory() {
        var store = VolatileRecitationPreferencesStore(
            defaults: RecitationPreferencesDefaults(
                backendPreset: .coreML,
                recitationMode: .selectedSurah,
                selectedSurahID: 108
            )
        )

        XCTAssertEqual(store.backendPreset, .coreML)
        XCTAssertEqual(store.recitationMode, .selectedSurah)
        XCTAssertEqual(store.selectedSurahID, 108)

        store.selectedSurahID = 4
        store.backendPreset = .custom

        XCTAssertEqual(store.selectedSurahID, 4)
        XCTAssertEqual(store.backendPreset, .custom)
    }

    func testPersistedValuesOverrideModalFallbackValues() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.persistedOverride")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.persistedOverride")
        var store = UserDefaultsRecitationPreferencesStore(
            defaults: defaults,
            fallbackValues: .modalPrimary
        )

        store.backendPreset = .simulator
        store.customBackendProvider = .runPod
        store.customBackendURLText = "wss://example.test/ws/recitation"
        store.recitationMode = .selectedSurah
        store.selectedSurahID = 4

        let reloaded = UserDefaultsRecitationPreferencesStore(
            defaults: defaults,
            fallbackValues: .modalPrimary
        )
        XCTAssertEqual(reloaded.backendPreset, .simulator)
        XCTAssertEqual(reloaded.customBackendProvider, .runPod)
        XCTAssertEqual(reloaded.customBackendURLText, "wss://example.test/ws/recitation")
        XCTAssertEqual(reloaded.recitationMode, .selectedSurah)
        XCTAssertEqual(reloaded.selectedSurahID, 4)
    }

    func testInvalidPersistedSelectedSurahIDFallsBackToConfiguredDefault() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.invalidPersistedSurah")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.invalidPersistedSurah")
        defaults.set(0, forKey: "tarteel.selectedSurahID")
        let store = UserDefaultsRecitationPreferencesStore(
            defaults: defaults,
            fallbackValues: RecitationPreferencesDefaults(selectedSurahID: 4)
        )

        XCTAssertEqual(store.selectedSurahID, 4)
    }

    func testPersistsNonSecretSettings() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.persist")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.persist")
        var store = UserDefaultsRecitationPreferencesStore(defaults: defaults)

        store.backendPreset = .custom
        store.customBackendProvider = .modal
        store.customBackendURLText = "wss://example.test/ws/recitation"
        store.recitationMode = .selectedSurah
        store.selectedSurahID = 4

        let reloaded = UserDefaultsRecitationPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.backendPreset, .custom)
        XCTAssertEqual(reloaded.customBackendProvider, .modal)
        XCTAssertEqual(reloaded.customBackendURLText, "wss://example.test/ws/recitation")
        XCTAssertEqual(reloaded.recitationMode, .selectedSurah)
        XCTAssertEqual(reloaded.selectedSurahID, 4)
    }

    func testRunPodAPIKeyIsNotPartOfPreferencesStore() {
        let defaults = UserDefaults(suiteName: "RecitationPreferencesStoreTests.noSecret")!
        defaults.removePersistentDomain(forName: "RecitationPreferencesStoreTests.noSecret")
        let store = UserDefaultsRecitationPreferencesStore(defaults: defaults)

        XCTAssertFalse(Mirror(reflecting: store).children.contains { $0.label == "backendBearerTokenText" })
    }
}
