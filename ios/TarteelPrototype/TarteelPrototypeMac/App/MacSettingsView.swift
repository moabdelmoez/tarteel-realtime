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
                    Picker("Provider", selection: Binding(
                        get: { viewModel.customBackendProvider },
                        set: { viewModel.selectCustomBackendProvider($0) }
                    )) {
                        ForEach(BackendProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isRecording)

                    SecureField(viewModel.customBackendProvider.tokenFieldLabel, text: $viewModel.backendBearerTokenText)
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
