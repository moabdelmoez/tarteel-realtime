import SwiftUI

@main
struct TarteelPrototypeApp: App {
    @StateObject private var viewModel: RecitationViewModel
    @State private var didStartReplay = false

    private let replayConfiguration: LocalAudioReplayConfiguration?
    private let replayStreamer: LocalAudioReplayStreamer?
    private let captureConfiguration: LocalAudioCaptureConfiguration?
    private let backendConfiguration: BackendLaunchConfiguration?

    init() {
        let replayConfiguration = LocalAudioReplayConfiguration()
        let replayStreamer = Self.makeReplayStreamer(replayConfiguration: replayConfiguration)
        let captureConfiguration = LocalAudioCaptureConfiguration()
        let backendConfiguration = BackendLaunchConfiguration()
        self.replayConfiguration = replayConfiguration
        self.replayStreamer = replayStreamer
        self.captureConfiguration = captureConfiguration
        self.backendConfiguration = backendConfiguration
        _viewModel = StateObject(
            wrappedValue: Self.makeViewModel(
                replayConfiguration: replayConfiguration,
                replayStreamer: replayStreamer,
                captureConfiguration: captureConfiguration,
                backendConfiguration: backendConfiguration
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
        captureConfiguration: LocalAudioCaptureConfiguration?,
        backendConfiguration: BackendLaunchConfiguration?
    ) -> RecitationViewModel {
        let audioStreamer = Self.makeAudioStreamer(
            replayStreamer: replayStreamer,
            captureConfiguration: captureConfiguration
        )
        let preferencesStore: RecitationPreferencesStoring
        if let replayConfiguration {
            preferencesStore = VolatileRecitationPreferencesStore(
                defaults: backendConfiguration?.preferencesDefaults(
                    selectedSurahID: replayConfiguration.selectedSurahID
                ) ?? RecitationPreferencesDefaults(
                    backendPreset: .coreML,
                    recitationMode: .selectedSurah,
                    selectedSurahID: replayConfiguration.selectedSurahID
                )
            )
        } else if let backendConfiguration {
            preferencesStore = VolatileRecitationPreferencesStore(
                defaults: backendConfiguration.preferencesDefaults(selectedSurahID: 108)
            )
        } else {
            preferencesStore = UserDefaultsRecitationPreferencesStore(fallbackValues: .coreMLSelectedSurah108)
        }

        return RecitationViewModel(
            socketClient: RoutingBackendSocketClient(
                coreML: CoreMLFastConformerSocketClient(bundle: .main)
            ),
            audioStreamer: audioStreamer,
            voiceActivityDetector: makeVoiceActivityDetector(replayStreamer: replayStreamer),
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
        return try? LocalAudioReplayStreamer(
            audioURL: audioURL,
            emitsTerminalChunk: true
        )
    }

    private static func makeVoiceActivityDetector(
        replayStreamer: LocalAudioReplayStreamer?
    ) -> VoiceActivityDetecting {
        if replayStreamer != nil {
            return LocalAudioReplayVoiceActivityDetector()
        }
        return VoiceActivityDetector()
    }
}
