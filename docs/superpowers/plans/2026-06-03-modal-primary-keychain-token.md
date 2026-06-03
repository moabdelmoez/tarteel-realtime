# Modal Primary Keychain Token Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the macOS prototype default to Modal and persist the Modal bearer token securely in macOS Keychain so the user does not re-enter it on every launch.

**Architecture:** Keep the existing WebSocket transport unchanged. Add configurable non-secret preference defaults in the shared client core, add a bearer-token storage protocol used by `RecitationViewModel`, and inject a macOS-only Keychain implementation from the macOS app target. iPhone keeps the current simulator-friendly default and memory-only token behavior.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Testing, `UserDefaults`, macOS Keychain through Security.framework, Python unittest source guardrails, Xcode project target membership.

---

## Reference Design

Read before implementation:

- `docs/superpowers/specs/2026-06-03-modal-primary-keychain-token-design.md`

## File Structure

- Modify `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationPreferencesStore.swift`
  - Add configurable fallback defaults while preserving current shared defaults.
- Modify `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationClientProtocols.swift`
  - Add `BackendBearerTokenStoring` and a volatile in-process implementation for tests and iPhone default behavior.
- Modify `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift`
  - Load, save, clear, and report errors for backend bearer tokens through the injected storage boundary.
- Create `ios/TarteelPrototype/TarteelPrototypeMac/App/KeychainBackendBearerTokenStore.swift`
  - Store provider-specific tokens in macOS Keychain.
- Modify `ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift`
  - Inject Modal defaults and the Keychain token store.
- Modify `ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift`
  - Show macOS Keychain-specific token copy and token persistence errors.
- Modify `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj`
  - Add the Keychain source file to the macOS target only.
- Modify tests:
  - `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationPreferencesStoreTests.swift`
  - `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift`
  - `tests/test_macos_app_project.py`
- Modify docs/harness after implementation:
  - `README.md`
  - `docs/modal-serverless.md`
  - `codex-progress.md`
  - `session-handoff.md`
  - `feature_list.json`

---

### Task 1: Add Configurable Non-Secret Preference Defaults

**Files:**
- Modify: `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationPreferencesStoreTests.swift`
- Modify: `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationPreferencesStore.swift`

- [ ] **Step 1: Write the failing preferences default tests**

In `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationPreferencesStoreTests.swift`, add this test after `testDefaultsWhenNoValuesArePersisted()`:

```swift
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
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationPreferencesStoreTests
```

Expected: FAIL with errors that `fallbackValues` and `.modalPrimary` do not exist.

- [ ] **Step 3: Implement configurable defaults**

Replace `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationPreferencesStore.swift` with:

```swift
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
            return defaults.integer(forKey: Key.selectedSurahID)
        }
        set {
            defaults.set(newValue, forKey: Key.selectedSurahID)
        }
    }
}
```

- [ ] **Step 4: Run focused preferences tests and verify they pass**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationPreferencesStoreTests
```

Expected: PASS for `RecitationPreferencesStoreTests`.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add ios/TarteelClientCore/Sources/TarteelClientCore/RecitationPreferencesStore.swift ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationPreferencesStoreTests.swift
git commit -m "feat: add modal preference defaults"
```

---

### Task 2: Add Token Storage Boundary and ViewModel Persistence Behavior

**Files:**
- Modify: `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift`
- Modify: `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationClientProtocols.swift`
- Modify: `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift`

- [ ] **Step 1: Write failing ViewModel token storage tests**

In `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift`, add these tests before `testDuplicateToggleWhileConnectingOnlyStartsOneSocketConnection()`:

```swift
func testLoadsStoredBearerTokenForInitialCustomProvider() {
    let tokenStore = FakeBearerTokenStore(tokens: [.modal: "stored-modal-token"])
    let viewModel = RecitationViewModel(
        socketClient: FakeSocket(),
        audioStreamer: FakeAudioStreamer(),
        voiceActivityDetector: FakeVoiceActivityDetector(),
        preferencesStore: FakePreferencesStore(
            backendPreset: .custom,
            customBackendProvider: .modal,
            customBackendURLText: "wss://example.modal.run/ws/recitation"
        ),
        backendBearerTokenStore: tokenStore
    )

    XCTAssertEqual(viewModel.backendBearerTokenText, "stored-modal-token")
    XCTAssertNil(viewModel.backendBearerTokenPersistenceMessage)
}

func testSwitchingCustomProviderLoadsProviderSpecificStoredToken() {
    let tokenStore = FakeBearerTokenStore(tokens: [
        .runPod: "stored-runpod-token",
        .modal: "stored-modal-token",
    ])
    let viewModel = RecitationViewModel(
        socketClient: FakeSocket(),
        audioStreamer: FakeAudioStreamer(),
        voiceActivityDetector: FakeVoiceActivityDetector(),
        preferencesStore: FakePreferencesStore(
            backendPreset: .custom,
            customBackendProvider: .runPod,
            customBackendURLText: "wss://example.test/ws/recitation"
        ),
        backendBearerTokenStore: tokenStore
    )

    XCTAssertEqual(viewModel.backendBearerTokenText, "stored-runpod-token")

    viewModel.selectCustomBackendProvider(.modal)

    XCTAssertEqual(viewModel.backendBearerTokenText, "stored-modal-token")
    XCTAssertEqual(viewModel.customBackendProvider, .modal)
}

func testEditingBearerTokenPersistsTrimmedTokenForCurrentProvider() {
    let tokenStore = FakeBearerTokenStore()
    let viewModel = RecitationViewModel(
        socketClient: FakeSocket(),
        audioStreamer: FakeAudioStreamer(),
        voiceActivityDetector: FakeVoiceActivityDetector(),
        preferencesStore: FakePreferencesStore(
            backendPreset: .custom,
            customBackendProvider: .modal,
            customBackendURLText: "wss://example.modal.run/ws/recitation"
        ),
        backendBearerTokenStore: tokenStore
    )

    viewModel.backendBearerTokenText = "  new-modal-token  "

    XCTAssertEqual(tokenStore.tokens[.modal], "new-modal-token")
    XCTAssertNil(viewModel.backendBearerTokenPersistenceMessage)
}

func testClearingBearerTokenDeletesStoredTokenForCurrentProvider() {
    let tokenStore = FakeBearerTokenStore(tokens: [.modal: "stored-modal-token"])
    let viewModel = RecitationViewModel(
        socketClient: FakeSocket(),
        audioStreamer: FakeAudioStreamer(),
        voiceActivityDetector: FakeVoiceActivityDetector(),
        preferencesStore: FakePreferencesStore(
            backendPreset: .custom,
            customBackendProvider: .modal,
            customBackendURLText: "wss://example.modal.run/ws/recitation"
        ),
        backendBearerTokenStore: tokenStore
    )

    viewModel.backendBearerTokenText = " "

    XCTAssertNil(tokenStore.tokens[.modal])
    XCTAssertNil(viewModel.backendBearerTokenPersistenceMessage)
}

func testTokenStorageWriteFailureKeepsTypedTokenForCurrentSession() {
    let tokenStore = ThrowingBearerTokenStore()
    let viewModel = RecitationViewModel(
        socketClient: FakeSocket(),
        audioStreamer: FakeAudioStreamer(),
        voiceActivityDetector: FakeVoiceActivityDetector(),
        preferencesStore: FakePreferencesStore(
            backendPreset: .custom,
            customBackendProvider: .modal,
            customBackendURLText: "wss://example.modal.run/ws/recitation"
        ),
        backendBearerTokenStore: tokenStore
    )

    viewModel.backendBearerTokenText = "modal-token"

    XCTAssertEqual(viewModel.backendBearerTokenText, "modal-token")
    XCTAssertEqual(
        viewModel.backendBearerTokenPersistenceMessage,
        "Token will be used for this session only. Keychain update failed."
    )
}
```

At the bottom of the same test file, before `private enum TestSocketError`, add these fakes:

```swift
private final class FakeBearerTokenStore: BackendBearerTokenStoring {
    private(set) var tokens: [BackendProvider: String]

    init(tokens: [BackendProvider: String] = [:]) {
        self.tokens = tokens
    }

    func token(for provider: BackendProvider) throws -> String? {
        tokens[provider]
    }

    func setToken(_ token: String?, for provider: BackendProvider) throws {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedToken.isEmpty {
            tokens.removeValue(forKey: provider)
        } else {
            tokens[provider] = trimmedToken
        }
    }
}

private final class ThrowingBearerTokenStore: BackendBearerTokenStoring {
    func token(for provider: BackendProvider) throws -> String? {
        nil
    }

    func setToken(_ token: String?, for provider: BackendProvider) throws {
        throw TestTokenStoreError.writeFailed
    }
}

private enum TestTokenStoreError: Error {
    case writeFailed
}
```

- [ ] **Step 2: Run the focused ViewModel tests and verify they fail**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationViewModelTests
```

Expected: FAIL with missing `BackendBearerTokenStoring`, `backendBearerTokenStore`, and `backendBearerTokenPersistenceMessage`.

- [ ] **Step 3: Add the token storage protocol and volatile implementation**

Append this code to `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationClientProtocols.swift` after `VoiceActivityDetecting`:

```swift
public protocol BackendBearerTokenStoring: AnyObject {
    func token(for provider: BackendProvider) throws -> String?
    func setToken(_ token: String?, for provider: BackendProvider) throws
}

public final class VolatileBackendBearerTokenStore: BackendBearerTokenStoring {
    private var tokens: [BackendProvider: String]

    public init(tokens: [BackendProvider: String] = [:]) {
        self.tokens = tokens
    }

    public func token(for provider: BackendProvider) throws -> String? {
        tokens[provider]
    }

    public func setToken(_ token: String?, for provider: BackendProvider) throws {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedToken.isEmpty {
            tokens.removeValue(forKey: provider)
        } else {
            tokens[provider] = trimmedToken
        }
    }
}
```

- [ ] **Step 4: Update RecitationViewModel to use the token store**

In `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift`, make these focused edits.

Add this published message near the existing backend validation published properties:

```swift
@Published public private(set) var backendBearerTokenPersistenceMessage: String?
```

Replace the current token property:

```swift
@Published public var backendBearerTokenText = ""
```

with:

```swift
@Published public var backendBearerTokenText = "" {
    didSet {
        persistBackendBearerTokenIfNeeded()
    }
}
```

Add these private properties near `private var preferencesStore`:

```swift
private let backendBearerTokenStore: BackendBearerTokenStoring
private var isLoadingBackendBearerToken = false
```

Change the initializer signature to include the token store:

```swift
public init(
    socketClient: BackendSocketing? = nil,
    audioStreamer: AudioStreaming,
    voiceActivityDetector: VoiceActivityDetecting,
    preferencesStore: RecitationPreferencesStoring = UserDefaultsRecitationPreferencesStore(),
    backendBearerTokenStore: BackendBearerTokenStoring = VolatileBackendBearerTokenStore()
) {
```

Inside the initializer body, after `self.preferencesStore = preferencesStore`, add:

```swift
self.backendBearerTokenStore = backendBearerTokenStore
```

At the end of the initializer, after `validateBackendURLText()`, add:

```swift
loadBackendBearerToken(for: customBackendProvider)
```

In `selectBackendPreset(_:)`, after the `switch preset` block and before `validateBackendURLText()`, add:

```swift
if preset == .custom {
    loadBackendBearerToken(for: customBackendProvider)
}
```

Replace `selectCustomBackendProvider(_:)` with:

```swift
public func selectCustomBackendProvider(_ provider: BackendProvider) {
    customBackendProvider = provider
    preferencesStore.customBackendProvider = provider
    loadBackendBearerToken(for: provider)
    validateBackendURLText()
}
```

Add these private helper methods before `private var recitationScopeSelection`:

```swift
private func loadBackendBearerToken(for provider: BackendProvider) {
    isLoadingBackendBearerToken = true
    defer {
        isLoadingBackendBearerToken = false
    }

    do {
        backendBearerTokenText = try backendBearerTokenStore.token(for: provider) ?? ""
        backendBearerTokenPersistenceMessage = nil
    } catch {
        backendBearerTokenText = ""
        backendBearerTokenPersistenceMessage = "Could not read saved backend token. Paste it again before recording."
    }
}

private func persistBackendBearerTokenIfNeeded() {
    guard !isLoadingBackendBearerToken, backendPreset == .custom else { return }

    let trimmedToken = backendBearerTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
    let tokenToStore = trimmedToken.isEmpty ? nil : trimmedToken
    do {
        try backendBearerTokenStore.setToken(tokenToStore, for: customBackendProvider)
        backendBearerTokenPersistenceMessage = nil
    } catch {
        backendBearerTokenPersistenceMessage = "Token will be used for this session only. Keychain update failed."
    }
}
```

Keep `backendAuthorizationToken` unchanged except for using the already-trimmed `backendBearerTokenText` as it does today.

- [ ] **Step 5: Run focused ViewModel tests and verify they pass**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationViewModelTests
```

Expected: PASS for `RecitationViewModelTests`.

- [ ] **Step 6: Commit Task 2**

Run:

```bash
git add ios/TarteelClientCore/Sources/TarteelClientCore/RecitationClientProtocols.swift ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift
git commit -m "feat: persist backend tokens through storage boundary"
```

---

### Task 3: Add macOS Keychain Store and Modal Injection

**Files:**
- Modify: `tests/test_macos_app_project.py`
- Create: `ios/TarteelPrototype/TarteelPrototypeMac/App/KeychainBackendBearerTokenStore.swift`
- Modify: `ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift`
- Modify: `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing macOS source guardrails**

In `tests/test_macos_app_project.py`, update `test_project_includes_shared_core_files_in_both_app_targets` so `BackendBearerTokenStore.swift` is not expected as a shared file. Then add this assertion block near the end of that test:

```python
        self.assertIn("App/KeychainBackendBearerTokenStore.swift", mac_paths)
        self.assertNotIn("App/KeychainBackendBearerTokenStore.swift", iphone_paths)
```

In `test_macos_sources_define_desktop_app_surface`, add:

```python
        keychain_source = (MAC_APP_SOURCE_ROOT / "KeychainBackendBearerTokenStore.swift").read_text(encoding="utf-8")
```

Then add these assertions before the end of the test:

```python
        self.assertIn("UserDefaultsRecitationPreferencesStore(fallbackValues: .modalPrimary)", app_source)
        self.assertIn("KeychainBackendBearerTokenStore()", app_source)
        self.assertIn("import Security", keychain_source)
        self.assertIn("SecItemCopyMatching", keychain_source)
        self.assertIn("SecItemAdd", keychain_source)
        self.assertIn("SecItemUpdate", keychain_source)
        self.assertIn("SecItemDelete", keychain_source)
        self.assertIn("dev.mostafa.TarteelPrototypeMac.backend-token", keychain_source)
```

- [ ] **Step 2: Run macOS source guardrails and verify they fail**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: FAIL because `KeychainBackendBearerTokenStore.swift` is missing and the macOS app does not inject Modal defaults or Keychain storage.

- [ ] **Step 3: Create the macOS Keychain token store**

Create `ios/TarteelPrototype/TarteelPrototypeMac/App/KeychainBackendBearerTokenStore.swift`:

```swift
import Foundation
import Security

final class KeychainBackendBearerTokenStore: BackendBearerTokenStoring {
    private let service: String

    init(service: String = "dev.mostafa.TarteelPrototypeMac.backend-token") {
        self.service = service
    }

    func token(for provider: BackendProvider) throws -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainBackendBearerTokenStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setToken(_ token: String?, for provider: BackendProvider) throws {
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedToken.isEmpty {
            try deleteToken(for: provider)
            return
        }

        let data = Data(trimmedToken.utf8)
        var query = baseQuery(for: provider)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainBackendBearerTokenStoreError.unhandledStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainBackendBearerTokenStoreError.unhandledStatus(addStatus)
        }
    }

    private func deleteToken(for provider: BackendProvider) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainBackendBearerTokenStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for provider: BackendProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}

private enum KeychainBackendBearerTokenStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
```

- [ ] **Step 4: Inject Modal defaults and Keychain storage in the macOS app**

Replace the `@StateObject` initialization in `ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift` with:

```swift
@StateObject private var viewModel = RecitationViewModel(
    audioStreamer: MacMicrophoneAudioStreamer(),
    voiceActivityDetector: VoiceActivityDetector(),
    preferencesStore: UserDefaultsRecitationPreferencesStore(fallbackValues: .modalPrimary),
    backendBearerTokenStore: KeychainBackendBearerTokenStore()
)
```

Do not change `ios/TarteelPrototype/TarteelPrototype/App/TarteelPrototypeApp.swift`; the iPhone app should keep its existing initializer and therefore keep simulator-friendly defaults plus volatile token storage.

- [ ] **Step 5: Add Keychain source file to the macOS Xcode target only**

Modify `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj`.

In the `PBXBuildFile section`, add:

```text
		200000000000000000000021 /* KeychainBackendBearerTokenStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = 200000000000000000000106 /* KeychainBackendBearerTokenStore.swift */; };
```

In the `PBXFileReference section`, add:

```text
		200000000000000000000106 /* KeychainBackendBearerTokenStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App/KeychainBackendBearerTokenStore.swift; sourceTree = "<group>"; };
```

In the `TarteelPrototypeMac` `PBXGroup` children list, add this entry after `MacMicrophoneAudioStreamer.swift`:

```text
				200000000000000000000106 /* KeychainBackendBearerTokenStore.swift */,
```

In the `TarteelPrototypeMac` `PBXSourcesBuildPhase` files list, add this entry after `MacMicrophoneAudioStreamer.swift in Sources`:

```text
				200000000000000000000021 /* KeychainBackendBearerTokenStore.swift in Sources */,
```

Do not add this file to the iPhone target.

- [ ] **Step 6: Run macOS source guardrails and verify they pass**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: PASS for `tests.test_macos_app_project`.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add tests/test_macos_app_project.py ios/TarteelPrototype/TarteelPrototypeMac/App/KeychainBackendBearerTokenStore.swift ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj
git commit -m "feat: use keychain modal token store on macos"
```

---

### Task 4: Update macOS Settings Copy and Error Feedback

**Files:**
- Modify: `tests/test_macos_app_project.py`
- Modify: `ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift`

- [ ] **Step 1: Write failing Settings source guardrails**

In `tests/test_macos_app_project.py`, update `test_macos_settings_show_validation_and_disabled_state_feedback` with these assertions:

```python
        self.assertIn("tokenHelpText", settings_source)
        self.assertIn("Saved securely in macOS Keychain", settings_source)
        self.assertIn("backendBearerTokenPersistenceMessage", settings_source)
        self.assertNotIn("viewModel.customBackendProvider.tokenHelpText)", settings_source)
```

- [ ] **Step 2: Run focused source guardrails and verify they fail**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: FAIL because `MacSettingsView.swift` still directly displays `viewModel.customBackendProvider.tokenHelpText` and does not render token persistence errors.

- [ ] **Step 3: Update MacSettingsView token copy and error display**

In `ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift`, replace:

```swift
Text(viewModel.customBackendProvider.tokenHelpText)
    .font(.caption)
    .foregroundStyle(.secondary)
```

with:

```swift
Text(tokenHelpText)
    .font(.caption)
    .foregroundStyle(.secondary)

if let tokenMessage = viewModel.backendBearerTokenPersistenceMessage {
    Label(tokenMessage, systemImage: "key.horizontal")
        .font(.caption)
        .foregroundStyle(.orange)
}
```

Then add this computed property inside `MacSettingsView`, after `body`:

```swift
private var tokenHelpText: String {
    switch viewModel.customBackendProvider {
    case .modal:
        return "Saved securely in macOS Keychain for this Mac user."
    case .generic, .runPod:
        return viewModel.customBackendProvider.tokenHelpText
    }
}
```

- [ ] **Step 4: Run focused source guardrails and verify they pass**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: PASS for `tests.test_macos_app_project`.

- [ ] **Step 5: Commit Task 4**

Run:

```bash
git add tests/test_macos_app_project.py ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift
git commit -m "feat: show macos keychain token feedback"
```

---

### Task 5: Update Docs and Harness State

**Files:**
- Modify: `README.md`
- Modify: `docs/modal-serverless.md`
- Modify: `session-handoff.md`
- Modify: `feature_list.json`

- [ ] **Step 1: Update README Modal/Apple copy**

In `README.md`, replace the current token paragraph under the Apple Custom provider section:

```text
Direct iOS-to-RunPod serverless testing is prototype-only because the app sends `Authorization: Bearer <token>` on the WebSocket request. Enter that key in the local bearer-token field; do not commit it or put it in docs. The serverless worker keeps the same `/ws/recitation` contract and also exposes `/ping` for RunPod health checks. See `docs/runpod-serverless.md` for the Dockerfile, endpoint settings, key workflow, and replay checks.
```

with:

```text
Direct Apple-to-serverless testing is prototype-only because the app sends `Authorization: Bearer <token>` on the WebSocket request. Enter that key locally; do not commit it or put it in docs. The iPhone prototype keeps the token memory-only. The macOS prototype stores the selected Custom provider token in macOS Keychain so it survives app relaunch without writing the secret to UserDefaults. The serverless worker keeps the same `/ws/recitation` contract and also exposes `/ping` for health checks.
```

- [ ] **Step 2: Update Modal docs**

In `docs/modal-serverless.md`, replace:

```text
The Apple prototypes can use this through Settings -> Custom -> Provider:
Modal. The token field is memory-only.
```

with:

```text
The Apple prototypes can use this through Settings -> Custom -> Provider:
Modal. The iPhone prototype keeps the token memory-only. The macOS prototype
uses Modal as its first-launch Custom default and stores the Modal bearer token
in macOS Keychain after the user enters it once.
```

- [ ] **Step 3: Update handoff**

In `session-handoff.md`, add the following under `## Verified Now` after the latest-slice bullets:

```markdown
- Modal is now the macOS prototype's first-launch Custom provider default.
- The macOS prototype injects `UserDefaultsRecitationPreferencesStore(fallbackValues: .modalPrimary)`, so persisted user preferences still override the Modal fallback.
- The macOS prototype stores the selected Custom provider bearer token in macOS Keychain through `KeychainBackendBearerTokenStore`; the iPhone prototype remains memory-only.
```

Add this risk under `## Current Risks`:

```markdown
- macOS Keychain token persistence needs a manual quit/reopen check with a real token before claiming end-to-end user workflow proof.
```

- [ ] **Step 4: Update feature evidence**

In `feature_list.json`, update `last_updated` to:

```json
"last_updated": "2026-06-03"
```

Append this evidence string to the `mobile-001` `evidence` array:

```json
"The macOS prototype now defaults to Custom/Modal through configurable client preference fallbacks and stores the selected Custom provider bearer token in macOS Keychain; iPhone simulator defaults and memory-only token behavior remain unchanged."
```

Keep JSON valid and do not add a second `in_progress` feature.

- [ ] **Step 5: Commit Task 5**

Run:

```bash
git add README.md docs/modal-serverless.md session-handoff.md feature_list.json
git commit -m "docs: document macos modal keychain defaults"
```

---

### Task 6: Verification

**Files:**
- All files changed in Tasks 1 through 5.

- [ ] **Step 1: Run Swift client core tests**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

Expected: PASS. Record the number of checks/tests in `codex-progress.md`.

- [ ] **Step 2: Run Apple source guardrails**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v
```

Expected: PASS. Record the pass count in `codex-progress.md`.

- [ ] **Step 3: Build the macOS app target**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

If sandboxed Xcode cache access blocks the command, rerun with approval using the same command.

- [ ] **Step 4: Build the iPhone app target**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

If sandboxed CoreSimulator or SwiftPM cache access blocks the command, rerun with approval using the same command.

- [ ] **Step 5: Validate structured project state**

Run:

```bash
uv run python -B -m json.tool feature_list.json
```

Expected: valid JSON output.

Run:

```bash
uv run python -B -c "import json; data=json.load(open('feature_list.json', encoding='utf-8')); active=[f['id'] for f in data['features'] if f['status']=='in_progress']; print(active); assert len(active) <= 1"
```

Expected:

```text
[]
```

- [ ] **Step 6: Run full deterministic Python suite**

Run:

```bash
uv run python -B -m unittest discover -s tests -v
```

Expected: PASS. Record the pass count in `codex-progress.md`.

- [ ] **Step 7: Run compile and whitespace checks**

Run:

```bash
uv run python -m compileall -q tarteel_realtime tests
git diff --check
```

Expected: both commands exit 0.

- [ ] **Step 8: Manual macOS Keychain workflow check**

Run or launch the macOS app, then perform these steps:

1. Open Settings.
2. Confirm first-launch values are `Custom`, `Modal`, and `wss://moabdelmoez--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation` when no prior backend preferences exist.
3. Paste the Modal bearer token in the secure field.
4. Quit the app.
5. Reopen the app.
6. Confirm the token field is populated from Keychain.
7. Start a Modal recording and confirm the backend does not reject the WebSocket for missing bearer auth.

Do not paste the token into logs, docs, git commits, or the final answer.

- [ ] **Step 9: Update progress log verification details**

Prepend a new session entry in `codex-progress.md` under `## Session Log`.
The entry must name the completed Modal-default and Keychain-token work, list
the exact commands executed in Steps 1 through 8 with their observed pass/build
results, and preserve these risk notes:

```markdown
- The token persistence path is build/source verified; manual Keychain persistence should still be exercised by entering a real token, quitting the app, reopening, and starting a Modal recording if Step 8 was not completed with a real token.
- Fresh Modal replay evidence after the CUDA image fix remains separate from this UI/storage slice unless Step 8 included a real Modal recitation.
```

- [ ] **Step 10: Commit final verification evidence**

Run:

```bash
git add codex-progress.md session-handoff.md feature_list.json
git commit -m "docs: record modal keychain verification"
```

---

## Self-Review Checklist

- [ ] The shared default remains `Simulator`.
- [ ] The macOS app injects `.modalPrimary` defaults.
- [ ] The iPhone app initializer is unchanged.
- [ ] No bearer token value is committed or printed.
- [ ] The token is not stored in `UserDefaultsRecitationPreferencesStore`.
- [ ] Provider-specific tokens use separate Keychain accounts.
- [ ] Clearing the token deletes the provider's Keychain item.
- [ ] `BackendWebSocketClient` transport behavior remains unchanged.
- [ ] The macOS Keychain source is only in the macOS Xcode target.
- [ ] Source guardrails, Swift package tests, macOS build, iPhone build, JSON validation, full Python suite, compile check, and whitespace check have run.
