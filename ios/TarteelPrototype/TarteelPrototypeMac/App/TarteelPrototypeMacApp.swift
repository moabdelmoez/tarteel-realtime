import SwiftUI

@main
struct TarteelPrototypeMacApp: App {
    @StateObject private var viewModel = RecitationViewModel(
        audioStreamer: MacMicrophoneAudioStreamer(),
        voiceActivityDetector: VoiceActivityDetector()
    )

    var body: some Scene {
        WindowGroup {
            MacContentView(viewModel: viewModel)
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button(viewModel.isRecording ? "Stop Recitation" : "Start Recitation") {
                    viewModel.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            MacSettingsView(viewModel: viewModel)
        }
    }
}
