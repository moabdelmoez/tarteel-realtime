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

public final class LocalAudioReplayStreamer: AudioStreaming, @unchecked Sendable {
    public let audioURL: URL
    public let chunkSampleCount: Int

    private let chunks: [Data]
    private var onChunk: (@Sendable (Data, Int) -> Void)?

    public init(
        audioURL: URL,
        chunkSampleCount: Int = CoreMLFastConformerFixtureRunner.defaultLiveChunkSamples
    ) throws {
        guard chunkSampleCount > 0 else {
            throw CoreMLFastConformerError.invalidAudio
        }

        self.audioURL = audioURL
        self.chunkSampleCount = chunkSampleCount
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
    }
}
