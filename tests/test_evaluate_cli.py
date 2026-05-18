import io
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tarteel_realtime.evaluate import (
    load_cases_from_jsonl,
    main,
    parse_quran_ref,
)
from tarteel_realtime.alignment import AlignmentStatus
from tarteel_realtime.locator import LocatorStatus
from tarteel_realtime.quran import QuranRef


SAMPLE_TANZIL_TEXT = "\n".join([
    "113|1|قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
])


class EvaluateCliTests(unittest.TestCase):
    def test_parses_quran_refs(self):
        self.assertEqual(parse_quran_ref("114:2"), QuranRef(surah=114, ayah=2))
        self.assertEqual(parse_quran_ref("114:2:1"), QuranRef(surah=114, ayah=2, word_index=1))
        self.assertIsNone(parse_quran_ref(None))

    def test_loads_cases_from_jsonl_fixture(self):
        with TemporaryDirectory() as directory:
            fixture_path = Path(directory) / "cases.jsonl"
            fixture_path.write_text(
                json.dumps({
                    "case_id": "correct-nas-2",
                    "transcript": "مَلِكِ النَّاسِ",
                    "expected_locator_status": "locked",
                    "expected_locator_start_ref": "114:2:1",
                    "alignment_start_ref": "114:2:1",
                    "expected_alignment_status": "correct",
                }, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )

            cases = load_cases_from_jsonl(fixture_path)

        self.assertEqual(len(cases), 1)
        self.assertEqual(cases[0].case_id, "correct-nas-2")
        self.assertEqual(cases[0].expected_locator_status, LocatorStatus.LOCKED)
        self.assertEqual(cases[0].expected_locator_start_ref, QuranRef(surah=114, ayah=2, word_index=1))
        self.assertEqual(cases[0].expected_alignment_status, AlignmentStatus.CORRECT)

    def test_cli_prints_metrics_for_fixture(self):
        with TemporaryDirectory() as directory:
            directory_path = Path(directory)
            tanzil_path = directory_path / "quran-simple-clean.txt"
            fixture_path = directory_path / "juz-amma-smoke.jsonl"
            tanzil_path.write_text(SAMPLE_TANZIL_TEXT, encoding="utf-8")
            fixture_path.write_text(
                "\n".join([
                    json.dumps({
                        "case_id": "correct-nas-2",
                        "transcript": "مَلِكِ النَّاسِ",
                        "expected_locator_status": "locked",
                        "expected_locator_start_ref": "114:2:1",
                        "alignment_start_ref": "114:2:1",
                        "expected_alignment_status": "correct",
                    }, ensure_ascii=False),
                    json.dumps({
                        "case_id": "seeded-wrong-final-word",
                        "transcript": "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
                        "alignment_start_ref": "114:1:1",
                        "expected_alignment_status": "wrong",
                    }, ensure_ascii=False),
                ]),
                encoding="utf-8",
            )
            output = io.StringIO()

            exit_code = main([
                str(fixture_path),
                "--tanzil-path",
                str(tanzil_path),
                "--minimum-lock-words",
                "2",
            ], stdout=output)

        self.assertEqual(exit_code, 0)
        self.assertIn("total_cases: 2", output.getvalue())
        self.assertIn("locator_accuracy: 1.000", output.getvalue())
        self.assertIn("alignment_accuracy: 1.000", output.getvalue())
        self.assertIn("wrong_detection_rate: 1.000", output.getvalue())

    def test_cli_can_scope_full_tanzil_file_to_mvp_surahs(self):
        with TemporaryDirectory() as directory:
            directory_path = Path(directory)
            tanzil_path = directory_path / "quran-simple-clean.txt"
            fixture_path = directory_path / "mvp-only.jsonl"
            tanzil_path.write_text(
                "\n".join([
                    "2|1|الم",
                    "114|2|مَلِكِ النَّاسِ",
                ]),
                encoding="utf-8",
            )
            fixture_path.write_text(
                json.dumps({
                    "case_id": "mvp-nas-2",
                    "transcript": "مَلِكِ النَّاسِ",
                    "expected_locator_status": "locked",
                    "expected_locator_start_ref": "114:2:1",
                }, ensure_ascii=False),
                encoding="utf-8",
            )
            output = io.StringIO()

            exit_code = main([
                str(fixture_path),
                "--tanzil-path",
                str(tanzil_path),
                "--minimum-lock-words",
                "2",
                "--mvp-scope",
            ], stdout=output)

        self.assertEqual(exit_code, 0)
        self.assertIn("locator_accuracy: 1.000", output.getvalue())

    def test_repository_smoke_fixture_reports_expected_metrics(self):
        output = io.StringIO()

        exit_code = main([
            "fixtures/evaluation/juz-amma-smoke.jsonl",
            "--tanzil-path",
            "fixtures/quran/sample-tanzil.txt",
            "--minimum-lock-words",
            "2",
            "--mvp-scope",
        ], stdout=output)

        self.assertEqual(exit_code, 0)
        self.assertIn("total_cases: 3", output.getvalue())
        self.assertIn("locator_accuracy: 1.000", output.getvalue())
        self.assertIn("alignment_accuracy: 1.000", output.getvalue())
        self.assertIn("wrong_detection_rate: 1.000", output.getvalue())

    def test_repository_surah_102_fixture_reports_expected_metrics(self):
        output = io.StringIO()

        exit_code = main([
            "fixtures/evaluation/surah-102-smoke.jsonl",
            "--tanzil-path",
            "fixtures/quran/sample-tanzil.txt",
            "--minimum-lock-words",
            "2",
            "--mvp-scope",
        ], stdout=output)

        self.assertEqual(exit_code, 0)
        self.assertIn("total_cases: 3", output.getvalue())
        self.assertIn("locator_accuracy: 1.000", output.getvalue())
        self.assertIn("alignment_accuracy: 1.000", output.getvalue())
        self.assertIn("wrong_detection_rate: 1.000", output.getvalue())


if __name__ == "__main__":
    unittest.main()
