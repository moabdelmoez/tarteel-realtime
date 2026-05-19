import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

actor VoiceActivityDetector {
    #if canImport(FluidAudio)
    private var manager: VadManager?
    private var pendingSamples: [Float] = []
    private var isSpeechActive = false
    #endif

    func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload? {
        #if canImport(FluidAudio)
        guard sampleRate == VadManager.sampleRate else { return nil }
        pendingSamples.append(contentsOf: pcm.float32Samples)
        guard pendingSamples.count >= VadManager.chunkSize else { return nil }

        let chunk = Array(pendingSamples.prefix(VadManager.chunkSize))
        pendingSamples.removeFirst(VadManager.chunkSize)

        do {
            let manager = try await manager()
            guard let result = try await manager.process(chunk).last else {
                return nil
            }

            let event: VoiceActivityEvent?
            if result.isVoiceActive && !isSpeechActive {
                event = .speechStart
            } else if !result.isVoiceActive && isSpeechActive {
                event = .speechEnd
            } else {
                event = nil
            }
            isSpeechActive = result.isVoiceActive

            return VoiceActivityPayload(
                probability: Double(result.probability),
                isSpeechActive: result.isVoiceActive,
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
