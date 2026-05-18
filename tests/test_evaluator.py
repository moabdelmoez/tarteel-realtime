import unittest

from tarteel_realtime.alignment import AlignmentStatus
from tarteel_realtime.evaluator import EvaluationCase, OfflineEvaluator
from tarteel_realtime.locator import LocatorStatus
from tarteel_realtime.quran import QuranCorpus, QuranRef


SAMPLE_TANZIL_LINES = [
    "113|1|قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]


class OfflineEvaluatorTests(unittest.TestCase):
    def setUp(self):
        corpus = QuranCorpus.from_tanzil_lines(SAMPLE_TANZIL_LINES)
        self.evaluator = OfflineEvaluator(corpus, minimum_lock_words=2)

    def test_evaluates_locator_and_alignment_expectations_for_one_case(self):
        report = self.evaluator.evaluate_cases([
            EvaluationCase(
                case_id="correct-nas-2",
                transcript="مَلِكِ النَّاسِ",
                expected_locator_status=LocatorStatus.LOCKED,
                expected_locator_start_ref=QuranRef(surah=114, ayah=2, word_index=1),
                alignment_start_ref=QuranRef(surah=114, ayah=2, word_index=1),
                expected_alignment_status=AlignmentStatus.CORRECT,
            )
        ])

        result = report.results[0]
        self.assertTrue(result.passed)
        self.assertEqual(result.locator_status, LocatorStatus.LOCKED)
        self.assertEqual(result.located_start_ref, QuranRef(surah=114, ayah=2, word_index=1))
        self.assertEqual(result.alignment_status, AlignmentStatus.CORRECT)
        self.assertEqual(report.metrics.total_cases, 1)
        self.assertEqual(report.metrics.locator_accuracy, 1.0)
        self.assertEqual(report.metrics.alignment_accuracy, 1.0)

    def test_reports_aggregate_metrics_for_locator_and_seeded_mistakes(self):
        report = self.evaluator.evaluate_cases([
            EvaluationCase(
                case_id="correct-nas-2",
                transcript="مَلِكِ النَّاسِ",
                expected_locator_status=LocatorStatus.LOCKED,
                expected_locator_start_ref=QuranRef(surah=114, ayah=2, word_index=1),
                alignment_start_ref=QuranRef(surah=114, ayah=2, word_index=1),
                expected_alignment_status=AlignmentStatus.CORRECT,
            ),
            EvaluationCase(
                case_id="seeded-wrong-final-word",
                transcript="قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
                alignment_start_ref=QuranRef(surah=114, ayah=1, word_index=1),
                expected_alignment_status=AlignmentStatus.WRONG,
            ),
            EvaluationCase(
                case_id="ambiguous-shared-start",
                transcript="قُلْ أَعُوذُ بِرَبِّ",
                expected_locator_status=LocatorStatus.AMBIGUOUS,
            ),
        ])

        self.assertTrue(all(result.passed for result in report.results))
        self.assertEqual(report.metrics.total_cases, 3)
        self.assertEqual(report.metrics.locator_cases, 2)
        self.assertEqual(report.metrics.locator_correct, 2)
        self.assertEqual(report.metrics.alignment_cases, 2)
        self.assertEqual(report.metrics.alignment_correct, 2)
        self.assertEqual(report.metrics.seeded_wrong_cases, 1)
        self.assertEqual(report.metrics.seeded_wrong_detected, 1)
        self.assertEqual(report.metrics.wrong_detection_rate, 1.0)

    def test_marks_case_failed_when_expected_alignment_status_is_not_met(self):
        report = self.evaluator.evaluate_cases([
            EvaluationCase(
                case_id="missed-mistake-expectation",
                transcript="مَلِكِ النَّاسِ",
                alignment_start_ref=QuranRef(surah=114, ayah=2, word_index=1),
                expected_alignment_status=AlignmentStatus.WRONG,
            )
        ])

        result = report.results[0]
        self.assertFalse(result.passed)
        self.assertEqual(result.alignment_status, AlignmentStatus.CORRECT)
        self.assertEqual(report.metrics.alignment_accuracy, 0.0)


if __name__ == "__main__":
    unittest.main()
