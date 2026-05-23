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
    "102|1|بسم الله الرحمن الرحيم ألهاكم التكاثر",
    "102|2|حتى زرتم المقابر",
    "102|3|كلا سوف تعلمون",
    "102|4|ثم كلا سوف تعلمون",
    "102|5|كلا لو تعلمون علم اليقين",
    "102|6|لترون الجحيم",
    "102|7|ثم لترونها عين اليقين",
    "102|8|ثم لتسألن يومئذ عن النعيم",
    "98|1|بسم الله الرحمن الرحيم لم يكن الذين كفروا من أهل الكتاب والمشركين منفكين حتى تأتيهم البينة",
    "98|2|رسول من الله يتلو صحفا مطهرة",
    "98|3|فيها كتب قيمة",
    "98|4|وما تفرق الذين أوتوا الكتاب إلا من بعد ما جاءتهم البينة",
    "98|5|وما أمروا إلا ليعبدوا الله مخلصين له الدين حنفاء ويقيموا الصلاة ويؤتوا الزكاة وذلك دين القيمة",
    "98|6|إن الذين كفروا من أهل الكتاب والمشركين في نار جهنم خالدين فيها أولئك هم شر البرية",
    "98|7|إن الذين آمنوا وعملوا الصالحات أولئك هم خير البرية",
    "98|8|جزاؤهم عند ربهم جنات عدن تجري من تحتها الأنهار خالدين فيها أبدا رضي الله عنهم ورضوا عنه ذلك لمن خشي ربه",
])

JUZ_AMMA_SMOKE_CASES = [
    {
        "case_id": "correct-nas-2",
        "transcript": "مَلِكِ النَّاسِ",
        "expected_locator_status": "locked",
        "expected_locator_start_ref": "114:2:1",
        "alignment_start_ref": "114:2:1",
        "expected_alignment_status": "correct",
    },
    {
        "case_id": "seeded-wrong-final-word",
        "transcript": "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
        "alignment_start_ref": "114:1:1",
        "expected_alignment_status": "wrong",
    },
    {
        "case_id": "ambiguous-shared-start",
        "transcript": "قُلْ أَعُوذُ بِرَبِّ",
        "expected_locator_status": "ambiguous",
    },
]

SURAH_102_SMOKE_CASES = [
    {
        "case_id": "surah-102-ayah-1-clean-audio-start",
        "transcript": "ألهاكم التكاثر",
        "expected_locator_status": "locked",
        "expected_locator_start_ref": "102:1:5",
        "alignment_start_ref": "102:1:5",
        "expected_alignment_status": "correct",
    },
    {
        "case_id": "surah-102-ayah-8-clean-audio",
        "transcript": "ثم لتسألن يومئذ عن النعيم",
        "expected_locator_status": "locked",
        "expected_locator_start_ref": "102:8:1",
        "alignment_start_ref": "102:8:1",
        "expected_alignment_status": "correct",
    },
    {
        "case_id": "surah-102-seeded-wrong-word",
        "transcript": "حتى زرتم الجحيم",
        "alignment_start_ref": "102:2:1",
        "expected_alignment_status": "wrong",
    },
]

SURAH_98_SMOKE_CASES = [
    {
        "case_id": "surah-98-ayah-1-clipped-audio-fragment",
        "transcript": "من أهل الكتاب والمشركين منفكين حتى تأتيهم البينة",
        "expected_locator_status": "locked",
        "expected_locator_start_ref": "98:1:9",
        "alignment_start_ref": "98:1:9",
        "expected_alignment_status": "correct",
    },
    {
        "case_id": "surah-98-ayah-2-clean-audio",
        "transcript": "رسول من الله يتلو صحفا مطهرة",
        "expected_locator_status": "locked",
        "expected_locator_start_ref": "98:2:1",
        "alignment_start_ref": "98:2:1",
        "expected_alignment_status": "correct",
    },
    {
        "case_id": "surah-98-ayah-8-long-tail",
        "transcript": "جنات عدن تجري من تحتها الأنهار خالدين فيها أبدا رضي الله عنهم ورضوا عنه ذلك لمن خشي ربه",
        "expected_locator_status": "locked",
        "expected_locator_start_ref": "98:8:4",
        "alignment_start_ref": "98:8:4",
        "expected_alignment_status": "correct",
    },
    {
        "case_id": "surah-98-seeded-wrong-word",
        "transcript": "رسول من الله يتلو نارا مطهرة",
        "alignment_start_ref": "98:2:1",
        "expected_alignment_status": "wrong",
    },
]


class EvaluateCliTests(unittest.TestCase):
    def assert_smoke_cases_report_expected_metrics(self, cases, expected_total):
        with TemporaryDirectory() as directory:
            directory_path = Path(directory)
            tanzil_path = directory_path / "quran-simple-clean.txt"
            fixture_path = directory_path / "smoke.jsonl"
            tanzil_path.write_text(SAMPLE_TANZIL_TEXT, encoding="utf-8")
            fixture_path.write_text(
                "\n".join(json.dumps(case, ensure_ascii=False) for case in cases),
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
        self.assertIn(f"total_cases: {expected_total}", output.getvalue())
        self.assertIn("locator_accuracy: 1.000", output.getvalue())
        self.assertIn("alignment_accuracy: 1.000", output.getvalue())
        self.assertIn("wrong_detection_rate: 1.000", output.getvalue())

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

    def test_embedded_juz_amma_smoke_cases_report_expected_metrics(self):
        self.assert_smoke_cases_report_expected_metrics(JUZ_AMMA_SMOKE_CASES, expected_total=3)

    def test_embedded_surah_102_smoke_cases_report_expected_metrics(self):
        self.assert_smoke_cases_report_expected_metrics(SURAH_102_SMOKE_CASES, expected_total=3)

    def test_embedded_surah_98_smoke_cases_report_expected_metrics(self):
        self.assert_smoke_cases_report_expected_metrics(SURAH_98_SMOKE_CASES, expected_total=4)


if __name__ == "__main__":
    unittest.main()
