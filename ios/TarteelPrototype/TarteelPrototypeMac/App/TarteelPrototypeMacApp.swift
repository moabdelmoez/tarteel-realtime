import SwiftUI

@main
struct TarteelPrototypeMacApp: App {
    @StateObject private var viewModel = RecitationViewModel(
        audioStreamer: MacMicrophoneAudioStreamer(),
        voiceActivityDetector: VoiceActivityDetector(),
        preferencesStore: UserDefaultsRecitationPreferencesStore(fallbackValues: .modalPrimary),
        backendBearerTokenStore: KeychainBackendBearerTokenStore()
    )

    var body: some Scene {
        WindowGroup {
            MacContentView(viewModel: viewModel)
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("Recitation") {
                Button(viewModel.recordingActionTitle) {
                    viewModel.toggleRecording()
                }
                .disabled(!viewModel.canStartRecording && !viewModel.isRecording)
                .keyboardShortcut("r", modifiers: [.command])

                Button("Search Surahs") {
                    NotificationCenter.default.post(name: .focusMacSurahSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
        }

        Settings {
            MacSettingsView(viewModel: viewModel)
        }
    }
}
