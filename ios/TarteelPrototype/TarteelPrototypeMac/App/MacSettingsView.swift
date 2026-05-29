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

                    Text(viewModel.customBackendProvider.tokenHelpText)
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
