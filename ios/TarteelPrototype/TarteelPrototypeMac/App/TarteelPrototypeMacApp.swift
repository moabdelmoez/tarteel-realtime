import SwiftUI

@main
struct TarteelPrototypeMacApp: App {
    @StateObject private var viewModel: RecitationViewModel
    @State private var didStartReplay = false

    private let replayConfiguration: LocalAudioReplayConfiguration?
    private let replayStreamer: LocalAudioReplayStreamer?

    init() {
        let replayConfiguration = LocalAudioReplayConfiguration()
        let replayStreamer = Self.makeReplayStreamer(replayConfiguration: replayConfiguration)
        self.replayConfiguration = replayConfiguration
        self.replayStreamer = replayStreamer
        _viewModel = StateObject(
            wrappedValue: Self.makeViewModel(
                replayConfiguration: replayConfiguration,
                replayStreamer: replayStreamer
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            MacContentView(viewModel: viewModel)
                .task {
                    await startReplayIfNeeded()
                }
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

    @MainActor
    private func startReplayIfNeeded() async {
        guard replayConfiguration != nil, let replayStreamer, !didStartReplay else {
            return
        }

        didStartReplay = true
        await viewModel.startRecording()
        await replayStreamer.replay()
    }

    private static func makeViewModel(
        replayConfiguration: LocalAudioReplayConfiguration?,
        replayStreamer: LocalAudioReplayStreamer?
    ) -> RecitationViewModel {
        let audioStreamer: AudioStreaming = replayStreamer ?? MacMicrophoneAudioStreamer()
        let preferencesStore: RecitationPreferencesStoring
        let backendBearerTokenStore: BackendBearerTokenStoring
        if let replayConfiguration {
            preferencesStore = VolatileRecitationPreferencesStore(
                defaults: RecitationPreferencesDefaults(
                    backendPreset: .coreML,
                    recitationMode: .selectedSurah,
                    selectedSurahID: replayConfiguration.selectedSurahID
                )
            )
            backendBearerTokenStore = VolatileBackendBearerTokenStore()
        } else {
            preferencesStore = UserDefaultsRecitationPreferencesStore(fallbackValues: .coreMLSelectedSurah108)
            backendBearerTokenStore = KeychainBackendBearerTokenStore()
        }

        return RecitationViewModel(
            socketClient: RoutingBackendSocketClient(
                coreML: CoreMLFastConformerSocketClient(bundle: .main)
            ),
            audioStreamer: audioStreamer,
            voiceActivityDetector: VoiceActivityDetector(),
            preferencesStore: preferencesStore,
            backendBearerTokenStore: backendBearerTokenStore
        )
    }

    private static func makeReplayStreamer(
        replayConfiguration: LocalAudioReplayConfiguration?
    ) -> LocalAudioReplayStreamer? {
        guard let replayConfiguration,
              let audioURL = replayConfiguration.audioURL(in: .main) else {
            return nil
        }
        return try? LocalAudioReplayStreamer(audioURL: audioURL)
    }
}
