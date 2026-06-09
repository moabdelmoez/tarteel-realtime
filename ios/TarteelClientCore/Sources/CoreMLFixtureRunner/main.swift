import Foundation
import TarteelClientCore

@main
struct CoreMLFixtureRunnerCLI {
    static func main() {
        do {
            let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
            let runner = CoreMLFastConformerFixtureRunner(
                modelDirectoryURL: arguments.modelDirectoryURL,
                padsFinalWindow: arguments.padsFinalWindow
            )
            let reports: [CoreMLFastConformerFixtureReport]
            if !arguments.audioURLs.isEmpty {
                reports = try arguments.audioURLs.map { try runner.run(audioURL: $0) }
            } else {
                reports = try runner.run(audioDirectoryURL: arguments.audioDirectoryURL)
            }
            let printableReports: [CoreMLFastConformerFixtureReport]
            if let manifestURL = arguments.manifestURL {
                let manifest = try CoreMLFastConformerFixtureManifest.load(from: manifestURL)
                printableReports = try reports.map { report in
                    try report.scored(
                        with: manifest.expectation(forAudioPath: report.audioPath)
                    )
                }
            } else {
                printableReports = reports
            }

            if arguments.printsJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(printableReports)
                print(String(decoding: data, as: UTF8.self))
            } else {
                for (index, report) in printableReports.enumerated() {
                    if index > 0 { print("") }
                    print(report.textSummary())
                }
            }
        } catch {
            fputs("\(error.localizedDescription)\n\n\(Arguments.usage)\n", stderr)
            Foundation.exit(2)
        }
    }
}

private struct Arguments {
    let modelDirectoryURL: URL
    let audioDirectoryURL: URL
    let audioURLs: [URL]
    let manifestURL: URL?
    let printsJSON: Bool
    let padsFinalWindow: Bool

    static let usage = """
    Usage:
      swift run coreml-fixture-runner --model-dir <path> --audio-dir <path> [--manifest <path>] [--json] [--no-pad-final-window]
      swift run coreml-fixture-runner --model-dir <path> --audio <path> [--audio <path> ...] [--manifest <path>] [--json] [--no-pad-final-window]

    Example:
      swift run coreml-fixture-runner \\
        --model-dir ../../.models/fastconformer-quran-coreml-streaming \\
        --audio-dir /Users/mostafa/Downloads/Coding_Projects/tarteel-realtime/fixtures/local_audio \\
        --manifest fixtures/local_audio_manifest.json
    """

    static func parse(_ arguments: [String]) throws -> Arguments {
        var modelDirectoryURL: URL?
        var audioDirectoryURL: URL?
        var audioURLs: [URL] = []
        var manifestURL: URL?
        var printsJSON = false
        var padsFinalWindow = true
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--model-dir":
                modelDirectoryURL = try valueURL(after: argument, in: arguments, at: &index)
            case "--audio-dir":
                audioDirectoryURL = try valueURL(after: argument, in: arguments, at: &index)
            case "--audio":
                audioURLs.append(try valueURL(after: argument, in: arguments, at: &index))
            case "--manifest":
                manifestURL = try valueURL(after: argument, in: arguments, at: &index)
            case "--json":
                printsJSON = true
            case "--no-pad-final-window":
                padsFinalWindow = false
            case "--help", "-h":
                throw CLIError.helpRequested
            default:
                throw CLIError.invalidArgument(argument)
            }
            index += 1
        }

        guard let modelDirectoryURL else {
            throw CLIError.missingRequiredArgument("--model-dir")
        }
        if audioDirectoryURL == nil, audioURLs.isEmpty {
            throw CLIError.missingRequiredArgument("--audio-dir or --audio")
        }
        if audioDirectoryURL != nil, !audioURLs.isEmpty {
            throw CLIError.invalidArgument("choose either --audio-dir or repeated --audio, not both")
        }

        return Arguments(
            modelDirectoryURL: modelDirectoryURL,
            audioDirectoryURL: audioDirectoryURL ?? URL(fileURLWithPath: "."),
            audioURLs: audioURLs,
            manifestURL: manifestURL,
            printsJSON: printsJSON,
            padsFinalWindow: padsFinalWindow
        )
    }

    private static func valueURL(
        after flag: String,
        in arguments: [String],
        at index: inout Int
    ) throws -> URL {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError.missingValue(flag)
        }
        index = valueIndex
        return URL(fileURLWithPath: arguments[valueIndex]).standardizedFileURL
    }
}

private enum CLIError: LocalizedError {
    case helpRequested
    case invalidArgument(String)
    case missingRequiredArgument(String)
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return "Help requested."
        case .invalidArgument(let argument):
            return "Invalid argument: \(argument)"
        case .missingRequiredArgument(let argument):
            return "Missing required argument: \(argument)"
        case .missingValue(let flag):
            return "Missing value after \(flag)"
        }
    }
}
