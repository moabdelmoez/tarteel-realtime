import Foundation

public enum CoreMLArabicTextNormalizer {
    public static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            guard scalar.value != 0x0640 else { continue }
            guard scalar.properties.generalCategory != .nonspacingMark else { continue }
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar) {
                scalars.append(UnicodeScalar(0x20)!)
                continue
            }

            switch scalar {
            case "\u{0671}", "\u{0622}", "\u{0623}", "\u{0625}":
                scalars.append("\u{0627}")
            case "\u{0649}":
                scalars.append("\u{064A}")
            case "\u{0624}":
                scalars.append("\u{0648}")
            case "\u{0626}":
                scalars.append("\u{064A}")
            case "\u{0629}":
                scalars.append("\u{0647}")
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public enum CoreMLFastConformerFixtureManifestError: LocalizedError, Equatable {
    case duplicateAudioFile(String)
    case missingEntry(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateAudioFile(let audioFile):
            return "Duplicate fixture manifest entry for \(audioFile)."
        case .missingEntry(let audioFile):
            return "Fixture manifest has no expected text for \(audioFile)."
        }
    }
}

public struct CoreMLFastConformerFixtureExpectation: Codable, Equatable, Sendable {
    public let audioFile: String
    public let ayahRef: String
    public let expectedText: String

    public init(audioFile: String, ayahRef: String, expectedText: String) {
        self.audioFile = audioFile
        self.ayahRef = ayahRef
        self.expectedText = expectedText
    }

    private enum CodingKeys: String, CodingKey {
        case audioFile = "audio_file"
        case ayahRef = "ayah_ref"
        case expectedText = "expected_text"
    }
}

public struct CoreMLFastConformerFixtureManifest: Equatable, Sendable {
    public let entries: [CoreMLFastConformerFixtureExpectation]

    public init(entries: [CoreMLFastConformerFixtureExpectation]) {
        self.entries = entries
    }

    public static func load(from url: URL) throws -> CoreMLFastConformerFixtureManifest {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ManifestFile.self, from: data)
        return CoreMLFastConformerFixtureManifest(entries: file.fixtures)
    }

    public func expectation(forAudioPath audioPath: String) throws -> CoreMLFastConformerFixtureExpectation {
        let audioFile = URL(fileURLWithPath: audioPath).lastPathComponent
        let matches = entries.filter { $0.audioFile == audioFile }
        guard matches.count <= 1 else {
            throw CoreMLFastConformerFixtureManifestError.duplicateAudioFile(audioFile)
        }
        guard let expectation = matches.first else {
            throw CoreMLFastConformerFixtureManifestError.missingEntry(audioFile)
        }
        return expectation
    }

    private struct ManifestFile: Codable {
        let fixtures: [CoreMLFastConformerFixtureExpectation]
    }
}

public struct CoreMLFastConformerFixtureSubstitution: Codable, Equatable, Sendable {
    public let expectedWord: String
    public let actualWord: String

    public init(expectedWord: String, actualWord: String) {
        self.expectedWord = expectedWord
        self.actualWord = actualWord
    }

    private enum CodingKeys: String, CodingKey {
        case expectedWord = "expected_word"
        case actualWord = "actual_word"
    }
}

public struct CoreMLFastConformerFixtureScore: Codable, Equatable, Sendable {
    public let normalizedExpectedText: String
    public let normalizedActualText: String
    public let expectedWordCount: Int
    public let actualWordCount: Int
    public let wordEditDistance: Int
    public let wordErrorRate: Double
    public let wordMatchScore: Double
    public let characterEditDistance: Int
    public let characterErrorRate: Double
    public let missingWords: [String]
    public let extraWords: [String]
    public let substitutions: [CoreMLFastConformerFixtureSubstitution]

    public static func score(
        expectedText: String,
        actualText: String
    ) -> CoreMLFastConformerFixtureScore {
        let normalizedExpected = CoreMLArabicTextNormalizer.normalize(expectedText)
        let normalizedActual = CoreMLArabicTextNormalizer.normalize(actualText)
        let expectedWords = normalizedExpected.split(separator: " ").map(String.init)
        let actualWords = normalizedActual.split(separator: " ").map(String.init)
        let alignment = align(expected: expectedWords, actual: actualWords)
        let characterDistance = editDistance(
            Array(normalizedExpected),
            Array(normalizedActual)
        )
        let wordErrorRate = expectedWords.isEmpty
            ? (actualWords.isEmpty ? 0.0 : 1.0)
            : Double(alignment.distance) / Double(expectedWords.count)
        let characterErrorRate = normalizedExpected.isEmpty
            ? (normalizedActual.isEmpty ? 0.0 : 1.0)
            : Double(characterDistance) / Double(normalizedExpected.count)

        return CoreMLFastConformerFixtureScore(
            normalizedExpectedText: normalizedExpected,
            normalizedActualText: normalizedActual,
            expectedWordCount: expectedWords.count,
            actualWordCount: actualWords.count,
            wordEditDistance: alignment.distance,
            wordErrorRate: wordErrorRate,
            wordMatchScore: max(0.0, 1.0 - wordErrorRate),
            characterEditDistance: characterDistance,
            characterErrorRate: characterErrorRate,
            missingWords: alignment.missingWords,
            extraWords: alignment.extraWords,
            substitutions: alignment.substitutions
        )
    }

    private static func align(
        expected: [String],
        actual: [String]
    ) -> (
        distance: Int,
        missingWords: [String],
        extraWords: [String],
        substitutions: [CoreMLFastConformerFixtureSubstitution]
    ) {
        let dp = editDistanceMatrix(expected, actual)
        var i = expected.count
        var j = actual.count
        var missingWords: [String] = []
        var extraWords: [String] = []
        var substitutions: [CoreMLFastConformerFixtureSubstitution] = []

        while i > 0 || j > 0 {
            if i > 0, j > 0, expected[i - 1] == actual[j - 1], dp[i][j] == dp[i - 1][j - 1] {
                i -= 1
                j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                substitutions.append(
                    CoreMLFastConformerFixtureSubstitution(
                        expectedWord: expected[i - 1],
                        actualWord: actual[j - 1]
                    )
                )
                i -= 1
                j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                missingWords.append(expected[i - 1])
                i -= 1
            } else if j > 0 {
                extraWords.append(actual[j - 1])
                j -= 1
            }
        }

        return (
            dp[expected.count][actual.count],
            Array(missingWords.reversed()),
            Array(extraWords.reversed()),
            Array(substitutions.reversed())
        )
    }

    private static func editDistance<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
        editDistanceMatrix(lhs, rhs)[lhs.count][rhs.count]
    }

    private static func editDistanceMatrix<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> [[Int]] {
        var dp = Array(
            repeating: Array(repeating: 0, count: rhs.count + 1),
            count: lhs.count + 1
        )
        for i in 0...lhs.count {
            dp[i][0] = i
        }
        for j in 0...rhs.count {
            dp[0][j] = j
        }
        guard !lhs.isEmpty, !rhs.isEmpty else { return dp }
        for i in 1...lhs.count {
            for j in 1...rhs.count {
                if lhs[i - 1] == rhs[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = min(
                        dp[i - 1][j] + 1,
                        dp[i][j - 1] + 1,
                        dp[i - 1][j - 1] + 1
                    )
                }
            }
        }
        return dp
    }
}
