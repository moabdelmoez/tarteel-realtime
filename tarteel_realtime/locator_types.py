from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from tarteel_realtime.quran import QuranRef


class LocatorStatus(StrEnum):
    LOCKED = "locked"
    AMBIGUOUS = "ambiguous"
    NOT_FOUND = "not_found"


@dataclass(frozen=True)
class LocatorCandidate:
    ayah_ref: QuranRef
    start_ref: QuranRef
    matched_words: int
    score: float


@dataclass(frozen=True)
class LocatorDecision:
    status: LocatorStatus
    candidates: tuple[LocatorCandidate, ...] = ()
    reason: str | None = None

    @property
    def best(self) -> LocatorCandidate | None:
        if not self.candidates:
            return None
        return self.candidates[0]
