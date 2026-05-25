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
