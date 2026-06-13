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
                .help("Choose the backend preset used for the next recitation session")

                TextField("Backend URL", text: $viewModel.backendURLText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(viewModel.isRecording || !viewModel.backendPreset.allowsURLTextEditing)

                if let message = viewModel.backendURLValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if viewModel.isRecording {
                    Text("Settings controls are locked while recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.backendPreset == .custom {
                    LabeledContent("Provider") {
                        Text(BackendProvider.modal.label)
                    }
                    .onAppear {
                        viewModel.selectModalCustomBackendProviderForSettings()
                    }

                    Picker("ASR model", selection: Binding(
                        get: { viewModel.modalASRModel },
                        set: { viewModel.selectModalASRModel($0) }
                    )) {
                        ForEach(ModalASRModel.allCases) { model in
                            Text(model.label).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRecording)

                    SecureField(BackendProvider.modal.tokenFieldLabel, text: $viewModel.backendBearerTokenText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(viewModel.isRecording)
                        .help(viewModel.backendBearerTokenPersistenceMessage ?? tokenHelpText)

                    if let tokenMessage = viewModel.backendBearerTokenPersistenceMessage {
                        Label(tokenMessage, systemImage: "key.horizontal")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(tokenHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }

    private var tokenHelpText: String {
        "Saved securely in macOS Keychain for this Mac user and selected provider."
    }
}
