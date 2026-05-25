# iOS Clean Home Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move backend-only controls behind a settings gear and restyle the iOS home screen as a clean white recitation surface.

**Architecture:** Keep `RecitationViewModel` and WebSocket behavior unchanged. Update `ContentView.swift` composition and light-theme styling, then adjust source guardrails to protect control placement.

**Tech Stack:** SwiftUI, existing Swift client core, Python unittest source guardrails, Xcode iOS simulator build.

---

### Task 1: Guard Settings And Home Control Placement

**Files:**
- Modify: `tests/test_ios_recitation_scope_ui.py`
- Modify: `tests/test_ios_websocket_client.py`

- [ ] **Step 1: Add source guardrails**

Update `tests/test_ios_recitation_scope_ui.py` so the recitation controls are still present and a settings sheet exists:

```python
def test_content_view_keeps_recitation_controls_on_home_screen(self) -> None:
    source = (APP_ROOT / "ContentView.swift").read_text(encoding="utf-8")

    self.assertIn("Picker(\"Recitation\"", source)
    self.assertIn("selectRecitationMode", source)
    self.assertIn("Text(\"Auto\").tag(RecitationMode.autoDetect)", source)
    self.assertIn("Text(\"Surah\").tag(RecitationMode.selectedSurah)", source)
    self.assertIn("Picker(\"Surah\"", source)
    self.assertIn("ForEach(SurahCatalog.all)", source)
    self.assertIn("Image(systemName: \"gearshape.fill\")", source)
    self.assertIn("SettingsSheet(", source)
```

Update `tests/test_ios_websocket_client.py` so the RunPod key field is protected as a settings control:

```python
def test_content_view_exposes_prototype_only_runpod_key_field_in_settings(self) -> None:
    source = (APP_ROOT / "ContentView.swift").read_text(encoding="utf-8")

    self.assertIn("private struct SettingsSheet", source)
    self.assertIn('SecureField("RunPod API key"', source)
    self.assertIn("prototype-only direct RunPod", source)
```

- [ ] **Step 2: Verify the guardrails fail before UI changes**

Run:

```bash
uv run python -B -m unittest tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client -v
```

Expected: FAIL because `gearshape.fill` and `SettingsSheet` do not exist yet.

### Task 2: Implement Clean Home And Settings Sheet

**Files:**
- Modify: `ios/TarteelPrototype/TarteelPrototype/App/ContentView.swift`

- [ ] **Step 1: Update `ContentView` state and layout**

Add:

```swift
@State private var isShowingSettings = false
```

Render a white background, a top gear button, the status panel, recitation controls, state copy, voice indicator, and mic button. Present:

```swift
.sheet(isPresented: $isShowingSettings) {
    SettingsSheet(viewModel: viewModel)
}
```

- [ ] **Step 2: Move backend controls into `SettingsSheet`**

Create:

```swift
private struct SettingsSheet: View {
    @ObservedObject var viewModel: RecitationViewModel

    var body: some View {
        NavigationStack {
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
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.footnote.monospaced())
                        .disabled(viewModel.isRecording || !viewModel.backendPreset.allowsURLTextEditing)

                    if viewModel.backendPreset == .custom {
                        SecureField("RunPod API key", text: $viewModel.runPodAPIKeyText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote.monospaced())
                            .disabled(viewModel.isRecording)

                        Text("prototype-only direct RunPod")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

- [ ] **Step 3: Verify focused tests pass**

Run:

```bash
uv run python -B -m unittest tests.test_ios_recitation_scope_ui tests.test_ios_websocket_client tests.test_ios_status_panel -v
```

Expected: PASS.

### Task 3: Build And Record Evidence

**Files:**
- Modify: `codex-progress.md`
- Modify: `feature_list.json`
- Modify: `session-handoff.md`
- Modify: `quality-document.md`

- [ ] **Step 1: Run Swift client tests**

Run from `ios/TarteelClientCore`:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/tarteel-clang-module-cache SWIFT_MODULE_CACHE_PATH=/private/tmp/tarteel-swift-module-cache swift test
```

Expected: PASS.

- [ ] **Step 2: Build the iOS app**

Run:

```bash
xcodebuild -project ios/TarteelPrototype/TarteelPrototype.xcodeproj -scheme TarteelPrototype -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tarteel-xcode-derived-ios-clean-home CODE_SIGNING_ALLOWED=NO build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Update harness docs**

Record changed UI behavior, exact verification commands, and remaining manual Simulator/device visual-test risk in the harness docs.
