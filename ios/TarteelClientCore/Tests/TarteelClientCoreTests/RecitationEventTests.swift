import Foundation
import Testing
@testable import TarteelClientCore

struct RecitationEventTests {
    @Test func decodesWrongEventFromBackendPayload() throws {
        let data = Data("""
        {
          "type": "wrong",
          "transcript": "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
          "confidence": 1.0,
          "chunk_sequence": 1,
          "reason": "word_mismatch",
          "candidate_refs": [],
          "ayah_ref": null,
          "start_ref": null,
          "next_expected_ref": null,
          "consumed_words": 3,
          "expected_ref": "114:1:4",
          "expected_word": "النَّاسِ",
          "recognized_word": "الْفَلَقِ"
        }
        """.utf8)

        let event = try JSONDecoder().decode(RecitationEvent.self, from: data)

        #expect(event.type == .wrong)
        #expect(event.chunkSequence == 1)
        #expect(event.expectedRef == "114:1:4")
        #expect(event.expectedWord == "النَّاسِ")
        #expect(event.recognizedWord == "الْفَلَقِ")
        #expect(event.isBlockingCorrection)
    }

    @Test func encodesAudioChunkPayloadForBackendTransport() throws {
        let payload = AudioChunkPayload(
            sequenceNumber: 7,
            pcm: Data([0x00, 0x01, 0xff]),
            sampleRateHz: 16_000
        )

        let data = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["sequence_number"] as? Int == 7)
        #expect(json["pcm_base64"] as? String == "AAH/")
        #expect(json["sample_rate_hz"] as? Int == 16_000)
    }
}
