import unittest

from tarteel_realtime.locator import LocatorCandidate
from tarteel_realtime.quran import QuranRef
from tarteel_realtime.session_events import (
    SessionEventType,
    locked_event,
    ordered_guidance_event,
    out_of_order_event,
    progress_event,
    waiting_event,
)


class SessionEventFactoryTests(unittest.TestCase):
    def test_waiting_event_is_locating_before_lock_and_uncertain_after_lock(self):
        before_lock = waiting_event(
            transcript="",
            confidence=0.0,
            chunk_sequence=3,
            has_locked=False,
            next_expected_ref=None,
        )
        after_lock = waiting_event(
            transcript="",
            confidence=0.0,
            chunk_sequence=4,
            has_locked=True,
            next_expected_ref=QuranRef(surah=114, ayah=2, word_index=2),
        )

        self.assertEqual(before_lock.type, SessionEventType.LOCATING)
        self.assertEqual(before_lock.reason, "waiting_for_audio_buffer")
        self.assertIsNone(before_lock.next_expected_ref)
        self.assertEqual(after_lock.type, SessionEventType.UNCERTAIN)
        self.assertEqual(after_lock.reason, "waiting_for_audio_buffer")
        self.assertEqual(after_lock.next_expected_ref, QuranRef(surah=114, ayah=2, word_index=2))

    def test_locked_and_progress_events_expose_candidate_and_next_expected_refs(self):
        candidate = LocatorCandidate(
            ayah_ref=QuranRef(surah=102, ayah=3),
            start_ref=QuranRef(surah=102, ayah=3, word_index=1),
            matched_words=3,
            score=3.0,
        )

        locked = locked_event(
            transcript="كلا سوف تعلمون",
            confidence=0.9,
            chunk_sequence=7,
            reason="unique_match",
            candidate=candidate,
            next_expected_ref=QuranRef(surah=102, ayah=4, word_index=1),
            consumed_words=3,
        )
        progress = progress_event(
            transcript="ثم",
            confidence=0.8,
            chunk_sequence=8,
            next_expected_ref=QuranRef(surah=102, ayah=4, word_index=2),
            consumed_words=1,
            reason="tolerant_progression",
        )

        self.assertEqual(locked.type, SessionEventType.LOCKED)
        self.assertEqual(locked.ayah_ref, QuranRef(surah=102, ayah=3))
        self.assertEqual(locked.start_ref, QuranRef(surah=102, ayah=3, word_index=1))
        self.assertEqual(locked.next_expected_ref, QuranRef(surah=102, ayah=4, word_index=1))
        self.assertEqual(locked.consumed_words, 3)
        self.assertEqual(progress.type, SessionEventType.PROGRESS)
        self.assertEqual(progress.reason, "tolerant_progression")
        self.assertEqual(progress.next_expected_ref, QuranRef(surah=102, ayah=4, word_index=2))
        self.assertEqual(progress.consumed_words, 1)

    def test_ordered_guidance_and_out_of_order_events_share_expected_ref_shape(self):
        expected_ref = QuranRef(surah=102, ayah=7, word_index=1)

        guidance = ordered_guidance_event(
            transcript="ملك الناس",
            confidence=0.6,
            chunk_sequence=10,
            expected_start_ref=expected_ref,
        )
        wrong = out_of_order_event(
            transcript="ملك الناس",
            confidence=0.6,
            chunk_sequence=11,
            expected_ref=expected_ref,
            expected_word="ثم",
        )

        self.assertEqual(guidance.type, SessionEventType.UNCERTAIN)
        self.assertEqual(guidance.reason, "expected_ordered_progression")
        self.assertEqual(guidance.ayah_ref, QuranRef(surah=102, ayah=7))
        self.assertEqual(guidance.start_ref, expected_ref)
        self.assertEqual(guidance.next_expected_ref, expected_ref)
        self.assertEqual(wrong.type, SessionEventType.WRONG)
        self.assertEqual(wrong.reason, "out_of_order")
        self.assertEqual(wrong.expected_ref, expected_ref)
        self.assertEqual(wrong.expected_word, "ثم")


if __name__ == "__main__":
    unittest.main()
