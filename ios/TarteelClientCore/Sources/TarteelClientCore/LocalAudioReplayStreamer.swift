import Foundation

public struct LocalAudioReplayConfiguration: Equatable, Sendable {
    public static let audioFlag = "--tarteel-replay-audio"
    public static let surahFlag = "--tarteel-replay-surah"

    public let audioArgument: String
    public let selectedSurahID: Int

    public init?(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaultSelectedSurahID: Int = 108
    ) {
        guard let audioArgument = Self.value(after: Self.audioFlag, in: arguments),
              !audioArgument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.audioArgument = audioArgument
        selectedSurahID = Self.value(after: Self.surahFlag, in: arguments)
            .flatMap(Int.init) ?? defaultSelectedSurahID
    }

    public func audioURL(in bundle: Bundle = .main) -> URL? {
        let expandedArgument = NSString(string: audioArgument).expandingTildeInPath
        let fileManager = FileManager.default
        let directURL = URL(fileURLWithPath: expandedArgument)
        if directURL.path.hasPrefix("/"), fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL.standardizedFileURL
        }

        let argumentURL = URL(fileURLWithPath: audioArgument)
        let resourceName = argumentURL.deletingPathExtension().lastPathComponent
        let resourceExtension = argumentURL.pathExtension
        let explicitSubdirectory = argumentURL.deletingLastPathComponent().relativePath
        let subdirectories = [
            explicitSubdirectory == "." ? nil : explicitSubdirectory,
            "local_audio",
            nil,
        ]

        for subdirectory in subdirectories {
            if let url = bundle.url(
                forResource: resourceName,
                withExtension: resourceExtension.isEmpty ? nil : resourceExtension,
                subdirectory: subdirectory
            ) {
                return url
            }
        }
        return nil
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

public struct BackendLaunchConfiguration: Equatable, Sendable {
    public static let urlFlag = "--tarteel-backend-url"
    public static let providerFlag = "--tarteel-backend-provider"

    public let urlText: String
    public let provider: BackendProvider

    public init?(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let urlText = Self.value(after: Self.urlFlag, in: arguments),
              !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.urlText = urlText
        provider = Self.value(after: Self.providerFlag, in: arguments)
            .flatMap(BackendProvider.init(rawValue:)) ?? .generic
    }

    public func preferencesDefaults(
        selectedSurahID: Int,
        recitationMode: RecitationMode = .selectedSurah
    ) -> RecitationPreferencesDefaults {
        RecitationPreferencesDefaults(
            backendPreset: .custom,
            customBackendProvider: provider,
            customBackendURLText: urlText,
            recitationMode: recitationMode,
            selectedSurahID: selectedSurahID
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

public struct LocalAudioCaptureConfiguration: Equatable, Sendable {
    public static let audioFlag = "--tarteel-capture-audio"

    public let outputArgument: String
    public let outputURL: URL

    public init?(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let outputArgument = Self.value(after: Self.audioFlag, in: arguments),
              !outputArgument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.outputArgument = outputArgument
        let expandedPath = NSString(string: outputArgument).expandingTildeInPath
        outputURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

public enum LocalAudioCaptureError: LocalizedError {
    case invalidPCMByteCount
    case unsupportedSampleRate(expected: Int, actual: Int)
    case captureAlreadyFinished
    case wavTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidPCMByteCount:
            return "Captured audio must be 16-bit PCM with an even byte count."
        case .unsupportedSampleRate(let expected, let actual):
            return "Captured audio sample rate \(actual) Hz does not match expected \(expected) Hz."
        case .captureAlreadyFinished:
            return "Captured audio cannot be appended after the WAV has been finalized."
        case .wavTooLarge:
            return "Captured audio is too large for a PCM WAV file."
        }
    }
}

public final class LocalAudioCaptureWriter: @unchecked Sendable {
    public let outputURL: URL
    public let sampleRateHz: Int

    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private var dataByteCount: UInt32 = 0
    private var isFinished = false

    public init(outputURL: URL, sampleRateHz: Int = 16_000) throws {
        self.outputURL = outputURL
        self.sampleRateHz = sampleRateHz

        let directoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: outputURL.path,
            contents: Self.wavHeader(sampleRateHz: sampleRateHz, dataByteCount: 0)
        )
        fileHandle = try FileHandle(forWritingTo: outputURL)
        try fileHandle?.seekToEnd()
        CoreMLFastConformerDiagnostics.logAudioCaptureStarted(url: outputURL)
    }

    deinit {
        try? finish()
    }

    public func append(pcm16: Data, sampleRateHz: Int) throws {
        guard pcm16.count.isMultiple(of: MemoryLayout<Int16>.size) else {
            throw LocalAudioCaptureError.invalidPCMByteCount
        }
        guard sampleRateHz == self.sampleRateHz else {
            throw LocalAudioCaptureError.unsupportedSampleRate(
                expected: self.sampleRateHz,
                actual: sampleRateHz
            )
        }

        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, let fileHandle else {
            throw LocalAudioCaptureError.captureAlreadyFinished
        }
        let nextByteCount = UInt64(dataByteCount) + UInt64(pcm16.count)
        guard nextByteCount <= UInt64(UInt32.max) else {
            throw LocalAudioCaptureError.wavTooLarge
        }

        do {
            try fileHandle.write(contentsOf: pcm16)
            dataByteCount = UInt32(nextByteCount)
        } catch {
            CoreMLFastConformerDiagnostics.logAudioCaptureFailed(url: outputURL, error: error)
            throw error
        }
    }

    public func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        guard let fileHandle else {
            isFinished = true
            return
        }

        do {
            try fileHandle.seek(toOffset: 0)
            try fileHandle.write(
                contentsOf: Self.wavHeader(
                    sampleRateHz: sampleRateHz,
                    dataByteCount: dataByteCount
                )
            )
            try fileHandle.close()
            self.fileHandle = nil
            isFinished = true
            CoreMLFastConformerDiagnostics.logAudioCaptureFinished(
                url: outputURL,
                pcmBytes: Int(dataByteCount)
            )
        } catch {
            CoreMLFastConformerDiagnostics.logAudioCaptureFailed(url: outputURL, error: error)
            throw error
        }
    }

    private static func wavHeader(sampleRateHz: Int, dataByteCount: UInt32) -> Data {
        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32LE(36 + dataByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(sampleRateHz))
        data.appendUInt32LE(UInt32(sampleRateHz * MemoryLayout<Int16>.size))
        data.appendUInt16LE(UInt16(MemoryLayout<Int16>.size))
        data.appendUInt16LE(16)
        data.appendASCII("data")
        data.appendUInt32LE(dataByteCount)
        return data
    }
}

public final class CapturingAudioStreamer: AudioStreaming, @unchecked Sendable {
    private let upstream: AudioStreaming
    private let initialCaptureWriter: LocalAudioCaptureWriter?
    private let outputURL: URL?
    private let onCaptureError: (@Sendable (Error) -> Void)?
    private var activeCaptureWriter: LocalAudioCaptureWriter?

    public init(
        upstream: AudioStreaming,
        captureWriter: LocalAudioCaptureWriter,
        onCaptureError: (@Sendable (Error) -> Void)? = nil
    ) {
        self.upstream = upstream
        self.initialCaptureWriter = captureWriter
        self.outputURL = nil
        self.onCaptureError = onCaptureError
    }

    public init(
        upstream: AudioStreaming,
        outputURL: URL,
        onCaptureError: (@Sendable (Error) -> Void)? = nil
    ) {
        self.upstream = upstream
        self.initialCaptureWriter = nil
        self.outputURL = outputURL
        self.onCaptureError = onCaptureError
    }

    public func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws {
        let captureWriter = try makeCaptureWriter()
        activeCaptureWriter = captureWriter
        try await upstream.start { [captureWriter, onCaptureError] pcm, sampleRate in
            do {
                try captureWriter.append(pcm16: pcm, sampleRateHz: sampleRate)
            } catch {
                CoreMLFastConformerDiagnostics.logAudioCaptureFailed(
                    url: captureWriter.outputURL,
                    error: error
                )
                onCaptureError?(error)
            }
            onChunk(pcm, sampleRate)
        }
    }

    public func stop() {
        upstream.stop()
        let captureWriter = activeCaptureWriter
        activeCaptureWriter = nil
        do {
            try captureWriter?.finish()
        } catch {
            onCaptureError?(error)
        }
    }

    private func makeCaptureWriter() throws -> LocalAudioCaptureWriter {
        if let outputURL {
            return try LocalAudioCaptureWriter(outputURL: outputURL)
        }
        guard let initialCaptureWriter else {
            throw CoreMLFastConformerError.invalidAudio
        }
        return initialCaptureWriter
    }
}

public final class LocalAudioReplayStreamer: AudioStreaming, @unchecked Sendable {
    public let audioURL: URL
    public let chunkSampleCount: Int
    public let emitsTerminalChunk: Bool

    private let chunks: [Data]
    private var onChunk: (@Sendable (Data, Int) -> Void)?

    public init(
        audioURL: URL,
        chunkSampleCount: Int = CoreMLFastConformerFixtureRunner.defaultLiveChunkSamples,
        emitsTerminalChunk: Bool = false
    ) throws {
        guard chunkSampleCount > 0 else {
            throw CoreMLFastConformerError.invalidAudio
        }

        self.audioURL = audioURL
        self.chunkSampleCount = chunkSampleCount
        self.emitsTerminalChunk = emitsTerminalChunk
        let audio = try CoreMLFastConformerFixtureAudio.loadWAV(from: audioURL)
        let pcm16 = audio.resampled16KPCM16
        let chunkByteCount = chunkSampleCount * MemoryLayout<Int16>.size
        var chunks: [Data] = []
        var offset = 0
        while offset < pcm16.count {
            let end = min(offset + chunkByteCount, pcm16.count)
            chunks.append(pcm16.subdata(in: offset..<end))
            offset = end
        }
        self.chunks = chunks
    }

    public func start(onChunk: @escaping @Sendable (Data, Int) -> Void) async throws {
        self.onChunk = onChunk
    }

    public func stop() {
        onChunk = nil
    }

    public func replay() async {
        guard let onChunk else { return }
        for chunk in chunks {
            onChunk(chunk, 16_000)
            await Task.yield()
        }
        if emitsTerminalChunk {
            onChunk(Data(), 16_000)
        }
    }
}

public actor LocalAudioReplayVoiceActivityDetector: VoiceActivityDetecting {
    private var hasStartedSpeech = false

    public init() {}

    public func process(pcm: Data, sampleRate: Int) async -> VoiceActivityPayload? {
        if pcm.isEmpty {
            return VoiceActivityPayload(
                probability: 0.0,
                isSpeechActive: false,
                event: .speechEnd
            )
        }

        let isFirstSpeechChunk = !hasStartedSpeech
        hasStartedSpeech = true

        return VoiceActivityPayload(
            probability: 1.0,
            isSpeechActive: true,
            event: isFirstSpeechChunk ? .speechStart : nil
        )
    }

    public func reset() async {
        hasStartedSpeech = false
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
