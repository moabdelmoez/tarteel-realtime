import Foundation

#if canImport(FluidAudio)
import CoreML
import FluidAudio
#endif

actor VoiceActivityDetector: VoiceActivityDetecting {
    #if canImport(FluidAudio)
    private var manager: VadManager?
    private var streamState: VadStreamState?
    #endif

    func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload? {
        #if canImport(FluidAudio)
        guard sampleRate == VadManager.sampleRate else { return nil }
        let chunk = pcm.float32Samples
        guard !chunk.isEmpty else { return nil }

        do {
            let manager = try await manager()
            let state: VadStreamState
            if let existingState = streamState {
                state = existingState
            } else {
                state = await manager.makeStreamState()
            }
            let result = try await manager.processStreamingChunk(
                chunk,
                state: state,
                config: .default,
                returnSeconds: true,
                timeResolution: 2
            )
            streamState = result.state

            let event: VoiceActivityEvent?
            switch result.event?.kind {
            case .speechStart:
                event = .speechStart
            case .speechEnd:
                event = .speechEnd
            case nil:
                event = nil
            }

            return VoiceActivityPayload(
                probability: Double(result.probability),
                isSpeechActive: result.state.triggered,
                event: event
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    func reset() async {
        #if canImport(FluidAudio)
        if let manager {
            streamState = await manager.makeStreamState()
        } else {
            streamState = nil
        }
        #endif
    }

    #if canImport(FluidAudio)
    private func manager() async throws -> VadManager {
        if let manager {
            return manager
        }

        let manager: VadManager
        if let modelURL = Bundle.main.url(
            forResource: "silero-vad-unified-256ms-v6.0.0",
            withExtension: "mlmodelc"
        ) {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            let vadModel = try MLModel(contentsOf: modelURL, configuration: configuration)
            manager = VadManager(config: .default, vadModel: vadModel)
        } else {
            manager = try await VadManager()
        }
        self.manager = manager
        self.streamState = await manager.makeStreamState()
        return manager
    }
    #endif
}

#if canImport(FluidAudio)
private extension Data {
    var float32Samples: [Float] {
        var samples = [Float]()
        samples.reserveCapacity(count / MemoryLayout<Int16>.size)
        withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for sample in int16Buffer {
                samples.append(Float(sample) / 32768.0)
            }
        }
        return samples
    }
}
#endif
