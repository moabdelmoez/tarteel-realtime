from __future__ import annotations

from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import AudioChunk, SpeechRecognizer
from tarteel_realtime.session_events import SessionEvent, SessionEventType
from tarteel_realtime.session_transitions import RecitationTransitionPolicy


class RecitationSession:
    def __init__(
        self,
        *,
        corpus: QuranCorpus,
        recognizer: SpeechRecognizer,
        minimum_lock_words: int = 3,
    ) -> None:
        self._recognizer = recognizer
        self._transitions = RecitationTransitionPolicy(
            corpus=corpus,
            minimum_lock_words=minimum_lock_words,
        )

    def handle_chunk(self, chunk: AudioChunk) -> SessionEvent:
        recognition = self._recognizer.recognize(chunk)
        return self._transitions.handle_recognition(recognition)
