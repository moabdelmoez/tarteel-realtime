from __future__ import annotations

from dataclasses import dataclass

from tarteel_realtime.alignment import AlignmentStatus, QuranAligner
from tarteel_realtime.locator import LocatorStatus, QuranLocator
from tarteel_realtime.quran import QuranCorpus, QuranRef


@dataclass(frozen=True)
class EvaluationCase:
    case_id: str
    transcript: str
    expected_locator_status: LocatorStatus | None = None
    expected_locator_start_ref: QuranRef | None = None
    alignment_start_ref: QuranRef | None = None
    expected_alignment_status: AlignmentStatus | None = None


@dataclass(frozen=True)
class EvaluationResult:
    case_id: str
    passed: bool
    locator_status: LocatorStatus
    located_start_ref: QuranRef | None
    locator_passed: bool | None
    alignment_status: AlignmentStatus | None
    alignment_passed: bool | None


@dataclass(frozen=True)
class EvaluationMetrics:
    total_cases: int
    locator_cases: int
    locator_correct: int
    alignment_cases: int
    alignment_correct: int
    seeded_wrong_cases: int
    seeded_wrong_detected: int

    @property
    def locator_accuracy(self) -> float:
        if self.locator_cases == 0:
            return 0.0
        return self.locator_correct / self.locator_cases

    @property
    def alignment_accuracy(self) -> float:
        if self.alignment_cases == 0:
            return 0.0
        return self.alignment_correct / self.alignment_cases

    @property
    def wrong_detection_rate(self) -> float:
        if self.seeded_wrong_cases == 0:
            return 0.0
        return self.seeded_wrong_detected / self.seeded_wrong_cases


@dataclass(frozen=True)
class EvaluationReport:
    results: tuple[EvaluationResult, ...]
    metrics: EvaluationMetrics


class OfflineEvaluator:
    def __init__(self, corpus: QuranCorpus, minimum_lock_words: int = 3) -> None:
        self._locator = QuranLocator(corpus, minimum_lock_words=minimum_lock_words)
        self._aligner = QuranAligner(corpus)

    def evaluate_cases(self, cases: list[EvaluationCase]) -> EvaluationReport:
        results = tuple(self._evaluate_case(case) for case in cases)
        return EvaluationReport(
            results=results,
            metrics=self._build_metrics(cases, results),
        )

    def _evaluate_case(self, case: EvaluationCase) -> EvaluationResult:
        locator_decision = self._locator.locate(case.transcript)
        located_start_ref = (
            locator_decision.best.start_ref
            if locator_decision.best is not None
            else None
        )
        locator_passed = self._locator_passed(
            expected_status=case.expected_locator_status,
            expected_start_ref=case.expected_locator_start_ref,
            actual_status=locator_decision.status,
            actual_start_ref=located_start_ref,
        )

        alignment_status = None
        alignment_passed = None
        if case.alignment_start_ref is not None:
            alignment_decision = self._aligner.evaluate_from(
                case.alignment_start_ref,
                case.transcript,
            )
            alignment_status = alignment_decision.status
            if case.expected_alignment_status is not None:
                alignment_passed = alignment_status == case.expected_alignment_status

        passed_checks = [
            check
            for check in (locator_passed, alignment_passed)
            if check is not None
        ]
        return EvaluationResult(
            case_id=case.case_id,
            passed=all(passed_checks),
            locator_status=locator_decision.status,
            located_start_ref=located_start_ref,
            locator_passed=locator_passed,
            alignment_status=alignment_status,
            alignment_passed=alignment_passed,
        )

    def _locator_passed(
        self,
        *,
        expected_status: LocatorStatus | None,
        expected_start_ref: QuranRef | None,
        actual_status: LocatorStatus,
        actual_start_ref: QuranRef | None,
    ) -> bool | None:
        if expected_status is None and expected_start_ref is None:
            return None
        if expected_status is not None and actual_status != expected_status:
            return False
        if expected_start_ref is not None and actual_start_ref != expected_start_ref:
            return False
        return True

    def _build_metrics(
        self,
        cases: list[EvaluationCase],
        results: tuple[EvaluationResult, ...],
    ) -> EvaluationMetrics:
        locator_cases = 0
        locator_correct = 0
        alignment_cases = 0
        alignment_correct = 0
        seeded_wrong_cases = 0
        seeded_wrong_detected = 0

        for case, result in zip(cases, results, strict=True):
            if result.locator_passed is not None:
                locator_cases += 1
                if result.locator_passed:
                    locator_correct += 1

            if result.alignment_passed is not None:
                alignment_cases += 1
                if result.alignment_passed:
                    alignment_correct += 1

            if case.expected_alignment_status == AlignmentStatus.WRONG:
                seeded_wrong_cases += 1
                if result.alignment_status == AlignmentStatus.WRONG:
                    seeded_wrong_detected += 1

        return EvaluationMetrics(
            total_cases=len(cases),
            locator_cases=locator_cases,
            locator_correct=locator_correct,
            alignment_cases=alignment_cases,
            alignment_correct=alignment_correct,
            seeded_wrong_cases=seeded_wrong_cases,
            seeded_wrong_detected=seeded_wrong_detected,
        )
