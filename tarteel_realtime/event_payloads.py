from __future__ import annotations

from typing import Any

from tarteel_realtime.quran import QuranCorpus, QuranRef
from tarteel_realtime.session_events import SessionEvent


def session_event_to_payload(
    event: SessionEvent,
    *,
    corpus: QuranCorpus,
) -> dict[str, Any]:
    return {
        "type": event.type.value,
        "transcript": event.transcript,
        "confidence": event.confidence,
        "chunk_sequence": event.chunk_sequence,
        "reason": event.reason,
        "candidate_refs": [_ref_to_string(ref) for ref in event.candidate_refs],
        "ayah_text": _ayah_text_for_event(event, corpus=corpus),
        "ayah_ref": _ref_to_string(event.ayah_ref),
        "start_ref": _ref_to_string(event.start_ref),
        "next_expected_ref": _ref_to_string(event.next_expected_ref),
        "consumed_words": event.consumed_words,
        "expected_ref": _ref_to_string(event.expected_ref),
        "expected_word": event.expected_word,
        "recognized_word": event.recognized_word,
    }


def _ayah_text_for_event(event: SessionEvent, *, corpus: QuranCorpus) -> str | None:
    ref = event.ayah_ref or event.start_ref
    if ref is None:
        return None
    return corpus.get_ayah(ref).text


def _ref_to_string(ref: QuranRef | None) -> str | None:
    if ref is None:
        return None
    return str(ref)
