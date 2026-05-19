import SwiftUI

@main
struct TarteelPrototypeApp: App {
    private let smokeArguments = ProcessInfo.processInfo.arguments

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: makeViewModel(),
                shouldAutostartLiveKit: smokeArguments.contains("--tarteel-autostart-livekit")
            )
        }
    }

    @MainActor
    private func makeViewModel() -> RecitationViewModel {
        let viewModel = RecitationViewModel()
        if smokeArguments.contains("--tarteel-autostart-livekit") {
            viewModel.selectBackendPreset(.liveKitLocal)
        }
        return viewModel
    }
}
