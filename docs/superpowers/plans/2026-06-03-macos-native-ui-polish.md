# macOS Native UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish `TarteelPrototypeMac` so it behaves like a native macOS utility: clear toolbar actions, adaptive light/dark appearance, searchable recitation scope, event history, drag/drop, onboarding, and visible feedback for every primary state.

**Architecture:** Keep app-specific UI in `ios/TarteelPrototype/TarteelPrototypeMac/App`. Put reusable presentation state in `RecitationViewModel` only when it reflects session behavior shared across Apple clients, such as startup state, event history, shareable diagnostics, and backend URL validation. Preserve the existing WebSocket-only audio contract; drag/drop is limited to backend URL/text import and diagnostic/history export.

**Tech Stack:** SwiftUI, AppKit system colors/materials through SwiftUI, UniformTypeIdentifiers, `TarteelClientCore`, XCTest, Python source guardrails, Xcode macOS build.

---

## Scope

This plan improves the existing native macOS target. It does not add audio file replay, system audio capture, backend changes, new ASR behavior, App Sandbox, or distribution packaging.

## File Structure

- Modify `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift`: expose startup state, bounded recent event history, shareable session summary, backend URL validation, dropped URL application, and search-independent selected-surah helpers.
- Modify `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift`: add behavior tests for startup feedback, event history, share summary, URL validation, and dropped URL handling.
- Modify `ios/TarteelPrototype/TarteelPrototypeMac/App/MacContentView.swift`: replace the fixed white prototype surface with native system colors/materials, toolbar actions, search, transitions, drop target, drag-out diagnostics, empty states, onboarding sheet trigger, and compact event history.
- Modify `ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift`: add fuller macOS commands for recording, search focus, and settings while keeping standard Quit behavior.
- Modify `ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift`: add URL validation feedback, inline disabled-state context, and control help.
- Modify `tests/test_macos_app_project.py`: add static guardrails for the native UI surface.
- Modify `ios/README.md`, `clean-state-checklist.md`, `codex-progress.md`, `feature_list.json`, and `session-handoff.md`: record behavior, verification, and remaining manual-test risks after implementation.

---

### Task 1: Add Failing macOS UI Guardrails

**Files:**
- Modify: `tests/test_macos_app_project.py`

- [ ] **Step 1: Add native polish source tests**

Append these tests to `MacOSAppProjectTests` in `tests/test_macos_app_project.py`:

```python
    def test_macos_ui_uses_native_visual_system_and_toolbar_actions(self) -> None:
        content_source = (MAC_APP_SOURCE_ROOT / "MacContentView.swift").read_text(encoding="utf-8")
        app_source = (MAC_APP_SOURCE_ROOT / "TarteelPrototypeMacApp.swift").read_text(encoding="utf-8")

        self.assertNotIn(".background(Color.white)", content_source)
        self.assertIn("Color(nsColor: .windowBackgroundColor)", content_source)
        self.assertIn(".background(.regularMaterial)", content_source)
        self.assertIn("ToolbarItemGroup", content_source)
        self.assertIn("Label(viewModel.recordingActionTitle", content_source)
        self.assertIn(".help(viewModel.recordingActionHelp)", content_source)
        self.assertIn(".windowToolbarStyle(.unifiedCompact)", app_source)
        self.assertIn('CommandMenu("Recitation")', app_source)
        self.assertIn(".keyboardShortcut(\"f\", modifiers: [.command])", app_source)

    def test_macos_ui_exposes_search_drag_drop_onboarding_and_transitions(self) -> None:
        content_source = (MAC_APP_SOURCE_ROOT / "MacContentView.swift").read_text(encoding="utf-8")

        self.assertIn("@FocusState", content_source)
        self.assertIn(".searchable(text:", content_source)
        self.assertIn("filteredSurahs", content_source)
        self.assertIn(".onDrop(of:", content_source)
        self.assertIn("UTType.url.identifier", content_source)
        self.assertIn("UTType.plainText.identifier", content_source)
        self.assertIn(".draggable(viewModel.shareableSessionSummary)", content_source)
        self.assertIn("NativeOnboardingSheet", content_source)
        self.assertIn("focusMacSurahSearch", content_source)
        self.assertIn(".onReceive(NotificationCenter.default.publisher", content_source)
        self.assertIn(".transition(.opacity.combined", content_source)
        self.assertIn(".animation(.snappy", content_source)

    def test_macos_settings_show_validation_and_disabled_state_feedback(self) -> None:
        settings_source = (MAC_APP_SOURCE_ROOT / "MacSettingsView.swift").read_text(encoding="utf-8")

        self.assertIn("backendURLValidationMessage", settings_source)
        self.assertIn("Label(message", settings_source)
        self.assertIn("exclamationmark.triangle", settings_source)
        self.assertIn("Settings controls are locked while recording", settings_source)
        self.assertIn(".help(", settings_source)
```

- [ ] **Step 2: Run the failing guardrails**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: FAIL. The current app still has fixed `Color.white`, no toolbar record action, no searchable surface, no drag/drop, no onboarding sheet, and no settings URL validation message.

- [ ] **Step 3: Commit the red guardrails**

Run:

```bash
git add tests/test_macos_app_project.py
git commit -m "test: guard native macOS UI polish"
```

---

### Task 2: Add Shared Presentation State

**Files:**
- Modify: `ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift`
- Modify: `ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift`

- [ ] **Step 1: Add failing `RecitationViewModel` tests**

Add these tests inside `RecitationViewModelTests`:

```swift
    func testRecordingActionReflectsConnectingStateBeforeStreaming() async throws {
        let socket = SuspendedConnectSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )

        viewModel.toggleRecording()
        await socket.waitForConnectCount(1)

        XCTAssertEqual(viewModel.recordingActionTitle, "Connecting")
        XCTAssertEqual(viewModel.recordingActionSystemImage, "waveform.badge.magnifyingglass")
        XCTAssertFalse(viewModel.canStartRecording)

        await socket.releaseAllConnections()
        await drainScheduledTasks()
    }

    func testRecentEventHistoryKeepsNewestFiveEventsAndShareSummary() async throws {
        let socket = FakeSocket()
        let viewModel = RecitationViewModel(
            socketClient: socket,
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: FakePreferencesStore()
        )
        await viewModel.startRecording()

        for sequence in 0..<7 {
            await socket.emit(
                RecitationEvent(
                    type: sequence == 0 ? .locked : .progress,
                    transcript: "transcript \(sequence)",
                    confidence: 0.9,
                    chunkSequence: sequence,
                    reason: "test_event",
                    candidateRefs: [],
                    ayahText: "ayah \(sequence)",
                    ayahRef: "112:\(sequence + 1)",
                    startRef: "112:\(sequence + 1):1",
                    nextExpectedRef: nil,
                    consumedWords: 1,
                    expectedRef: nil,
                    expectedWord: nil,
                    recognizedWord: nil
                )
            )
        }

        XCTAssertEqual(viewModel.recentEventHistory.count, 5)
        XCTAssertEqual(viewModel.recentEventHistory.first?.chunkSequence, 6)
        XCTAssertEqual(viewModel.recentEventHistory.last?.chunkSequence, 2)
        XCTAssertTrue(viewModel.shareableSessionSummary.contains("Connection: Receiving events"))
        XCTAssertTrue(viewModel.shareableSessionSummary.contains("112:7"))
        XCTAssertTrue(viewModel.shareableSessionSummary.contains("transcript 6"))
    }

    func testBackendURLValidationAndDroppedURLApplication() {
        let preferences = FakePreferencesStore()
        let viewModel = RecitationViewModel(
            socketClient: FakeSocket(),
            audioStreamer: FakeAudioStreamer(),
            voiceActivityDetector: FakeVoiceActivityDetector(),
            preferencesStore: preferences
        )

        XCTAssertNil(viewModel.applyDroppedBackendText("not a websocket url"))
        XCTAssertNotNil(viewModel.backendURLValidationMessage)

        let normalizedURL = viewModel.applyDroppedBackendText(
            "https://workspace--tarteel-realtime-asr-fastapi-app.modal.run"
        )

        XCTAssertEqual(
            normalizedURL,
            "wss://workspace--tarteel-realtime-asr-fastapi-app.modal.run/ws/recitation"
        )
        XCTAssertEqual(viewModel.backendPreset, .custom)
        XCTAssertEqual(viewModel.customBackendProvider, .modal)
        XCTAssertEqual(viewModel.backendURLText, normalizedURL)
        XCTAssertNil(viewModel.backendURLValidationMessage)
    }
```

- [ ] **Step 2: Run the focused Swift tests and verify failure**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationViewModelTests
```

Expected: FAIL with missing `recordingActionTitle`, `recordingActionSystemImage`, `canStartRecording`, `recentEventHistory`, `shareableSessionSummary`, `backendURLValidationMessage`, and `applyDroppedBackendText`.

- [ ] **Step 3: Add public event-history type**

Add this near the top of `RecitationViewModel.swift`, below imports:

```swift
public struct RecitationEventHistoryItem: Equatable, Identifiable, Sendable {
    public let id: Int
    public let typeText: String
    public let detailText: String
    public let ayahRef: String?
    public let transcript: String
    public let chunkSequence: Int?

    public init(event: RecitationEvent, id: Int) {
        self.id = id
        self.typeText = event.type.rawValue
        self.detailText = event.reason ?? event.type.rawValue
        self.ayahRef = event.ayahRef ?? event.startRef
        self.transcript = event.transcript
        self.chunkSequence = event.chunkSequence
    }
}
```

- [ ] **Step 4: Add published presentation properties**

In `RecitationViewModel`, add:

```swift
    @Published public private(set) var recentEventHistory: [RecitationEventHistoryItem] = []
    @Published public private(set) var backendURLValidationMessage: String?
```

Add private counters:

```swift
    private var eventHistoryID = 0
```

Add computed properties:

```swift
    public var canStartRecording: Bool {
        !isRecording && !isStartingRecording
    }

    public var recordingActionTitle: String {
        if isStartingRecording {
            return "Connecting"
        }
        return isRecording ? "Stop Recitation" : "Start Recitation"
    }

    public var recordingActionSystemImage: String {
        if isStartingRecording {
            return "waveform.badge.magnifyingglass"
        }
        return isRecording ? "xmark.circle.fill" : "mic.circle.fill"
    }

    public var recordingActionHelp: String {
        isRecording ? "Stop the current recitation stream" : "Start streaming microphone audio"
    }

    public var shareableSessionSummary: String {
        let events = recentEventHistory.map { item in
            let ref = item.ayahRef ?? "none"
            return "- \(item.typeText) \(ref): \(item.transcript)"
        }.joined(separator: "\n")
        return """
        Tarteel realtime session
        Connection: \(connectionStatus)
        Ayah: \(state.debugAyahText)
        Transcript: \(state.debugTranscriptText)

        Recent events:
        \(events.isEmpty ? "- none" : events)
        """
    }
```

- [ ] **Step 5: Record event history on socket events**

Inside the socket event callback in `startRecording()`, before reducing `state`, insert:

```swift
                    self.recordHistoryItem(for: event)
```

Add this helper inside `RecitationViewModel`:

```swift
    private func recordHistoryItem(for event: RecitationEvent) {
        eventHistoryID += 1
        let item = RecitationEventHistoryItem(event: event, id: eventHistoryID)
        recentEventHistory.insert(item, at: 0)
        if recentEventHistory.count > 5 {
            recentEventHistory.removeLast(recentEventHistory.count - 5)
        }
    }
```

- [ ] **Step 6: Add URL validation and dropped text application**

Add these methods inside `RecitationViewModel`:

```swift
    public func validateBackendURLText() {
        guard backendPreset == .custom else {
            backendURLValidationMessage = nil
            return
        }
        let text = backendURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            backendURLValidationMessage = "Enter a backend WebSocket URL before recording."
            return
        }
        guard let url = URL(string: BackendEndpointPreset.custom.recordingURLText(
            currentURLText: text,
            provider: customBackendProvider
        )), let scheme = url.scheme, ["ws", "wss"].contains(scheme) else {
            backendURLValidationMessage = "Use a ws:// or wss:// backend URL."
            return
        }
        backendURLValidationMessage = nil
    }

    @discardableResult
    public func applyDroppedBackendText(_ text: String) -> String? {
        guard !isRecording, !isStartingRecording else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider: BackendProvider
        if trimmed.contains(".modal.run") {
            provider = .modal
        } else if trimmed.contains(".proxy.runpod.net") || trimmed.contains(".api.runpod.ai") {
            provider = .runPod
        } else {
            provider = .generic
        }
        let normalized = BackendEndpointPreset.custom.recordingURLText(
            currentURLText: trimmed,
            provider: provider
        )
        guard let url = URL(string: normalized), let scheme = url.scheme, ["ws", "wss"].contains(scheme) else {
            backendURLValidationMessage = "Drop a ws://, wss://, Modal, or RunPod backend URL."
            return nil
        }
        selectBackendPreset(.custom)
        selectCustomBackendProvider(provider)
        backendURLText = normalized
        validateBackendURLText()
        return normalized
    }
```

Call `validateBackendURLText()` from the `backendURLText` `didSet`, `selectBackendPreset(_:)`, and `selectCustomBackendProvider(_:)` paths after their existing state updates.

- [ ] **Step 7: Reset transient history on a new session**

In `startRecording()`, after `errorMessage = nil`, add:

```swift
        recentEventHistory = []
        eventHistoryID = 0
```

- [ ] **Step 8: Run focused Swift tests**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test --filter RecitationViewModelTests
```

Expected: PASS.

- [ ] **Step 9: Commit shared state changes**

Run:

```bash
git add ios/TarteelClientCore/Sources/TarteelClientCore/RecitationViewModel.swift ios/TarteelClientCore/Tests/TarteelClientCoreTests/RecitationViewModelTests.swift
git commit -m "feat: expose macOS recitation presentation state"
```

---

### Task 3: Rework The macOS Main Window Shell

**Files:**
- Modify: `ios/TarteelPrototype/TarteelPrototypeMac/App/MacContentView.swift`
- Modify: `ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift`

- [ ] **Step 1: Add native imports and local UI state**

In `MacContentView.swift`, add:

```swift
import UniformTypeIdentifiers
```

Inside `MacContentView`, add:

```swift
    @AppStorage("mac.hasSeenNativeOnboarding") private var hasSeenNativeOnboarding = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var isShowingOnboarding = false
```

Add this computed property:

```swift
    private var filteredSurahs: [SurahMetadata] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SurahCatalog.all }
        return SurahCatalog.all.filter { surah in
            surah.nameSimple.localizedCaseInsensitiveContains(query)
                || surah.nameArabic.localizedCaseInsensitiveContains(query)
                || String(surah.id) == query
        }
    }
```

- [ ] **Step 2: Replace fixed white background with native system materials**

Update `MacContentView.body` so the root uses:

```swift
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search surahs")
        .focused($isSearchFocused)
        .onAppear {
            if !hasSeenNativeOnboarding {
                isShowingOnboarding = true
            }
        }
        .sheet(isPresented: $isShowingOnboarding) {
            NativeOnboardingSheet(
                hasSeenNativeOnboarding: $hasSeenNativeOnboarding,
                toggleRecording: { viewModel.toggleRecording() }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusMacSurahSearch)) { _ in
            isSearchFocused = true
        }
        .animation(.snappy(duration: 0.2), value: viewModel.state.phase)
        .animation(.snappy(duration: 0.2), value: viewModel.recentEventHistory)
```

Keep the minimum frame `860 x 560`.

- [ ] **Step 3: Add toolbar actions**

Replace the current toolbar with:

```swift
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { viewModel.toggleRecording() }) {
                    Label(viewModel.recordingActionTitle, systemImage: viewModel.recordingActionSystemImage)
                }
                .disabled(!viewModel.canStartRecording && !viewModel.isRecording)
                .keyboardShortcut(.space, modifiers: [])
                .help(viewModel.recordingActionHelp)

                Button(action: { isSearchFocused = true }) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .help("Search for a surah")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open Settings")
            }
        }
```

- [ ] **Step 4: Convert the right panel to native material**

Update `EventHistoryPanel` so its container ends with:

```swift
        .padding(22)
        .background(.regularMaterial)
```

Replace `Spacer()` in the panel with an empty-state-aware history list:

```swift
            Divider()

            Text("Recent Events")
                .font(.headline)

            if viewModel.recentEventHistory.isEmpty {
                ContentUnavailableView(
                    "No events yet",
                    systemImage: "waveform",
                    description: Text("Start reciting to populate the event console.")
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                ForEach(viewModel.recentEventHistory) { item in
                    EventHistoryRow(item: item)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 0)

            Text("Drag this panel to copy diagnostics.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .draggable(viewModel.shareableSessionSummary)
```

Add `EventHistoryRow`:

```swift
private struct EventHistoryRow: View {
    let item: RecitationEventHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.typeText)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(item.ayahRef ?? "none")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(item.transcript.isEmpty ? item.detailText : item.transcript)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 5: Add drop handling**

On the root view, add:

```swift
        .onDrop(
            of: [UTType.url.identifier, UTType.plainText.identifier],
            isTargeted: $isDropTargeted
        ) { providers in
            handleDrop(providers)
        }
```

Add this helper inside `MacContentView`:

```swift
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    let text = (item as? URL)?.absoluteString ?? (item as? Data).flatMap {
                        String(data: $0, encoding: .utf8)
                    }
                    if let text {
                        Task { @MainActor in _ = viewModel.applyDroppedBackendText(text) }
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    let text = (item as? String) ?? (item as? Data).flatMap {
                        String(data: $0, encoding: .utf8)
                    }
                    if let text {
                        Task { @MainActor in _ = viewModel.applyDroppedBackendText(text) }
                    }
                }
                return true
            }
        }
        return false
    }
```

- [ ] **Step 6: Add onboarding sheet**

Add this view to `MacContentView.swift`:

```swift
private struct NativeOnboardingSheet: View {
    @Binding var hasSeenNativeOnboarding: Bool
    let toggleRecording: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tarteel")
                .font(.title.bold())
            Text("Use the toolbar or Space to start listening. Drop a backend URL anywhere in the window to switch Custom endpoints.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Try Space") {
                    hasSeenNativeOnboarding = true
                    dismiss()
                    toggleRecording()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Done") {
                    hasSeenNativeOnboarding = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
```

- [ ] **Step 7: Add search focus notification**

Add this extension at file scope in `MacContentView.swift`:

```swift
extension Notification.Name {
    static let focusMacSurahSearch = Notification.Name("focusMacSurahSearch")
}
```

- [ ] **Step 8: Add macOS command menu and toolbar style**

In `TarteelPrototypeMacApp.swift`, update `WindowGroup`:

```swift
        WindowGroup {
            MacContentView(viewModel: viewModel)
        }
        .windowToolbarStyle(.unifiedCompact)
```

Replace the current command group with:

```swift
        .commands {
            CommandMenu("Recitation") {
                Button(viewModel.recordingActionTitle) {
                    viewModel.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Search Surahs") {
                    NotificationCenter.default.post(name: .focusMacSurahSearch, object: nil)
                }
                    .keyboardShortcut("f", modifiers: [.command])
            }
        }
```

- [ ] **Step 9: Run macOS source guardrails**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: PASS for the new UI source tests.

- [ ] **Step 10: Commit the macOS shell changes**

Run:

```bash
git add ios/TarteelPrototype/TarteelPrototypeMac/App/MacContentView.swift ios/TarteelPrototype/TarteelPrototypeMac/App/TarteelPrototypeMacApp.swift tests/test_macos_app_project.py
git commit -m "feat: polish native macOS window shell"
```

---

### Task 4: Replace The Full Surah Menu With Search-Aware Selection

**Files:**
- Modify: `ios/TarteelPrototype/TarteelPrototypeMac/App/MacContentView.swift`

- [ ] **Step 1: Change `MacRecitationControls` signature**

Replace:

```swift
MacRecitationControls(viewModel: viewModel)
```

with:

```swift
MacRecitationControls(viewModel: viewModel, filteredSurahs: filteredSurahs)
```

Update the struct:

```swift
private struct MacRecitationControls: View {
    @ObservedObject var viewModel: RecitationViewModel
    let filteredSurahs: [SurahMetadata]
```

- [ ] **Step 2: Replace the selected-surah picker content**

Inside the Surah picker, replace `ForEach(SurahCatalog.all)` with:

```swift
                    ForEach(filteredSurahs) { surah in
                        Text(surah.displayName).tag(surah.id)
                    }
```

Add an empty state below the picker:

```swift
                if filteredSurahs.isEmpty {
                    Text("No matching surah")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
```

- [ ] **Step 3: Add source guardrail for filtered Surah use**

In `tests/test_macos_app_project.py`, extend `test_macos_ui_exposes_search_drag_drop_onboarding_and_transitions`:

```python
        self.assertNotIn("ForEach(SurahCatalog.all)", content_source)
        self.assertIn("ForEach(filteredSurahs)", content_source)
```

- [ ] **Step 4: Run the guardrail**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: PASS.

- [ ] **Step 5: Commit searchable Surah selection**

Run:

```bash
git add ios/TarteelPrototype/TarteelPrototypeMac/App/MacContentView.swift tests/test_macos_app_project.py
git commit -m "feat: add searchable macOS surah selection"
```

---

### Task 5: Improve Settings Feedback

**Files:**
- Modify: `ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift`

- [ ] **Step 1: Add validation feedback below the URL field**

After the backend URL `TextField`, add:

```swift
                if let message = viewModel.backendURLValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
```

- [ ] **Step 2: Add disabled-state context**

Inside the Backend section, after the provider/token controls, add:

```swift
                if viewModel.isRecording {
                    Text("Settings controls are locked while recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

- [ ] **Step 3: Add control help**

Add these `.help(...)` modifiers:

```swift
                .help("Choose the backend preset used for the next recitation session")
```

to the backend preset picker, and:

```swift
                    .help("Optional memory-only bearer token for the next Custom backend connection")
```

to the secure token field.

- [ ] **Step 4: Run macOS source guardrails**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project -v
```

Expected: PASS.

- [ ] **Step 5: Commit settings feedback**

Run:

```bash
git add ios/TarteelPrototype/TarteelPrototypeMac/App/MacSettingsView.swift
git commit -m "feat: add macOS settings validation feedback"
```

---

### Task 6: Verify Builds And Apple Client Tests

**Files:**
- No source edits unless verification exposes a build issue.

- [ ] **Step 1: Run full Swift client core tests**

Run:

```bash
cd ios/TarteelClientCore
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

Expected: PASS.

- [ ] **Step 2: Run focused Apple source guardrails**

Run:

```bash
uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v
```

Expected: PASS.

- [ ] **Step 3: Build macOS target**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototypeMac -sdk macosx -derivedDataPath /private/tmp/tarteel-xcode-derived-macos CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS. If sandboxed Xcode package/cache access blocks the build, rerun the same command with approved escalation.

- [ ] **Step 4: Build iPhone target for shared-core safety**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 5: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

---

### Task 7: Update Docs And Harness State

**Files:**
- Modify: `ios/README.md`
- Modify: `clean-state-checklist.md`
- Modify: `codex-progress.md`
- Modify: `feature_list.json`
- Modify: `session-handoff.md`

- [ ] **Step 1: Update `ios/README.md` macOS section**

Add this paragraph under `## macOS Prototype`:

```markdown
The macOS window uses the native toolbar for recording, search, and settings. `Space` and `Command-R` toggle recording, and `Command-F` focuses Surah search. Dropping a WebSocket, Modal, or RunPod URL onto the window switches the next session to the Custom backend. The status console shows the latest state plus recent events, and its diagnostic text can be dragged or copied for debugging.
```

- [ ] **Step 2: Update `clean-state-checklist.md`**

Add this checklist item near the existing macOS app checks:

```markdown
- [ ] macOS native UI polish changes keep toolbar record/search/settings, adaptive system colors/materials, searchable Surah selection, URL/text drop-in, diagnostic drag-out, onboarding, event history, and settings validation covered: `uv run python -B -m unittest tests.test_macos_app_project -v`, plus the macOS app build.
```

- [ ] **Step 3: Update `feature_list.json` evidence**

In feature `mobile-001`, append evidence:

```json
"macOS native UI polish adds toolbar recording/search/settings, adaptive system colors/materials, searchable Surah selection, backend URL/text drop-in, diagnostic drag-out, onboarding, event history, and settings URL validation."
```

Append verification:

```json
"Run uv run python -B -m unittest tests.test_macos_app_project -v after native macOS UI polish changes."
```

- [ ] **Step 4: Update progress and handoff**

Add a new session entry to `codex-progress.md` recording:

```markdown
### Session 081

- Date: 2026-06-03
- Goal: Polish the native macOS prototype UI against native macOS utility guidelines.
- Completed:
  - Added toolbar recording/search/settings, adaptive macOS colors/materials, searchable Surah selection, URL/text drop-in, diagnostic drag-out, onboarding, event history, and settings URL validation.
- Verification run:
  - `env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test` from `ios/TarteelClientCore`.
  - `uv run python -B -m unittest tests.test_macos_app_project tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v`.
  - macOS and iPhone `xcodebuild` commands.
  - `git diff --check`.
- Known risk or unresolved issue:
  - Manual visual review on a running macOS app is still needed to judge spacing, titlebar integration, dark mode, drop affordance, and onboarding feel.
- Next best step: launch the macOS app locally, test light and dark appearances, drop a Modal/RunPod URL, drag diagnostics into TextEdit, and record screenshots.
```

Update `session-handoff.md` with the same current-state summary and next best step.

- [ ] **Step 5: Validate JSON and whitespace**

Run:

```bash
uv run python -B -m json.tool feature_list.json
git diff --check
```

Expected: JSON prints formatted content; whitespace check has no output.

- [ ] **Step 6: Commit docs and harness updates**

Run:

```bash
git add ios/README.md clean-state-checklist.md codex-progress.md feature_list.json session-handoff.md
git commit -m "docs: record macOS native UI polish"
```

---

### Task 8: Manual Visual Acceptance

**Files:**
- No source edits unless manual acceptance finds a UI defect.

- [ ] **Step 1: Launch local backend**

Run:

```bash
uv run uvicorn tarteel_realtime.dev_app:app --reload
```

Expected: backend serves `http://127.0.0.1:8000/health` and `ws://127.0.0.1:8000/ws/recitation`.

- [ ] **Step 2: Launch the macOS app from Xcode**

Open:

```text
ios/TarteelPrototype/TarteelPrototype.xcodeproj
```

Run scheme `TarteelPrototypeMac`.

Expected: the window opens with native toolbar-integrated traffic lights, no floating custom chrome, and a clear drag zone in the titlebar/toolbar area.

- [ ] **Step 3: Check core native interactions**

Verify:

- `Space` starts/stops recording and the button reads `Connecting` while startup is in progress.
- `Command-R` toggles recording from the menu.
- `Command-F` exposes/focuses Surah search.
- Light and dark appearances both use native system colors and readable contrast.
- Dropping `wss://example.modal.run/ws/recitation` or a Modal/RunPod URL text snippet sets Custom backend for the next session.
- Dragging diagnostics from the console into TextEdit produces session summary text.
- Settings show validation when Custom URL text is invalid.
- The onboarding sheet appears once, then stays dismissed after completion.

- [ ] **Step 4: Record residual risk**

If spacing, dark mode contrast, titlebar integration, drop targeting, or onboarding copy feels off, record the issue in `session-handoff.md` with the exact screenshot path or observed behavior before continuing.
