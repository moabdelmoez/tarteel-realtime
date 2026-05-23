import unittest

from tarteel_realtime.alignment import AlignmentDecision, AlignmentStatus
from tarteel_realtime.locator import LocatorCandidate
from tarteel_realtime.progression import RecitationProgression, ayah_ref
from tarteel_realtime.quran import QuranCorpus, QuranRef


SAMPLE_TANZIL_LINES = [
    "102|5|كلا لو تعلمون علم اليقين",
    "102|6|لترون الجحيم",
    "102|7|ثم لترونها عين اليقين",
    "102|8|ثم لتسألن يومئذ عن النعيم",
]


class RecitationProgressionTests(unittest.TestCase):
    def setUp(self):
        self.corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)

    def test_initial_lock_tracks_next_word_and_ordered_ayah_scope(self):
        progression = RecitationProgression(self.corpus)
        alignment = AlignmentDecision(
            status=AlignmentStatus.CORRECT,
            next_expected_ref=QuranRef(surah=102, ayah=5, word_index=3),
        )

        next_expected_ref = progression.mark_initial_lock(
            ayah_ref=QuranRef(surah=102, ayah=5),
            alignment_decision=alignment,
        )

        self.assertEqual(next_expected_ref, QuranRef(surah=102, ayah=5, word_index=3))
        self.assertEqual(progression.next_expected_ref, QuranRef(surah=102, ayah=5, word_index=3))
        self.assertEqual(progression.progress_anchor_ref, QuranRef(surah=102, ayah=5, word_index=3))
        self.assertEqual(
            progression.ordered_allowed_ayah_refs(),
            (
                QuranRef(surah=102, ayah=5),
                QuranRef(surah=102, ayah=6),
            ),
        )

    def test_full_ayah_match_anchors_ordered_progression_on_next_ayah(self):
        progression = RecitationProgression(self.corpus)
        candidate = LocatorCandidate(
            ayah_ref=QuranRef(surah=102, ayah=6),
            start_ref=QuranRef(surah=102, ayah=6, word_index=1),
            matched_words=2,
            score=2.0,
        )

        next_expected_ref = progression.mark_candidate_match(candidate)

        self.assertIsNone(next_expected_ref)
        self.assertIsNone(progression.next_expected_ref)
        self.assertEqual(progression.progress_anchor_ref, QuranRef(surah=102, ayah=7))
        self.assertEqual(
            progression.ordered_allowed_ayah_refs(),
            (QuranRef(surah=102, ayah=7),),
        )
        self.assertEqual(
            progression.expected_ordered_start_ref(),
            QuranRef(surah=102, ayah=7, word_index=1),
        )

    def test_ordered_misses_are_counted_and_reset_after_match(self):
        progression = RecitationProgression(self.corpus)

        self.assertEqual(progression.record_ordered_miss(), 1)
        self.assertEqual(progression.record_ordered_miss(), 2)

        progression.mark_candidate_match(
            LocatorCandidate(
                ayah_ref=QuranRef(surah=102, ayah=5),
                start_ref=QuranRef(surah=102, ayah=5, word_index=1),
                matched_words=2,
                score=2.0,
            )
        )

        self.assertEqual(progression.record_ordered_miss(), 1)

    def test_ayah_ref_strips_word_index(self):
        self.assertEqual(
            ayah_ref(QuranRef(surah=102, ayah=5, word_index=3)),
            QuranRef(surah=102, ayah=5),
        )


if __name__ == "__main__":
    unittest.main()
