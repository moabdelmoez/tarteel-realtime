from __future__ import annotations

from tarteel_realtime.api import create_app
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import FakeRecognizer


DEV_TANZIL_LINES = [
    "113|1|قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
    "114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ",
    "114|2|مَلِكِ النَّاسِ",
]

DEV_RECOGNIZER_SCRIPT = [
    "مَلِكِ",
    "الْفَلَقِ",
]


def create_dev_app():
    return create_app(
        corpus=QuranCorpus.from_tanzil_lines(DEV_TANZIL_LINES),
        recognizer_factory=lambda: FakeRecognizer(DEV_RECOGNIZER_SCRIPT),
        minimum_lock_words=1,
    )


app = create_dev_app()
