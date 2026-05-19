import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

actor VoiceActivityDetector {
    #if canImport(FluidAudio)
    private var manager: VadManager?
    private var streamState: VadStreamState?
    #endif

    func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload? {
        #if canImport(FluidAudio)
        guard sampleRate == VadManager.sampleRate else { return nil }
        do {
            let manager = try await manager()
            var state = try await streamState ?? manager.makeStreamState()
            let result = try await manager.processStreamingChunk(
                pcm.float32Samples,
                state: state,
                config: .default,
                returnSeconds: true,
                timeResolution: 2
            )
            state = result.state
            streamState = state

            let event: VoiceActivityEvent?
            switch result.event?.kind {
            case .speechStart:
                event = .speechStart
            case .speechEnd:
                event = .speechEnd
            case nil:
                event = nil
            @unknown default:
                event = nil
            }

            return VoiceActivityPayload(
                probability: result.probability,
                isSpeechActive: result.probability >= 0.5,
                event: event
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(FluidAudio)
    private func manager() async throws -> VadManager {
        if let manager {
            return manager
        }
        let manager = try await VadManager()
        self.manager = manager
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
