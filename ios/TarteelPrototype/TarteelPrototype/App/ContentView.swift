import SwiftUI

struct ContentView: View {
    @StateObject var viewModel: RecitationViewModel
    @State private var isShowingSettings = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()

                    Button(action: { isShowingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.slate)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.softGray)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Settings")
                }
                .padding(.top, 10)

                VStack(spacing: 20) {
                    DebugStatusPanel(
                        connectionStatus: viewModel.connectionStatus,
                        state: viewModel.state,
                        errorMessage: viewModel.errorMessage
                    )

                    Text(viewModel.state.headline)
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(viewModel.state.detail)
                        .font(.title3)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)

                    RecitationControlPanel(viewModel: viewModel)
                }

                VoiceActivityIndicator(isActive: viewModel.isRecording)

                Spacer()

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.warning)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                }

                Button(action: { viewModel.toggleRecording() }) {
                    Image(systemName: viewModel.isRecording ? "xmark" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 74, height: 74)
                        .background(viewModel.isRecording ? AppTheme.warning : AppTheme.teal)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.teal.opacity(viewModel.isRecording ? 0 : 0.24), radius: 18, y: 8)
                }
                .accessibilityLabel(viewModel.isRecording ? "Stop recitation" : "Start recitation")
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(viewModel: viewModel)
        }
    }
}

private enum AppTheme {
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.15)
    static let slate = Color(red: 0.24, green: 0.29, blue: 0.37)
    static let muted = Color(red: 0.39, green: 0.43, blue: 0.50)
    static let softGray = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let line = Color(red: 0.84, green: 0.87, blue: 0.91)
    static let teal = Color(red: 0.11, green: 0.58, blue: 0.64)
    static let paleTeal = Color(red: 0.89, green: 0.98, blue: 0.98)
    static let warning = Color(red: 0.85, green: 0.20, blue: 0.22)
}

private struct RecitationControlPanel: View {
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
            .tint(AppTheme.teal)
            .disabled(viewModel.isRecording)

            if viewModel.recitationMode == .selectedSurah {
                Picker("Surah", selection: $viewModel.selectedSurahID) {
                    ForEach(SurahCatalog.all) { surah in
                        Text(surah.displayName).tag(surah.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.teal)
                .disabled(viewModel.isRecording)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.paleTeal)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.teal.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct SettingsSheet: View {
    @ObservedObject var viewModel: RecitationViewModel
    @Environment(\.dismiss) private var dismiss

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DebugStatusPanel: View {
    let connectionStatus: String
    let state: RecitationSessionState
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            DebugStatusRow(title: "Connection", value: connectionStatus)
            DebugStatusRow(title: "Last event", value: state.debugLastEventText)
            DebugStatusRow(title: "Ayah", value: state.debugAyahText)
            DebugStatusRow(title: "Ayah text", value: state.debugAyahBodyText)

            if let errorMessage, !errorMessage.isEmpty {
                DebugStatusRow(title: "Error", value: errorMessage, isError: true)
            }
        }
        .padding(14)
        .background(AppTheme.softGray)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DebugStatusRow: View {
    let title: String
    let value: String
    var isError = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(isError ? AppTheme.warning : AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct VoiceActivityIndicator: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(isActive ? AppTheme.teal : AppTheme.line)
                    .frame(width: 54, height: isActive ? CGFloat(46 + (index % 2) * 30) : 46)
                    .opacity(isActive ? 1.0 : 0.78)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: isActive
                    )
            }
        }
        .frame(height: 96)
    }
}
