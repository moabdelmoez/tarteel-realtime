from __future__ import annotations

from dataclasses import dataclass

from tarteel_realtime.quran import QuranCorpus, QuranRef


@dataclass(frozen=True)
class RecitationScope:
    allowed_ayah_refs: tuple[QuranRef, ...]

    def __post_init__(self) -> None:
        if not self.allowed_ayah_refs:
            raise ValueError("recitation scope must include at least one ayah")

    def contains(self, ref: QuranRef) -> bool:
        return _ayah_ref(ref) in self.allowed_ayah_refs

    def filter_ayah_refs(self, refs: tuple[QuranRef, ...]) -> tuple[QuranRef, ...]:
        return tuple(ref for ref in refs if self.contains(ref))


def parse_recitation_scope(
    raw_scope: str | None,
    *,
    corpus: QuranCorpus,
) -> RecitationScope | None:
    if raw_scope is None:
        return None

    scope_text = raw_scope.strip()
    if not scope_text:
        return None

    if scope_text.isdecimal():
        return _scope_for_surah(int(scope_text), corpus=corpus)

    if "-" in scope_text:
        start_text, end_text = _split_range(scope_text)
        start_ref = _parse_ayah_ref(start_text)
        end_ref = _parse_ayah_ref(end_text, default_surah=start_ref.surah)
        return _scope_for_range(start_ref, end_ref, corpus=corpus)

    ref = _parse_ayah_ref(scope_text)
    return _scope_for_range(ref, ref, corpus=corpus)


def _scope_for_surah(surah: int, *, corpus: QuranCorpus) -> RecitationScope:
    refs = tuple(
        ayah.ref
        for ayah in corpus.ayahs()
        if ayah.ref.surah == surah
    )
    if not refs:
        raise ValueError(f"unknown recitation scope: {surah}")
    return RecitationScope(refs)


def _scope_for_range(
    start_ref: QuranRef,
    end_ref: QuranRef,
    *,
    corpus: QuranCorpus,
) -> RecitationScope:
    ordered_refs = tuple(ayah.ref for ayah in corpus.ayahs())
    try:
        start_index = ordered_refs.index(start_ref)
        end_index = ordered_refs.index(end_ref)
    except ValueError as exc:
        raise ValueError(f"unknown recitation scope: {start_ref}-{end_ref}") from exc

    if start_index > end_index:
        raise ValueError(f"invalid recitation scope range: {start_ref}-{end_ref}")

    return RecitationScope(ordered_refs[start_index : end_index + 1])


def _split_range(scope_text: str) -> tuple[str, str]:
    parts = scope_text.split("-", maxsplit=1)
    if len(parts) != 2 or not parts[0].strip() or not parts[1].strip():
        raise ValueError(f"invalid recitation scope: {scope_text}")
    return parts[0].strip(), parts[1].strip()


def _parse_ayah_ref(ref_text: str, *, default_surah: int | None = None) -> QuranRef:
    parts = [part.strip() for part in ref_text.split(":")]
    if len(parts) == 1 and default_surah is not None and parts[0].isdecimal():
        return QuranRef(surah=default_surah, ayah=int(parts[0]))
    if len(parts) != 2 or not all(part.isdecimal() for part in parts):
        raise ValueError(f"invalid recitation scope ref: {ref_text}")
    return QuranRef(surah=int(parts[0]), ayah=int(parts[1]))


def _ayah_ref(ref: QuranRef) -> QuranRef:
    return QuranRef(surah=ref.surah, ayah=ref.ayah)
