import unittest

from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.recognition import RecognitionResult
from tarteel_realtime.session_events import SessionEventType
from tarteel_realtime.session_transitions import RecitationTransitionPolicy


SAMPLE_TANZIL_LINES = [
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


class RecitationTransitionPolicyTests(unittest.TestCase):
    def setUp(self):
        self.corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)

    def test_handles_initial_lock_without_audio_chunk_dependency(self):
        policy = RecitationTransitionPolicy(
            corpus=self.corpus,
            minimum_lock_words=1,
        )

        event = policy.handle_recognition(
            RecognitionResult(
                transcript="مَلِكِ",
                confidence=0.9,
                chunk_sequence=7,
            )
        )

        self.assertEqual(event.type, SessionEventType.LOCKED)
        self.assertEqual(event.chunk_sequence, 7)
        self.assertEqual(event.ayah_ref, QuranRef(surah=114, ayah=2))
        self.assertEqual(event.start_ref, QuranRef(surah=114, ayah=2, word_index=1))
        self.assertEqual(event.next_expected_ref, QuranRef(surah=114, ayah=2, word_index=2))

    def test_tracks_post_lock_progression_inside_transition_policy(self):
        policy = RecitationTransitionPolicy(
            corpus=self.corpus,
            minimum_lock_words=1,
        )

        policy.handle_recognition(
            RecognitionResult(transcript="مَلِكِ", confidence=0.9, chunk_sequence=0)
        )
        event = policy.handle_recognition(
            RecognitionResult(transcript="النَّاسِ", confidence=0.9, chunk_sequence=1)
        )

        self.assertEqual(event.type, SessionEventType.PROGRESS)
        self.assertEqual(event.consumed_words, 1)
        self.assertIsNone(event.next_expected_ref)

    def test_waiting_events_use_policy_lock_state(self):
        policy = RecitationTransitionPolicy(
            corpus=self.corpus,
            minimum_lock_words=1,
        )

        before_lock = policy.handle_recognition(
            RecognitionResult(transcript="", confidence=0.0, is_final=False, chunk_sequence=0)
        )
        policy.handle_recognition(
            RecognitionResult(transcript="مَلِكِ", confidence=0.9, chunk_sequence=1)
        )
        after_lock = policy.handle_recognition(
            RecognitionResult(transcript="", confidence=0.0, is_final=False, chunk_sequence=2)
        )

        self.assertEqual(before_lock.type, SessionEventType.LOCATING)
        self.assertEqual(before_lock.reason, "waiting_for_audio_buffer")
        self.assertEqual(after_lock.type, SessionEventType.UNCERTAIN)
        self.assertEqual(after_lock.reason, "waiting_for_audio_buffer")
        self.assertEqual(after_lock.next_expected_ref, QuranRef(surah=114, ayah=2, word_index=2))


if __name__ == "__main__":
    unittest.main()
