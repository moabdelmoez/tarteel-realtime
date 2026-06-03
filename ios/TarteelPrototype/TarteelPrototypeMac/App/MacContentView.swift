import SwiftUI
import UniformTypeIdentifiers

struct MacContentView: View {
    @ObservedObject var viewModel: RecitationViewModel
    @AppStorage("mac.hasSeenNativeOnboarding") private var hasSeenNativeOnboarding = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var isShowingOnboarding = false

    private var filteredSurahs: [SurahMetadata] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SurahCatalog.all }

        let exactID = Int(query)
        return SurahCatalog.all.filter { surah in
            if let exactID, surah.id == exactID {
                return true
            }
            return surah.nameSimple.localizedCaseInsensitiveContains(query)
                || surah.nameArabic.localizedCaseInsensitiveContains(query)
        }
    }

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
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MacTheme.teal, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(10)
                    .transition(.opacity)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search surahs") {
            ForEach(filteredSurahs.prefix(8)) { surah in
                Text(surah.displayName)
                    .searchCompletion(surah.nameSimple)
            }
        }
        .focused($isSearchFocused)
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
        .onAppear {
            guard !hasSeenNativeOnboarding else { return }
            isShowingOnboarding = true
            hasSeenNativeOnboarding = true
        }
        .sheet(isPresented: $isShowingOnboarding) {
            NativeOnboardingSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusMacSurahSearch)) { _ in
            isSearchFocused = true
        }
        .onDrop(of: [UTType.url.identifier, UTType.plainText.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.snappy(duration: 0.2), value: viewModel.state.phase)
        .animation(.snappy(duration: 0.2), value: viewModel.recentEventHistory)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for typeIdentifier in [UTType.url.identifier, UTType.plainText.identifier] {
            guard let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(typeIdentifier)
            }) else {
                continue
            }

            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                guard error == nil, let text = Self.droppedText(from: item) else { return }
                Task { @MainActor in
                    _ = viewModel.applyDroppedBackendText(text)
                }
            }
            return true
        }

        return false
    }

    private static func droppedText(from item: NSSecureCoding?) -> String? {
        if let url = item as? URL {
            return url.absoluteString
        }
        if let url = item as? NSURL {
            return url.absoluteString
        }
        if let string = item as? String {
            return string
        }
        if let string = item as? NSString {
            return string as String
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
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
            Label(viewModel.recordingActionTitle, systemImage: viewModel.recordingActionSystemImage)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRecording ? MacTheme.warning : MacTheme.teal)
        .disabled(!viewModel.canStartRecording && !viewModel.isRecording)
        .help(viewModel.recordingActionHelp)
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
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.06),
                        value: isActive
                    )
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
                .foregroundStyle(MacTheme.ink)

            StatusRow(title: "Connection", value: viewModel.connectionStatus)
            StatusRow(title: "Last event", value: viewModel.state.debugLastEventText)
            StatusRow(title: "Ayah", value: viewModel.state.debugAyahText)
            StatusRow(title: "Ayah text", value: viewModel.state.debugAyahBodyText)
            StatusRow(title: "Transcript", value: viewModel.state.debugTranscriptText)

            if let errorMessage = viewModel.errorMessage {
                StatusRow(title: "Error", value: errorMessage, isError: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostic Summary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MacTheme.muted)
                Text(viewModel.shareableSessionSummary)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MacTheme.ink)
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .draggable(viewModel.shareableSessionSummary)
            }

            Divider()

            Text("Recent Events")
                .font(.headline)
                .foregroundStyle(MacTheme.ink)

            if viewModel.recentEventHistory.isEmpty {
                ContentUnavailableView(
                    "No Recent Events",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Start recording to see backend events.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.recentEventHistory) { item in
                            EventHistoryRow(item: item)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(22)
        .background(.regularMaterial)
    }
}

private struct EventHistoryRow: View {
    let item: RecitationEventHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.typeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MacTheme.ink)
                Spacer(minLength: 8)
                if let chunkSequence = item.chunkSequence {
                    Text("#\(chunkSequence)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(MacTheme.muted)
                }
            }

            HStack(spacing: 8) {
                if let ayahRef = item.ayahRef {
                    Text(ayahRef)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(MacTheme.teal)
                }
                Text(item.detailText)
                    .font(.caption)
                    .foregroundStyle(MacTheme.muted)
                    .lineLimit(2)
            }

            if !item.transcript.isEmpty {
                Text(item.transcript)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MacTheme.ink)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct NativeOnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(MacTheme.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tarteel Realtime")
                        .font(.title2.weight(.semibold))
                    Text("Native macOS recitation surface")
                        .foregroundStyle(MacTheme.muted)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                OnboardingRow(systemImage: "record.circle", title: "Record", detail: "Use the toolbar record action or space bar.")
                OnboardingRow(systemImage: "magnifyingglass", title: "Search", detail: "Find surahs from the toolbar search field.")
                OnboardingRow(systemImage: "arrow.down.doc", title: "Drop", detail: "Drop a backend URL or text endpoint onto the window.")
                OnboardingRow(systemImage: "square.and.arrow.up", title: "Share", detail: "Drag the diagnostic summary into notes or an issue.")
            }

            HStack {
                Spacer()
                Button("Continue") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 460)
    }
}

private struct OnboardingRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(MacTheme.teal)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(MacTheme.muted)
            }
        }
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
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let line = Color(nsColor: .separatorColor)
    static let teal = Color(nsColor: .controlAccentColor)
    static let warning = Color(nsColor: .systemRed)
}

extension Notification.Name {
    static let focusMacSurahSearch = Notification.Name("focusMacSurahSearch")
}
