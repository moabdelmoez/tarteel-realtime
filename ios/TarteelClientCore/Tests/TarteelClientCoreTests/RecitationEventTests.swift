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
          "ayah_text": null,
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

    @Test func decodesCanonicalAyahTextFromBackendPayload() throws {
        let data = Data("""
        {
          "type": "locked",
          "transcript": "raw asr noise",
          "confidence": 0.8,
          "chunk_sequence": 4,
          "reason": "tolerant_match",
          "candidate_refs": [],
          "ayah_text": "مَلِكِ النَّاسِ",
          "ayah_ref": "114:2",
          "start_ref": "114:2:1",
          "next_expected_ref": null,
          "consumed_words": 2,
          "expected_ref": null,
          "expected_word": null,
          "recognized_word": null
        }
        """.utf8)

        let event = try JSONDecoder().decode(RecitationEvent.self, from: data)

        #expect(event.ayahRef == "114:2")
        #expect(event.ayahText == "مَلِكِ النَّاسِ")
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

    @Test func encodesVoiceActivityMetadataForBackendTransport() throws {
        let payload = AudioChunkPayload(
            sequenceNumber: 8,
            pcm: Data([0x00, 0x01]),
            sampleRateHz: 16_000,
            voiceActivity: VoiceActivityPayload(
                probability: 0.82,
                isSpeechActive: true,
                event: .speechStart
            )
        )

        let data = try JSONEncoder().encode(payload)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let voiceActivity = try #require(json["voice_activity"] as? [String: Any])

        #expect(voiceActivity["probability"] as? Double == 0.82)
        #expect(voiceActivity["is_speech_active"] as? Bool == true)
        #expect(voiceActivity["event"] as? String == "speech_start")
    }

    @Test func decodesLiveKitRecitationTokenResponse() throws {
        let data = Data("""
        {
          "url": "ws://127.0.0.1:7880",
          "room": "tarteel-local-recitation",
          "identity": "ios-simulator",
          "role": "client",
          "token": "signed-token"
        }
        """.utf8)

        let token = try JSONDecoder().decode(LiveKitRecitationToken.self, from: data)

        #expect(token.url == "ws://127.0.0.1:7880")
        #expect(token.room == "tarteel-local-recitation")
        #expect(token.identity == "ios-simulator")
        #expect(token.role == "client")
        #expect(token.token == "signed-token")
    }
}
