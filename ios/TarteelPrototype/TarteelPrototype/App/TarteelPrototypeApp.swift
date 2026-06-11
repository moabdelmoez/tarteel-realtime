import SwiftUI

@main
struct TarteelPrototypeApp: App {
    @StateObject private var viewModel: RecitationViewModel
    @State private var didStartReplay = false

    private let replayConfiguration: LocalAudioReplayConfiguration?
    private let replayStreamer: LocalAudioReplayStreamer?
    private let captureConfiguration: LocalAudioCaptureConfiguration?

    init() {
        let replayConfiguration = LocalAudioReplayConfiguration()
        let replayStreamer = Self.makeReplayStreamer(replayConfiguration: replayConfiguration)
        let captureConfiguration = LocalAudioCaptureConfiguration()
        self.replayConfiguration = replayConfiguration
        self.replayStreamer = replayStreamer
        self.captureConfiguration = captureConfiguration
        _viewModel = StateObject(
            wrappedValue: Self.makeViewModel(
                replayConfiguration: replayConfiguration,
                replayStreamer: replayStreamer,
                captureConfiguration: captureConfiguration
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .task {
                    await startReplayIfNeeded()
                }
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
        replayStreamer: LocalAudioReplayStreamer?,
        captureConfiguration: LocalAudioCaptureConfiguration?
    ) -> RecitationViewModel {
        let audioStreamer = Self.makeAudioStreamer(
            replayStreamer: replayStreamer,
            captureConfiguration: captureConfiguration
        )
        let preferencesStore: RecitationPreferencesStoring
        if let replayConfiguration {
            preferencesStore = VolatileRecitationPreferencesStore(
                defaults: RecitationPreferencesDefaults(
                    backendPreset: .coreML,
                    recitationMode: .selectedSurah,
                    selectedSurahID: replayConfiguration.selectedSurahID
                )
            )
        } else {
            preferencesStore = UserDefaultsRecitationPreferencesStore(fallbackValues: .coreMLSelectedSurah108)
        }

        return RecitationViewModel(
            socketClient: RoutingBackendSocketClient(
                coreML: CoreMLFastConformerSocketClient(bundle: .main)
            ),
            audioStreamer: audioStreamer,
            voiceActivityDetector: VoiceActivityDetector(),
            preferencesStore: preferencesStore
        )
    }

    private static func makeAudioStreamer(
        replayStreamer: LocalAudioReplayStreamer?,
        captureConfiguration: LocalAudioCaptureConfiguration?
    ) -> AudioStreaming {
        let baseAudioStreamer: AudioStreaming = replayStreamer ?? MicrophoneAudioStreamer()
        guard let captureConfiguration else {
            return baseAudioStreamer
        }
        return CapturingAudioStreamer(
            upstream: baseAudioStreamer,
            outputURL: captureConfiguration.outputURL
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
