from __future__ import annotations

from inspect import Parameter, signature
from typing import Any

from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recitation_scope import RecitationScope
from tarteel_realtime.recognition import AudioChunk, RecognitionResult, SpeechRecognizer
from tarteel_realtime.session_events import SessionEvent, SessionEventType
from tarteel_realtime.session_transitions import RecitationTransitionPolicy


class RecitationSession:
    def __init__(
        self,
        *,
        corpus: QuranCorpus,
        recognizer: SpeechRecognizer,
        minimum_lock_words: int = 3,
        recitation_scope: RecitationScope | None = None,
    ) -> None:
        self._recognizer = recognizer
        self._transitions = RecitationTransitionPolicy(
            corpus=corpus,
            minimum_lock_words=minimum_lock_words,
            recitation_scope=recitation_scope,
        )

    def handle_chunk(self, chunk: AudioChunk) -> SessionEvent:
        recognition = self._recognizer.recognize(chunk)
        return self._transitions.handle_recognition(recognition)

    def handle_chunk_with_diagnostics(
        self,
        chunk: AudioChunk,
        *,
        diagnostic_collector: Any,
    ) -> SessionEvent:
        recognition = _recognize_with_optional_diagnostics(
            self._recognizer,
            chunk,
            diagnostic_collector=diagnostic_collector,
        )
        return self._transitions.handle_recognition(recognition)


def _recognize_with_optional_diagnostics(
    recognizer: SpeechRecognizer,
    chunk: AudioChunk,
    *,
    diagnostic_collector: Any,
) -> RecognitionResult:
    if _recognizer_accepts_diagnostic_collector(recognizer):
        return recognizer.recognize(
            chunk,
            diagnostic_collector=diagnostic_collector,
        )
    return recognizer.recognize(chunk)


def _recognizer_accepts_diagnostic_collector(recognizer: SpeechRecognizer) -> bool:
    try:
        parameters = signature(recognizer.recognize).parameters
    except (TypeError, ValueError):
        return False

    diagnostic_parameter = parameters.get("diagnostic_collector")
    if diagnostic_parameter is not None:
        return diagnostic_parameter.kind in {
            Parameter.POSITIONAL_OR_KEYWORD,
            Parameter.KEYWORD_ONLY,
        }
    return any(
        parameter.kind is Parameter.VAR_KEYWORD
        for parameter in parameters.values()
    )
