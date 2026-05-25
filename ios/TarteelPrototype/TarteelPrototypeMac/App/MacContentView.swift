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
