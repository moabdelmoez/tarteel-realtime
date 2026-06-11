import AVFoundation
import Foundation

final class MacMicrophoneAudioStreamer: AudioStreaming, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sampleRate = 16_000
    private let outputChunkSampleCount = CoreMLFastConformerFixtureRunner.defaultLiveChunkSamples
    private var isTapInstalled = false
    private var pendingPCM = Data()

    func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws {
        stop()

        guard await Self.requestMicrophonePermission() else {
            throw MacMicrophoneAudioStreamerError.microphonePermissionDenied
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MacMicrophoneAudioStreamerError.unsupportedInputFormat
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw MacMicrophoneAudioStreamerError.unsupportedFormat
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            let sourceFormat = buffer.format
            guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
                return
            }
            guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
                return
            }

            let frameCapacity = max(
                1,
                AVAudioFrameCount(ceil(Double(buffer.frameLength) * outputFormat.sampleRate / sourceFormat.sampleRate))
            )
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCapacity
            ) else {
                return
            }

            var error: NSError?
            var didProvideInput = false
            converter.convert(to: converted, error: &error) { _, status in
                guard !didProvideInput else {
                    status.pointee = .noDataNow
                    return nil
                }

                didProvideInput = true
                status.pointee = .haveData
                return buffer
            }

            guard error == nil, let data = converted.pcm16Data else {
                return
            }
            self.emitCoalescedChunks(from: data, onChunk: onChunk)
        }
        isTapInstalled = true

        engine.prepare()
        try engine.start()
    }

    func stop() {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
        pendingPCM.removeAll(keepingCapacity: true)
    }

    private func emitCoalescedChunks(
        from data: Data,
        onChunk: @escaping @Sendable (Data, Int) -> Void
    ) {
        pendingPCM.append(data)
        let chunkByteCount = outputChunkSampleCount * MemoryLayout<Int16>.size
        while pendingPCM.count >= chunkByteCount {
            let chunk = Data(pendingPCM.prefix(chunkByteCount))
            pendingPCM.removeFirst(chunkByteCount)
            onChunk(chunk, sampleRate)
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }
}

enum MacMicrophoneAudioStreamerError: LocalizedError {
    case microphonePermissionDenied
    case unsupportedInputFormat
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable it in macOS Settings, then try again."
        case .unsupportedInputFormat:
            return "The microphone input format is not ready. Select an audio input and try again."
        case .unsupportedFormat:
            return "The microphone format is not supported."
        }
    }
}

private extension AVAudioPCMBuffer {
    var pcm16Data: Data? {
        guard let channelData = int16ChannelData else { return nil }
        let frameCount = Int(frameLength)
        return Data(bytes: channelData[0], count: frameCount * MemoryLayout<Int16>.size)
    }
}
