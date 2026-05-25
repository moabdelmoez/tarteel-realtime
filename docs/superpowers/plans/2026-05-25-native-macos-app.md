# Native macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a build-verified native macOS SwiftUI prototype alongside the existing iPhone app while preserving the current WebSocket recitation contract and iPhone UI.

**Architecture:** Move platform-neutral recording orchestration and WebSocket transport into `TarteelClientCore` behind protocols, then inject platform-specific microphone and VAD implementations from the iPhone and macOS targets. Keep the existing direct shared-source-file Xcode pattern for this slice, and add a separate native macOS target in the current Xcode project.

**Tech Stack:** SwiftUI, Combine, AVFoundation, CoreML, FluidAudio, URLSessionWebSocketTask, SwiftPM tests, Xcode project source guardrails, `uv` Python unittest harness.

---

## File Structure

Create or move shared Swift code under `ios/TarteelClientCore/Sources/TarteelClientCore`:

- `RecitationClientProtocols.swift`: protocol boundaries for socket, audio streaming, and VAD.
- `RecitationPreferencesStore.swift`: non-secret preference store protocol and `UserDefaults` implementation.
- `BackendWebSocketClient.swift`: shared WebSocket transport implementation moved from the iPhone app target.
- `RecitationMode.swift`: shared Auto versus Surah selection enum moved from the app target.
- `RecitationViewModel.swift`: shared `ObservableObject` orchestration moved from the app target and changed to inject protocols.

Keep platform code in app target folders:

- `ios/TarteelPrototype/TarteelPrototype/App/MicrophoneAudioStreamer.swift`: iPhone audio streamer, conformed to the shared protocol.
- `ios/TarteelPrototype/TarteelPrototype/App/VoiceActivityDetector.swift`: existing FluidAudio/CoreML VAD, conformed to the shared protocol and reused by both app targets.
- `ios/TarteelPrototype/TarteelPrototype/App/TarteelPrototypeApp.swift`: injects iPhone audio and VAD into the shared view model.
- `ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift`: macOS app entry point and Settings scene.
- `ios/TarteelPrototype/TarteelPrototypeMac/App/MacContentView.swift`: desktop recitation UI and status console.
- `ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift`: native macOS Settings content.
- `ios/TarteelPrototype/TarteelPrototypeMac/App/MacMicrophoneAudioStreamer.swift`: macOS microphone capture with `AVAudioEngine`.
- `ios/TarteelPrototype/TarteelPrototypeMac/Info.plist`: macOS-specific plist.

Add tests and guardrails:

- `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationPreferencesStoreTests.swift`
- `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift`
- `tests/test_macos_app_project.py`
- extend `tests/test_ios_recitation_scope_ui.py`
- extend `tests/test_ios_websocket_client.py`
- extend `clean-state-checklist.md`, `feature_list.json`, `ios/README.md`, `codex-progress.md`, and `session-handoff.md`

---

### Task 1: Add Failing Source Guardrails For macOS Shape

**Files:**
- Create: `tests/test_macos_app_project.py`
- Modify: `tests/test_ios_recitation_scope_ui.py`
- Modify: `tests/test_ios_websocket_client.py`

- [ ] **Step 1: Add macOS project/source guardrails**

Create `tests/test_macos_app_project.py` with:

```python
from pathlib import Path
import plistlib
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype.xcodeproj" / "project.pbxproj"
MAC_APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototypeMac"
MAC_APP_SOURCE_ROOT = MAC_APP_ROOT / "App"
MAC_PLIST_PATH = MAC_APP_ROOT / "Info.plist"
MODEL_NAME = "silero-vad-unified-256ms-v6.0.0.mlmodelc"


class MacOSAppProjectTests(unittest.TestCase):
    def test_project_declares_native_macos_target(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")

        self.assertIn("TarteelPrototypeMac", project)
        self.assertIn("TarteelPrototypeMac.app", project)
        self.assertIn('SDKROOT = macosx;', project)
        self.assertIn("MACOSX_DEPLOYMENT_TARGET = 14.0;", project)
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER = dev.mostafa.TarteelPrototypeMac;', project)
        self.assertIn('SUPPORTED_PLATFORMS = "macosx";', project)
        self.assertIn('productType = "com.apple.product-type.application";', project)

    def test_project_includes_shared_core_files_in_both_app_targets(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")

        for filename in [
            "AudioChunkPayload.swift",
            "BackendEndpointPreset.swift",
            "BackendWebSocketClient.swift",
            "RecitationClientProtocols.swift",
            "RecitationEvent.swift",
            "RecitationMode.swift",
            "RecitationPreferencesStore.swift",
            "RecitationScopeSelection.swift",
            "RecitationSessionState.swift",
            "RecitationViewModel.swift",
            "SurahCatalog.swift",
            "VoiceActivityPayload.swift",
        ]:
            self.assertIn(filename, project)

    def test_project_includes_vad_model_resource_for_iphone_and_macos(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")

        self.assertGreaterEqual(project.count(f"{MODEL_NAME} in Resources"), 2)
        self.assertIn(MODEL_NAME, project)

    def test_macos_info_plist_is_not_ios_plist(self) -> None:
        with MAC_PLIST_PATH.open("rb") as file:
            plist = plistlib.load(file)

        self.assertEqual(
            plist["NSMicrophoneUsageDescription"],
            "Microphone access streams recitation audio to your selected development backend.",
        )
        self.assertIn("NSAppTransportSecurity", plist)
        self.assertNotIn("LSRequiresIPhoneOS", plist)
        self.assertNotIn("UIApplicationSceneManifest", plist)
        self.assertNotIn("UILaunchScreen", plist)

    def test_macos_sources_define_desktop_app_surface(self) -> None:
        app_source = (MAC_APP_SOURCE_ROOT / "TarteelPrototypeMacApp.swift").read_text(encoding="utf-8")
        content_source = (MAC_APP_SOURCE_ROOT / "MacContentView.swift").read_text(encoding="utf-8")
        settings_source = (MAC_APP_SOURCE_ROOT / "MacSettingsView.swift").read_text(encoding="utf-8")
        audio_source = (MAC_APP_SOURCE_ROOT / "MacMicrophoneAudioStreamer.swift").read_text(encoding="utf-8")

        self.assertIn("@main", app_source)
        self.assertIn("Settings", app_source)
        self.assertIn("MacContentView", app_source)
        self.assertIn("CommandGroup", app_source)
        self.assertIn("MacSettingsView", settings_source)
        self.assertIn("EventHistoryPanel", content_source)
        self.assertIn("SettingsLink", content_source)
        self.assertIn("AVCaptureDevice.requestAccess", audio_source)
        self.assertIn("AVAudioEngine", audio_source)
        self.assertNotIn("AVAudioSession", audio_source)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Strengthen iPhone UI guardrail to reject visual drift**

Append these assertions to `IOSRecitationScopeUITests.test_content_view_keeps_recitation_controls_on_home_screen` in `tests/test_ios_recitation_scope_ui.py`:

```python
        self.assertIn("SettingsSheet(viewModel: viewModel)", source)
        self.assertIn("VoiceActivityIndicator(isActive: viewModel.isRecording)", source)
        self.assertIn("Image(systemName: viewModel.isRecording ? \"xmark\" : \"mic.fill\")", source)
        self.assertIn("DebugStatusPanel(", source)
```

- [ ] **Step 3: Strengthen transport guardrail for moved shared socket**

In `tests/test_ios_websocket_client.py`, change `APP_ROOT` to include the core root and read the moved socket source:

```python
REPO_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = REPO_ROOT / "ios" / "TarteelPrototype" / "TarteelPrototype" / "App"
CORE_ROOT = REPO_ROOT / "ios" / "TarteelClientCore" / "Sources" / "TarteelClientCore"
```

Then change the two socket-source reads in `test_websocket_client_waits_until_socket_is_open_before_streaming` and `test_websocket_client_can_attach_runpod_bearer_token` to:

```python
        source = (CORE_ROOT / "BackendWebSocketClient.swift").read_text(encoding="utf-8")
```

- [ ] **Step 4: Run guardrails and verify they fail for missing macOS work**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client -v
```

Expected: FAIL. The macOS test should fail because `TarteelPrototypeMac` files and project target do not exist yet. The WebSocket test should fail because `BackendWebSocketClient.swift` has not moved to `TarteelClientCore` yet.

- [ ] **Step 5: Commit failing guardrails**

```bash
git add tests/test_macos_app_project.py tests/test_ios_recitation_scope_ui.py tests/test_ios_websocket_client.py
git commit -m "test: add macOS app guardrails"
```

---

### Task 2: Add Shared Core Protocols And Preference Store

**Files:**
- Create: `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationClientProtocols.swift`
- Create: `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationPreferencesStore.swift`
- Create: `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationMode.swift`
- Create: `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationPreferencesStoreTests.swift`

- [ ] **Step 1: Write preference store tests**

Create `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationPreferencesStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationPreferencesStoreTests
```

Expected: FAIL with missing `UserDefaultsRecitationPreferencesStore` and `RecitationMode`.

- [ ] **Step 3: Add shared protocols**

Create `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationClientProtocols.swift`:

```swift
import Foundation

public protocol BackendSocketing: AnyObject {
    func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws
    func send(_ payload: AudioChunkPayload) async throws
    func disconnect()
}

public protocol AudioStreaming: AnyObject {
    func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws
    func stop()
}

public protocol VoiceActivityDetecting: AnyObject {
    func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload?
    func reset() async
}
```

- [ ] **Step 4: Add shared recitation mode**

Create `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationMode.swift`:

```swift
import Foundation

public enum RecitationMode: String, CaseIterable, Hashable, Identifiable, Sendable {
    case autoDetect
    case selectedSurah

    public var id: String { rawValue }
}
```

- [ ] **Step 5: Add non-secret preferences store**

Create `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationPreferencesStore.swift`:

```swift
import Foundation

public protocol RecitationPreferencesStoring {
    var backendPreset: BackendEndpointPreset { get set }
    var customBackendURLText: String { get set }
    var recitationMode: RecitationMode { get set }
    var selectedSurahID: Int { get set }
}

public struct UserDefaultsRecitationPreferencesStore: RecitationPreferencesStoring {
    private enum Key {
        static let backendPreset = "tarteel.backendPreset"
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
```

- [ ] **Step 6: Run focused Swift tests**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationPreferencesStoreTests
```

Expected: PASS.

- [ ] **Step 7: Commit shared core boundaries**

```bash
git add ios/TarteelClientCore/Sources/TarteelClientCore/RecitationClientProtocols.swift ios/TarteelClientCore/Sources/TarteelClientCore/RecitationPreferencesStore.swift ios/TarteelClientCore/Sources/TarteelClientCore/RecitationMode.swift ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationPreferencesStoreTests.swift
git commit -m "feat: add shared client protocols and preferences"
```

---

### Task 3: Move WebSocket Transport Into Shared Core

**Files:**
- Create: `ios/TarteelClientCore/Sources/TarteelClientCore/BackendWebSocketClient.swift`
- Delete: `ios/TarteelPrototype/TarteelPrototype/App/BackendWebSocketClient.swift`
- Modify: `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj`

- [ ] **Step 1: Move transport source into core**

Create `ios/TarteelClientCore/Sources/TarteelClientCore/BackendWebSocketClient.swift` with the current transport implementation plus protocol conformance:

```swift
import Foundation

public final class BackendWebSocketClient: BackendSocketing {
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init() {}

    public func connect(
        url: URL,
        authorizationToken: String? = nil,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        disconnect()

        var request = URLRequest(url: url)
        if let authorizationToken, !authorizationToken.isEmpty {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()

        do {
            try await waitUntilConnected(task)
        } catch {
            disconnect()
            throw error
        }

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(onEvent: onEvent)
        }
    }

    public func send(_ payload: AudioChunkPayload) async throws {
        guard let task else { return }
        let data = try encoder.encode(payload)
        let text = String(decoding: data, as: UTF8.self)
        try await task.send(.string(text))
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receiveLoop(onEvent: @escaping @Sendable (RecitationEvent) -> Void) async {
        guard let task else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if let event = try decodeEvent(from: message) {
                    onEvent(event)
                }
            } catch {
                return
            }
        }
    }

    private func waitUntilConnected(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }

    private func decodeEvent(from message: URLSessionWebSocketTask.Message) throws -> RecitationEvent? {
        switch message {
        case .data(let data):
            return try decoder.decode(RecitationEvent.self, from: data)
        case .string(let text):
            return try decoder.decode(RecitationEvent.self, from: Data(text.utf8))
        @unknown default:
            return nil
        }
    }
}
```

- [ ] **Step 2: Remove old app-local transport file**

Delete `ios/TarteelPrototype/TarteelPrototype/App/BackendWebSocketClient.swift`.

- [ ] **Step 3: Update Xcode project file reference**

In `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj`, keep the existing build-file ID for `BackendWebSocketClient.swift` if convenient, but change its file reference path from:

```text
path = App/BackendWebSocketClient.swift;
```

to:

```text
path = ../TarteelClientCore/Sources/TarteelClientCore/BackendWebSocketClient.swift;
```

Leave it in the iPhone target sources. Add the same file to the macOS target sources in Task 6.

- [ ] **Step 4: Run focused Swift package tests**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

Expected: PASS.

- [ ] **Step 5: Run focused Python transport guardrails**

Run:

```bash
uv run python -B -m unittest tests.test_ios_websocket_client -v
```

Expected: PASS.

- [ ] **Step 6: Commit shared transport move**

```bash
git add ios/TarteelClientCore/Sources/TarteelClientCore/BackendWebSocketClient.swift ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj tests/test_ios_websocket_client.py
git add -u ios/TarteelPrototype/TarteelPrototype/App/BackendWebSocketClient.swift
git commit -m "refactor: share websocket client across apple targets"
```

---

### Task 4: Move Recording Orchestration Into Shared Core

**Files:**
- Create: `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift`
- Delete: `ios/TarteelPrototype/TarteelPrototype/App/RecitationViewModel.swift`
- Modify: `ios/TarteelPrototype/TarteelPrototype/App/TarteelPrototypeApp.swift`
- Modify: `ios/TarteelPrototype/TarteelPrototype/App/MicrophoneAudioStreamer.swift`
- Modify: `ios/TarteelPrototype/TarteelPrototype/App/VoiceActivityDetector.swift`
- Modify: `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj`
- Create: `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift`

- [ ] **Step 1: Add shared view-model tests**

Create `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift`:

```swift
import Foundation
import XCTest
@testable import TarteelClientCore

@MainActor
final class RecitationViewModelTests: XCTestCase {
    func testStartRecordingConnectsWithScopedURLAndBearerToken() async throws {
        let socket = FakeSocketClient()
        let audio = FakeAudioStreamer()
        let vad = FakeVoiceActivityDetector()
        let preferences = InMemoryPreferencesStore()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: vad,
            preferencesStore: preferences
        )

        viewModel.selectBackendPreset(.custom)
        viewModel.backendURLText = "example.api.runpod.ai"
        viewModel.runPodAPIKeyText = "secret-token"
        viewModel.selectRecitationMode(.selectedSurah)
        viewModel.selectedSurahID = 108

        try await viewModel.startRecording()

        XCTAssertEqual(socket.connectedURL?.absoluteString, "wss://example.api.runpod.ai/ws/recitation?scope=108")
        XCTAssertEqual(socket.authorizationToken, "secret-token")
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(viewModel.connectionStatus, "Streaming")
    }

    func testAudioChunksIncludeVADPayloadAndIncrementSequence() async throws {
        let socket = FakeSocketClient()
        let audio = FakeAudioStreamer()
        let vad = FakeVoiceActivityDetector()
        vad.nextPayload = VoiceActivityPayload(probability: 0.9, isSpeechActive: true, event: .speechStart)
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: vad,
            preferencesStore: InMemoryPreferencesStore()
        )

        try await viewModel.startRecording()
        audio.emit(pcm: Data([1, 2, 3, 4]), sampleRate: 16_000)
        await Task.yield()

        XCTAssertEqual(socket.sentPayloads.count, 1)
        XCTAssertEqual(socket.sentPayloads[0].sequenceNumber, 0)
        XCTAssertEqual(socket.sentPayloads[0].sampleRateHz, 16_000)
        XCTAssertEqual(socket.sentPayloads[0].voiceActivity?.isSpeechActive, true)
    }

    func testSocketEventsReduceSessionState() async throws {
        let socket = FakeSocketClient()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: InMemoryPreferencesStore()
        )

        try await viewModel.startRecording()
        socket.emit(RecitationEvent(
            type: .locked,
            transcript: "قل هو الله احد",
            confidence: 0.97,
            chunkSequence: 2,
            reason: "exact_match",
            candidateRefs: [],
            ayahText: "قل هو الله احد",
            ayahRef: "112:1",
            startRef: "112:1:1",
            nextExpectedRef: "112:1:2",
            consumedWords: 4,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        ))
        await Task.yield()

        XCTAssertEqual(viewModel.state.currentAyahRef, "112:1")
        XCTAssertEqual(viewModel.state.headline, "Locked on 112:1")
        XCTAssertEqual(viewModel.connectionStatus, "Receiving events")
    }

    func testStopRecordingDisconnectsAndResetsVAD() async throws {
        let socket = FakeSocketClient()
        let audio = FakeAudioStreamer()
        let vad = FakeVoiceActivityDetector()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: audio,
            voiceActivityDetector: vad,
            preferencesStore: InMemoryPreferencesStore()
        )

        try await viewModel.startRecording()
        viewModel.stopRecording()
        await Task.yield()

        XCTAssertTrue(socket.didDisconnect)
        XCTAssertTrue(audio.didStop)
        XCTAssertTrue(vad.didReset)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(viewModel.state.headline, "Stopped")
    }
}

private final class FakeSocketClient: BackendSocketing {
    var connectedURL: URL?
    var authorizationToken: String?
    var sentPayloads: [AudioChunkPayload] = []
    var didDisconnect = false
    private var onEvent: (@Sendable (RecitationEvent) -> Void)?

    func connect(
        url: URL,
        authorizationToken: String?,
        onEvent: @escaping @Sendable (RecitationEvent) -> Void
    ) async throws {
        self.connectedURL = url
        self.authorizationToken = authorizationToken
        self.onEvent = onEvent
    }

    func send(_ payload: AudioChunkPayload) async throws {
        sentPayloads.append(payload)
    }

    func disconnect() {
        didDisconnect = true
    }

    func emit(_ event: RecitationEvent) {
        onEvent?(event)
    }
}

@MainActor
private final class FakeAudioStreamer: AudioStreaming {
    var didStop = false
    private var onChunk: (@Sendable (Data, Int) -> Void)?

    func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws {
        self.onChunk = onChunk
    }

    func stop() {
        didStop = true
    }

    func emit(pcm: Data, sampleRate: Int) {
        onChunk?(pcm, sampleRate)
    }
}

private final class FakeVoiceActivityDetector: VoiceActivityDetecting {
    var nextPayload: VoiceActivityPayload?
    var didReset = false

    func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload? {
        nextPayload
    }

    func reset() async {
        didReset = true
    }
}

private struct InMemoryPreferencesStore: RecitationPreferencesStoring {
    var backendPreset: BackendEndpointPreset = .simulator
    var customBackendURLText: String = ""
    var recitationMode: RecitationMode = .autoDetect
    var selectedSurahID: Int = 108
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationViewModelTests
```

Expected: FAIL because `RecitationViewModel` is not in the core package and protocol injection is not implemented.

- [ ] **Step 3: Create shared view model**

Create `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift` by moving the existing app-local implementation and using this public initializer and public start/stop methods:

```swift
import Combine
import Foundation

@MainActor
public final class RecitationViewModel: ObservableObject {
    @Published public private(set) var state = RecitationSessionState()
    @Published public private(set) var isRecording = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var backendPreset: BackendEndpointPreset
    @Published public private(set) var recitationMode: RecitationMode
    @Published public private(set) var connectionStatus = "Idle"
    @Published public var backendURLText: String
    @Published public var selectedSurahID: Int
    @Published public var runPodAPIKeyText = ""

    private let socketClient: BackendSocketing
    private let audioStreamer: AudioStreaming
    private let voiceActivityDetector: VoiceActivityDetecting
    private var preferencesStore: RecitationPreferencesStoring
    private var sequenceNumber = 0
    private var customBackendURLText = ""

    public init(
        socketClient: BackendSocketing = BackendWebSocketClient(),
        audioStreamer: AudioStreaming,
        voiceActivityDetector: VoiceActivityDetecting,
        preferencesStore: RecitationPreferencesStoring = UserDefaultsRecitationPreferencesStore()
    ) {
        self.socketClient = socketClient
        self.audioStreamer = audioStreamer
        self.voiceActivityDetector = voiceActivityDetector
        self.preferencesStore = preferencesStore

        let preset = preferencesStore.backendPreset
        self.backendPreset = preset
        self.customBackendURLText = preferencesStore.customBackendURLText
        self.recitationMode = preferencesStore.recitationMode
        self.selectedSurahID = preferencesStore.selectedSurahID
        self.backendURLText = preset.urlText(currentCustomURLText: preferencesStore.customBackendURLText)
    }

    public func selectBackendPreset(_ preset: BackendEndpointPreset) {
        if backendPreset == .custom {
            customBackendURLText = backendURLText
            preferencesStore.customBackendURLText = backendURLText
        }

        backendPreset = preset
        preferencesStore.backendPreset = preset
        switch preset {
        case .simulator:
            backendURLText = preset.defaultURLText
        case .custom:
            backendURLText = customBackendURLText
        }
    }

    public func selectRecitationMode(_ mode: RecitationMode) {
        recitationMode = mode
        preferencesStore.recitationMode = mode
    }

    public func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }

        Task {
            await startRecordingHandlingErrors()
        }
    }

    public func startRecording() async throws {
        errorMessage = nil
        connectionStatus = "Connecting"
        sequenceNumber = 0
        preferencesStore.selectedSurahID = selectedSurahID
        if backendPreset == .custom {
            customBackendURLText = backendURLText
            preferencesStore.customBackendURLText = backendURLText
        }
        await voiceActivityDetector.reset()
        state = RecitationSessionState(
            phase: .connecting,
            headline: "Connecting",
            detail: "Preparing microphone"
        )

        let urlText = backendPreset.recordingURLText(
            currentURLText: backendURLText,
            recitationScope: recitationScopeSelection
        )
        if urlText != backendURLText {
            backendURLText = urlText
        }
        guard let backendURL = URL(string: urlText) else {
            throw RecitationViewModelError.invalidBackendURL
        }

        try await socketClient.connect(
            url: backendURL,
            authorizationToken: runPodAuthorizationToken
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                let currentState = self.state
                let nextState = currentState.applying(event)
                if nextState != currentState {
                    self.state = nextState
                }
                if self.connectionStatus != "Receiving events" {
                    self.connectionStatus = "Receiving events"
                }
            }
        }
        connectionStatus = "Connected"

        try await audioStreamer.start { [weak self] pcm, sampleRate in
            Task { @MainActor in
                await self?.sendAudioChunk(pcm: pcm, sampleRate: sampleRate)
            }
        }

        isRecording = true
        connectionStatus = "Streaming"
        state = RecitationSessionState(
            phase: .listening,
            headline: "Listening",
            detail: "Start reciting"
        )
    }

    public func stopRecording() {
        audioStreamer.stop()
        socketClient.disconnect()
        Task { await voiceActivityDetector.reset() }
        isRecording = false
        connectionStatus = "Stopped"
        state = RecitationSessionState(
            phase: .stopped,
            headline: "Stopped",
            detail: "Tap the mic to begin again"
        )
    }

    private var recitationScopeSelection: RecitationScopeSelection {
        switch recitationMode {
        case .autoDetect:
            return .autoDetect
        case .selectedSurah:
            return .selectedSurah(id: selectedSurahID)
        }
    }

    private var runPodAuthorizationToken: String? {
        guard backendPreset == .custom else { return nil }
        let token = runPodAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private func startRecordingHandlingErrors() async {
        do {
            try await startRecording()
        } catch {
            stopRecording()
            errorMessage = errorMessage(for: error, backendPreset: backendPreset)
            connectionStatus = "Error"
        }
    }

    private func sendAudioChunk(pcm: Data, sampleRate: Int) async {
        let voiceActivity = await voiceActivityDetector.process(
            pcm: pcm,
            sampleRate: sampleRate
        )
        let payload = AudioChunkPayload(
            sequenceNumber: sequenceNumber,
            pcm: pcm,
            sampleRateHz: sampleRate,
            voiceActivity: voiceActivity
        )
        sequenceNumber += 1

        do {
            try await socketClient.send(payload)
        } catch {
            stopRecording()
            errorMessage = errorMessage(for: error, backendPreset: backendPreset)
            connectionStatus = "Error"
        }
    }

    private func errorMessage(for error: Error, backendPreset: BackendEndpointPreset) -> String {
        let message = error.localizedDescription
        guard backendPreset == .simulator else {
            return message
        }

        if message.contains("Socket is not connected")
            || message.localizedCaseInsensitiveContains("connection refused")
            || message.localizedCaseInsensitiveContains("could not connect") {
            return "Start the local Simulator backend on 127.0.0.1:8000, then try again."
        }

        return message
    }
}

public enum RecitationViewModelError: LocalizedError {
    case invalidBackendURL

    public var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            return "Enter a valid backend URL."
        }
    }
}
```

- [ ] **Step 4: Remove duplicate app-local model declarations**

Delete `ios/TarteelPrototype/TarteelPrototype/App/RecitationViewModel.swift`. Do not leave an app-local `RecitationMode`; it now lives in core.

- [ ] **Step 5: Conform iPhone audio and VAD to shared protocols**

In `ios/TarteelPrototype/TarteelPrototype/App/MicrophoneAudioStreamer.swift`, change the class declaration to:

```swift
final class MicrophoneAudioStreamer: AudioStreaming {
```

In `ios/TarteelPrototype/TarteelPrototype/App/VoiceActivityDetector.swift`, change the actor declaration to:

```swift
actor VoiceActivityDetector: VoiceActivityDetecting {
```

- [ ] **Step 6: Inject iPhone dependencies from app entry point**

Replace `ios/TarteelPrototype/TarteelPrototype/App/TarteelPrototypeApp.swift` with:

```swift
import SwiftUI

@main
struct TarteelPrototypeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: RecitationViewModel(
                    audioStreamer: MicrophoneAudioStreamer(),
                    voiceActivityDetector: VoiceActivityDetector()
                )
            )
        }
    }
}
```

- [ ] **Step 7: Update Xcode project references for moved RecitationViewModel**

In `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj`, change the existing `RecitationViewModel.swift` file reference path from:

```text
path = App/RecitationViewModel.swift;
```

to:

```text
path = ../TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift;
```

Also add file references and iPhone source-build entries for:

```text
../TarteelClientCore/Sources/TarteelClientCore/RecitationClientProtocols.swift
../TarteelClientCore/Sources/TarteelClientCore/RecitationMode.swift
../TarteelClientCore/Sources/TarteelClientCore/RecitationPreferencesStore.swift
```

- [ ] **Step 8: Run focused Swift tests**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

Expected: PASS.

- [ ] **Step 9: Run focused Python iPhone guardrails**

Run:

```bash
uv run python -B -m unittest tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v
```

Expected: PASS.

- [ ] **Step 10: Build iPhone target**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS. If the sandbox blocks CoreSimulator or Swift package access, rerun with escalated permissions using the same command.

- [ ] **Step 11: Commit shared recording orchestration**

```bash
git add ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift ios/TarteelPrototype/TarteelPrototype/App/TarteelPrototypeApp.swift ios/TarteelPrototype/TarteelPrototype/App/MicrophoneAudioStreamer.swift ios/TarteelPrototype/TarteelPrototype/App/VoiceActivityDetector.swift ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj
git add -u ios/TarteelPrototype/TarteelPrototype/App/RecitationViewModel.swift
git commit -m "refactor: share recitation recording orchestration"
```

---

### Task 5: Add Native macOS App Sources

**Files:**
- Create: `ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift`
- Create: `ios/TarteelPrototype/TarteelPrototypeMac/App/MacContentView.swift`
- Create: `ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift`
- Create: `ios/TarteelPrototype/TarteelPrototypeMac/App/MacMicrophoneAudioStreamer.swift`
- Create: `ios/TarteelPrototype/TarteelPrototypeMac/Info.plist`

- [ ] **Step 1: Add macOS Info.plist**

Create `ios/TarteelPrototype/TarteelPrototypeMac/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSMicrophoneUsageDescription</key>
    <string>Microphone access streams recitation audio to your selected development backend.</string>
</dict>
</plist>
```

- [ ] **Step 2: Add macOS microphone streamer**

Create `ios/TarteelPrototype/TarteelPrototypeMac/App/MacMicrophoneAudioStreamer.swift`:

```swift
import AVFoundation
import Foundation

final class MacMicrophoneAudioStreamer: AudioStreaming {
    private let engine = AVAudioEngine()
    private let sampleRate = 16_000
    private var isTapInstalled = false

    func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws {
        stop()

        guard await Self.requestMicrophonePermission() else {
            throw MacMicrophoneAudioStreamerError.microphonePermissionDenied
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MacMicrophoneAudioStreamerError.unsupportedInputFormat
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw MacMicrophoneAudioStreamerError.unsupportedFormat
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            let sourceFormat = buffer.format
            guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
                return
            }
            guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
                return
            }

            let frameCapacity = max(
                1,
                AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / sourceFormat.sampleRate)
            )
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCapacity
            ) else {
                return
            }

            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                status.pointee = .haveData
                return buffer
            }

            guard error == nil, let data = converted.pcm16Data else {
                return
            }
            onChunk(data, self.sampleRate)
        }
        isTapInstalled = true

        engine.prepare()
        try engine.start()
    }

    func stop() {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
    }

    private static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }
}

enum MacMicrophoneAudioStreamerError: LocalizedError {
    case microphonePermissionDenied
    case unsupportedInputFormat
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable it in macOS Settings, then try again."
        case .unsupportedInputFormat:
            return "The microphone input format is not ready. Select an audio input and try again."
        case .unsupportedFormat:
            return "The microphone format is not supported."
        }
    }
}

private extension AVAudioPCMBuffer {
    var pcm16Data: Data? {
        guard let channelData = int16ChannelData else { return nil }
        let frameCount = Int(frameLength)
        return Data(bytes: channelData[0], count: frameCount * MemoryLayout<Int16>.size)
    }
}
```

- [ ] **Step 3: Add macOS settings view**

Create `ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift`:

```swift
import SwiftUI

struct MacSettingsView: View {
    @ObservedObject var viewModel: RecitationViewModel

    var body: some View {
        Form {
            Section("Backend") {
                Picker("Backend", selection: Binding(
                    get: { viewModel.backendPreset },
                    set: { viewModel.selectBackendPreset($0) }
                )) {
                    ForEach(BackendEndpointPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isRecording)

                TextField("Backend URL", text: $viewModel.backendURLText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(viewModel.isRecording || !viewModel.backendPreset.allowsURLTextEditing)

                if viewModel.backendPreset == .custom {
                    SecureField("RunPod API key", text: $viewModel.runPodAPIKeyText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(viewModel.isRecording)

                    Text("Prototype-only direct RunPod token. This value is not saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }
}
```

- [ ] **Step 4: Add macOS main content view**

Create `ios/TarteelPrototype/TarteelPrototypeMac/App/MacContentView.swift`:

```swift
import SwiftUI

struct MacContentView: View {
    @ObservedObject var viewModel: RecitationViewModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 22) {
                RecitationHeader(viewModel: viewModel)
                MacRecitationControls(viewModel: viewModel)
                MacVoiceActivityIndicator(isActive: viewModel.isRecording)
                MacMicButton(viewModel: viewModel)
                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            EventHistoryPanel(viewModel: viewModel)
                .frame(width: 360)
        }
        .background(Color.white)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
    }
}

private struct RecitationHeader: View {
    @ObservedObject var viewModel: RecitationViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text(viewModel.state.headline)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(MacTheme.ink)
                .multilineTextAlignment(.center)

            Text(viewModel.state.detail)
                .font(.title3)
                .foregroundStyle(MacTheme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MacRecitationControls: View {
    @ObservedObject var viewModel: RecitationViewModel

    var body: some View {
        VStack(spacing: 12) {
            Picker("Recitation", selection: Binding(
                get: { viewModel.recitationMode },
                set: { viewModel.selectRecitationMode($0) }
            )) {
                Text("Auto").tag(RecitationMode.autoDetect)
                Text("Surah").tag(RecitationMode.selectedSurah)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isRecording)
            .frame(width: 280)

            if viewModel.recitationMode == .selectedSurah {
                Picker("Surah", selection: $viewModel.selectedSurahID) {
                    ForEach(SurahCatalog.all) { surah in
                        Text(surah.displayName).tag(surah.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.isRecording)
                .frame(width: 320)
            }
        }
    }
}

private struct MacMicButton: View {
    @ObservedObject var viewModel: RecitationViewModel

    var body: some View {
        Button(action: { viewModel.toggleRecording() }) {
            Label(
                viewModel.isRecording ? "Stop Recitation" : "Start Recitation",
                systemImage: viewModel.isRecording ? "xmark.circle.fill" : "mic.circle.fill"
            )
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRecording ? MacTheme.warning : MacTheme.teal)
        .keyboardShortcut(.space, modifiers: [])
    }
}

private struct MacVoiceActivityIndicator: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(isActive ? MacTheme.teal : MacTheme.line)
                    .frame(width: 18, height: isActive ? CGFloat(42 + (index % 3) * 20) : 34)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isActive)
            }
        }
        .frame(height: 92)
    }
}

private struct EventHistoryPanel: View {
    @ObservedObject var viewModel: RecitationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Status")
                .font(.headline)

            StatusRow(title: "Connection", value: viewModel.connectionStatus)
            StatusRow(title: "Last event", value: viewModel.state.debugLastEventText)
            StatusRow(title: "Ayah", value: viewModel.state.debugAyahText)
            StatusRow(title: "Ayah text", value: viewModel.state.debugAyahBodyText)
            StatusRow(title: "Transcript", value: viewModel.state.debugTranscriptText)

            if let errorMessage = viewModel.errorMessage {
                StatusRow(title: "Error", value: errorMessage, isError: true)
            }

            Spacer()
        }
        .padding(22)
        .background(MacTheme.softGray)
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacTheme.muted)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isError ? MacTheme.warning : MacTheme.ink)
                .textSelection(.enabled)
                .lineLimit(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum MacTheme {
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.15)
    static let muted = Color(red: 0.39, green: 0.43, blue: 0.50)
    static let softGray = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let line = Color(red: 0.84, green: 0.87, blue: 0.91)
    static let teal = Color(red: 0.11, green: 0.58, blue: 0.64)
    static let warning = Color(red: 0.85, green: 0.20, blue: 0.22)
}
```

- [ ] **Step 5: Add macOS app entry point and commands**

Create `ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift`:

```swift
import SwiftUI

@main
struct TarteelPrototypeMacApp: App {
    @StateObject private var viewModel = RecitationViewModel(
        audioStreamer: MacMicrophoneAudioStreamer(),
        voiceActivityDetector: VoiceActivityDetector()
    )

    var body: some Scene {
        WindowGroup {
            MacContentView(viewModel: viewModel)
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button(viewModel.isRecording ? "Stop Recitation" : "Start Recitation") {
                    viewModel.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            MacSettingsView(viewModel: viewModel)
        }
    }
}
```

- [ ] **Step 6: Run macOS guardrails and verify source failures are limited to project wiring**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: FAIL only for project target/resource wiring if the source files and plist are present.

- [ ] **Step 7: Commit macOS app sources**

```bash
git add ios/TarteelPrototype/TarteelPrototypeMac
git commit -m "feat: add native macOS app sources"
```

---

### Task 6: Wire The Native macOS Target In Xcode

**Files:**
- Modify: `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add macOS product, groups, build phases, and target**

Edit `ios/TarteelPrototype/TarteelPrototype.xcodeproj/project.pbxproj` manually, following the existing deterministic ID style. Use a new ID prefix such as `200000000000000000000` for macOS objects.

Add file references for:

```text
TarteelPrototypeMac.app
TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift
TarteelPrototypeMac/App/MacContentView.swift
TarteelPrototypeMac/App/MacSettingsView.swift
TarteelPrototypeMac/App/MacMicrophoneAudioStreamer.swift
TarteelPrototypeMac/Info.plist
```

Add macOS build-file entries for app-specific files, shared core files, `VoiceActivityDetector.swift`, `FluidAudio in Frameworks`, and `silero-vad-unified-256ms-v6.0.0.mlmodelc in Resources`.

Add a `PBXNativeTarget` named `TarteelPrototypeMac` with:

```text
productName = TarteelPrototypeMac;
productReference = the `TarteelPrototypeMac.app` product file-reference ID created in the `PBXFileReference` section;
productType = "com.apple.product-type.application";
packageProductDependencies = (
    the existing `FluidAudio` product-dependency ID,
);
```

Add that target ID to the project `targets = (` list and add `TarteelPrototypeMac.app` to the `Products` group.

- [ ] **Step 2: Add macOS target build settings**

Create Debug and Release `XCBuildConfiguration` entries for the macOS target with these settings:

```text
CODE_SIGN_STYLE = Automatic;
CURRENT_PROJECT_VERSION = 1;
DEVELOPMENT_TEAM = "";
ENABLE_HARDENED_RUNTIME = NO;
GENERATE_INFOPLIST_FILE = NO;
INFOPLIST_FILE = TarteelPrototypeMac/Info.plist;
LD_RUNPATH_SEARCH_PATHS = (
    "$(inherited)",
    "@executable_path/../Frameworks",
);
MACOSX_DEPLOYMENT_TARGET = 14.0;
MARKETING_VERSION = 0.1;
PRODUCT_BUNDLE_IDENTIFIER = dev.mostafa.TarteelPrototypeMac;
PRODUCT_NAME = "$(TARGET_NAME)";
SDKROOT = macosx;
SUPPORTED_PLATFORMS = "macosx";
SWIFT_EMIT_LOC_STRINGS = YES;
SWIFT_VERSION = 5.0;
```

Do not add App Sandbox entitlements in this slice.

- [ ] **Step 3: Add macOS scheme if xcodebuild cannot infer it**

If `xcodebuild -list -project ios/TarteelPrototype/TarteelPrototype.xcodeproj` does not list `TarteelPrototypeMac`, add a shared scheme under:

```text
ios/TarteelPrototype/TarteelPrototype.xcodeproj/xcshareddata/xcschemes/TarteelPrototypeMac.xcscheme
```

The scheme must build the `TarteelPrototypeMac` target for running and testing.

- [ ] **Step 4: Run macOS project guardrails**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: PASS.

- [ ] **Step 5: Build macOS app target**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS. If Swift package resolution is blocked by sandboxed network access, rerun with escalated permissions using the same command.

- [ ] **Step 6: Rebuild iPhone app target**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 7: Commit Xcode macOS target wiring**

```bash
git add ios/TarteelPrototype/TarteelPrototype.xcodeproj
git commit -m "feat: wire native macOS app target"
```

---

### Task 7: Update Docs, Harness State, And Final Verification

**Files:**
- Modify: `ios/README.md`
- Modify: `clean-state-checklist.md`
- Modify: `feature_list.json`
- Modify: `codex-progress.md`
- Modify: `session-handoff.md`
- Modify: `quality-document.md` if the quality posture changes

- [ ] **Step 1: Update iOS README to describe Apple clients**

In `ios/README.md`, add a `macOS Prototype` section with this Markdown:

````markdown
## macOS Prototype

The same Xcode project also contains a native macOS developer prototype target:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build
```

The macOS app defaults to:

```text
ws://127.0.0.1:8000/ws/recitation
```

It uses a native Settings window for backend preset, custom URL, and the prototype-only RunPod API key. Non-secret settings persist between launches. The RunPod API key is memory-only unless a later Keychain slice adds secure storage.

The macOS app captures microphone input, converts it to mono 16 kHz PCM16, runs the bundled FluidAudio/CoreML Silero VAD when available, and sends the same `AudioChunkPayload` shape as the iPhone app.
````

- [ ] **Step 2: Update clean-state checklist**

Add these checks to `clean-state-checklist.md` near the existing iOS checks:

```markdown
- [ ] macOS app source/project guardrails still run when touched: `uv run python -B -m unittest tests.test_macos_app_project -v`.
- [ ] macOS app still builds when touched: `xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build`.
- [ ] Shared Apple client orchestration changes keep protocol-injected socket/audio/VAD behavior covered: `cd ios/TarteelClientCore && env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test`.
```

- [ ] **Step 3: Update feature list**

In `feature_list.json`, add evidence to `mobile-001` that the iPhone prototype now shares client orchestration and the macOS prototype builds. Add these verification entries:

```json
"Run uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v after Apple client project/source changes.",
"Run xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build after macOS app changes."
```

Add evidence lines that name each command from Steps 5 through 8 and its pass/fail result from the implementation run.

- [ ] **Step 4: Update progress and handoff**

After Steps 5 through 8 have run, append a new session entry to `codex-progress.md` with this shape and concrete command results from the current run:

```markdown
### Session 075

- Date: 2026-05-25
- Goal: Add a native macOS SwiftUI prototype alongside the existing iPhone app.
- Completed:
  - Added shared Apple client protocols, preferences, WebSocket transport, and recording orchestration in `TarteelClientCore`.
  - Preserved the iPhone clean home/settings UI while injecting iPhone microphone and VAD dependencies.
  - Added native macOS app sources, separate macOS plist, Settings scene, desktop recitation surface, status console, macOS microphone capture, and bundled VAD resource wiring.
  - Added Xcode target `TarteelPrototypeMac` with bundle id `dev.mostafa.TarteelPrototypeMac`.
- Verification run:
  - Add one bullet for the Swift client core command and its passing test count.
  - Add one bullet for the focused Python Apple guardrail command and its passing test count.
  - Add one bullet for the iPhone `xcodebuild` command and pass result.
  - Add one bullet for the macOS `xcodebuild` command and pass result.
  - Add one bullet for JSON validation and pass result.
  - Add one bullet for `git diff --check` and pass result.
  - Add one bullet for the full Python suite and its passing test count.
- Known risk or unresolved issue:
  - Manual macOS microphone testing was not part of this automated build slice unless it was explicitly performed during implementation.
  - RunPod live-ASR proof remains a separate acceptance step unless it was explicitly performed during implementation.
- Next best step: manually launch the macOS app, grant microphone permission, and test local backend recording against `/ws/recitation`.
```

Before committing, replace the seven `Add one bullet` instructions in `codex-progress.md` with the exact commands and pass results from the current implementation run.

Update `session-handoff.md` with the same current state, changed files, verification evidence, remaining risk, and next best step.

- [ ] **Step 5: Validate structured files**

Run:

```bash
uv run python -B -m json.tool feature_list.json
```

Expected: PASS with formatted JSON printed.

- [ ] **Step 6: Run final focused Apple checks**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v
```

Expected: PASS.

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

Expected: PASS.

- [ ] **Step 7: Run app builds**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 8: Run final repository hygiene checks**

Run:

```bash
git diff --check
```

Expected: no output.

Run:

```bash
uv run python -B -m unittest discover -s tests -v
```

Expected: PASS.

- [ ] **Step 9: Commit docs and harness updates**

```bash
git add ios/README.md clean-state-checklist.md feature_list.json codex-progress.md session-handoff.md quality-document.md
git commit -m "docs: record native macOS app verification"
```

---

## Self-Review

Spec coverage:

- Native macOS target, target name, bundle id, and macOS 14 are covered in Task 6.
- No `ios/` to `apple/` rename is preserved by all tasks.
- Shared orchestration and WebSocket core move are covered in Tasks 2 through 4.
- iPhone visual preservation is covered by Task 1 guardrails and Task 4 iPhone build.
- macOS UI, Settings scene, commands, status console, microphone capture, and VAD resource are covered in Tasks 5 and 6.
- Non-secret persistence and memory-only RunPod key are covered in Tasks 2 and 4.
- Separate macOS plist and no App Sandbox are covered in Tasks 5 and 6.
- Swift tests, Python guardrails, iPhone build, macOS build, docs, and harness updates are covered in Task 7.

Placeholder scan:

- No red-flag markers or unspecified test commands are intentionally present.

Type consistency:

- `BackendSocketing`, `AudioStreaming`, `VoiceActivityDetecting`, `RecitationPreferencesStoring`, `RecitationMode`, and `RecitationViewModel` are introduced before use.
- App targets inject platform audio and VAD into the shared `RecitationViewModel`.
- `VoiceActivityPayload`, `AudioChunkPayload`, `BackendEndpointPreset`, `RecitationScopeSelection`, and `RecitationSessionState` match existing core model names.
