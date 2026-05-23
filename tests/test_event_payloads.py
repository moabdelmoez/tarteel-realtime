import unittest

from tarteel_realtime.event_payloads import session_event_to_payload
from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.session_events import SessionEvent, SessionEventType


class SessionEventPayloadTests(unittest.TestCase):
    def test_encodes_session_event_wire_payload_with_canonical_ayah_text(self):
        corpus = QuranCorpus.from_tanzil_lines([
            "114|2|مَلِكِ النَّاسِ",
        ])
        event = SessionEvent(
            type=SessionEventType.LOCKED,
            transcript="مَلِكِ",
            confidence=0.9,
            chunk_sequence=7,
            reason="unique_match",
            ayah_ref=QuranRef(surah=114, ayah=2),
            start_ref=QuranRef(surah=114, ayah=2, word_index=1),
            next_expected_ref=QuranRef(surah=114, ayah=2, word_index=2),
            consumed_words=1,
        )

        payload = session_event_to_payload(
            event,
            corpus=corpus,
        )

        self.assertEqual(payload["type"], "locked")
        self.assertNotIn("session_id", payload)
        self.assertEqual(payload["ayah_text"], "مَلِكِ النَّاسِ")
        self.assertEqual(payload["ayah_ref"], "114:2")
        self.assertEqual(payload["start_ref"], "114:2:1")
        self.assertEqual(payload["next_expected_ref"], "114:2:2")
        self.assertEqual(payload["consumed_words"], 1)


if __name__ == "__main__":
    unittest.main()
