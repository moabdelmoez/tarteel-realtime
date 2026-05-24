import SwiftUI

struct ContentView: View {
    @StateObject var viewModel: RecitationViewModel

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.02, blue: 0.05)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

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
                    .padding(.bottom, 2)

                    if viewModel.recitationMode == .selectedSurah {
                        Picker("Surah", selection: $viewModel.selectedSurahID) {
                            ForEach(SurahCatalog.all) { surah in
                                Text(surah.displayName).tag(surah.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)
                        .disabled(viewModel.isRecording)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

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
                    .padding(.bottom, 4)

                    TextField("Backend URL", text: $viewModel.backendURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(viewModel.isRecording || !viewModel.backendPreset.allowsURLTextEditing)
                        .padding(.bottom, 12)

                    DebugStatusPanel(
                        connectionStatus: viewModel.connectionStatus,
                        state: viewModel.state,
                        errorMessage: viewModel.errorMessage
                    )
                    .padding(.bottom, 8)

                    Text(viewModel.state.headline)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(viewModel.state.detail)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 28)

                VoiceActivityIndicator(isActive: viewModel.isRecording)

                Spacer()

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Button(action: { viewModel.toggleRecording() }) {
                    Image(systemName: viewModel.isRecording ? "xmark" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 74, height: 74)
                        .background(viewModel.isRecording ? Color.red.opacity(0.85) : Color.teal)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                }
                .accessibilityLabel(viewModel.isRecording ? "Stop recitation" : "Start recitation")
                .padding(.bottom, 28)
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
        .padding(12)
        .background(.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.14), lineWidth: 1)
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
                .foregroundStyle(.white.opacity(0.64))
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(isError ? .red.opacity(0.9) : .white.opacity(0.92))
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
                    .fill(.white)
                    .frame(width: 54, height: isActive ? CGFloat(46 + (index % 2) * 30) : 46)
                    .opacity(isActive ? 1.0 : 0.45)
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
