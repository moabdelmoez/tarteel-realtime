from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import TextIO

from tarteel_realtime.alignment import AlignmentStatus
from tarteel_realtime.evaluator import EvaluationCase, OfflineEvaluator
from tarteel_realtime.locator import LocatorStatus
from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.quran_data import DEFAULT_TANZIL_PATH
from tarteel_realtime.scope import mvp_corpus


def parse_quran_ref(value: str | None) -> QuranRef | None:
    if value is None:
        return None

    parts = value.split(":")
    if len(parts) not in (2, 3):
        raise ValueError(f"invalid Quran ref: {value}")

    surah = int(parts[0])
    ayah = int(parts[1])
    word_index = int(parts[2]) if len(parts) == 3 else None
    return QuranRef(surah=surah, ayah=ayah, word_index=word_index)


def load_cases_from_jsonl(path: str | Path) -> list[EvaluationCase]:
    fixture_path = Path(path)
    cases: list[EvaluationCase] = []

    for line_number, raw_line in enumerate(fixture_path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue

        try:
            payload = json.loads(line)
            cases.append(_case_from_payload(payload))
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise ValueError(f"invalid evaluation case at line {line_number}") from exc

    return cases


def main(argv: list[str] | None = None, stdout: TextIO | None = None) -> int:
    output = stdout if stdout is not None else sys.stdout
    parser = argparse.ArgumentParser(description="Run offline Quran recitation evaluation fixtures.")
    parser.add_argument("fixture_path")
    parser.add_argument("--tanzil-path", default=str(DEFAULT_TANZIL_PATH))
    parser.add_argument("--minimum-lock-words", type=int, default=3)
    parser.add_argument("--mvp-scope", action="store_true")
    args = parser.parse_args(argv)

    corpus = QuranCorpus.from_tanzil_file(args.tanzil_path)
    if args.mvp_scope:
        corpus = mvp_corpus(corpus)

    cases = load_cases_from_jsonl(args.fixture_path)
    report = OfflineEvaluator(
        corpus,
        minimum_lock_words=args.minimum_lock_words,
    ).evaluate_cases(cases)

    metrics = report.metrics
    print(f"total_cases: {metrics.total_cases}", file=output)
    print(f"locator_cases: {metrics.locator_cases}", file=output)
    print(f"locator_correct: {metrics.locator_correct}", file=output)
    print(f"locator_accuracy: {metrics.locator_accuracy:.3f}", file=output)
    print(f"alignment_cases: {metrics.alignment_cases}", file=output)
    print(f"alignment_correct: {metrics.alignment_correct}", file=output)
    print(f"alignment_accuracy: {metrics.alignment_accuracy:.3f}", file=output)
    print(f"seeded_wrong_cases: {metrics.seeded_wrong_cases}", file=output)
    print(f"seeded_wrong_detected: {metrics.seeded_wrong_detected}", file=output)
    print(f"wrong_detection_rate: {metrics.wrong_detection_rate:.3f}", file=output)
    return 0


def _case_from_payload(payload: dict) -> EvaluationCase:
    return EvaluationCase(
        case_id=payload["case_id"],
        transcript=payload["transcript"],
        expected_locator_status=_optional_locator_status(payload.get("expected_locator_status")),
        expected_locator_start_ref=parse_quran_ref(payload.get("expected_locator_start_ref")),
        alignment_start_ref=parse_quran_ref(payload.get("alignment_start_ref")),
        expected_alignment_status=_optional_alignment_status(payload.get("expected_alignment_status")),
    )


def _optional_locator_status(value: str | None) -> LocatorStatus | None:
    if value is None:
        return None
    return LocatorStatus(value)


def _optional_alignment_status(value: str | None) -> AlignmentStatus | None:
    if value is None:
        return None
    return AlignmentStatus(value)


if __name__ == "__main__":
    raise SystemExit(main())
