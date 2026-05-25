import SwiftUI

@main
struct TarteelPrototypeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: RecitationViewModel(
                audioStreamer: MicrophoneAudioStreamer(),
                voiceActivityDetector: VoiceActivityDetector()
            ))
        }
    }
}
