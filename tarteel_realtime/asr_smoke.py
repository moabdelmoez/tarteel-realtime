from __future__ import annotations

import argparse
import json
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, TextIO

from tarteel_realtime.locator import LocatorDecision, QuranLocator
from tarteel_realtime.quran import QuranCorpus
from tarteel_realtime.recognition import AudioChunk, RecognitionResult, SpeechRecognizer
from tarteel_realtime.scope import mvp_corpus
from tarteel_realtime.whisper_adapter import WhisperBackendMissing, WhisperConfig, WhisperRecognizer


DEFAULT_MODEL_ID = "basharalrfooh/whisper-small-quran"
DEFAULT_SAMPLE_RATE_HZ = 16_000

RecognizerFactory = Callable[[WhisperConfig], SpeechRecognizer]


class AudioInputError(ValueError):
    pass


@dataclass(frozen=True)
class SmokeAudio:
    pcm: bytes
    sample_rate_hz: int


def load_audio_file(audio_path: Path, *, raw_sample_rate_hz: int) -> SmokeAudio:
    if audio_path.suffix.lower() == ".wav":
        return load_wav_file(audio_path)

    return SmokeAudio(
        pcm=audio_path.read_bytes(),
        sample_rate_hz=raw_sample_rate_hz,
    )


def load_wav_file(audio_path: Path) -> SmokeAudio:
    try:
        with wave.open(str(audio_path), "rb") as wav_file:
            if wav_file.getnchannels() != 1:
                raise AudioInputError("WAV input must be mono PCM16 audio.")
            if wav_file.getsampwidth() != 2:
                raise AudioInputError("WAV input must use 16-bit PCM samples.")
            if wav_file.getcomptype() != "NONE":
                raise AudioInputError("WAV input must be uncompressed PCM audio.")

            return SmokeAudio(
                pcm=wav_file.readframes(wav_file.getnframes()),
                sample_rate_hz=wav_file.getframerate(),
            )
    except wave.Error as exc:
        raise AudioInputError(f"Invalid WAV input: {exc}") from exc


def transcribe_pcm16_file(
    audio_path: Path,
    *,
    recognizer: SpeechRecognizer,
    sample_rate_hz: int,
) -> RecognitionResult:
    audio = load_audio_file(audio_path, raw_sample_rate_hz=sample_rate_hz)
    return recognize_audio(audio, recognizer=recognizer)


def recognize_audio(audio: SmokeAudio, *, recognizer: SpeechRecognizer) -> RecognitionResult:
    chunk = AudioChunk(
        sequence_number=0,
        pcm=audio.pcm,
        sample_rate_hz=audio.sample_rate_hz,
    )
    return recognizer.recognize(chunk)


def result_payload(
    result: RecognitionResult,
    *,
    audio_path: Path,
    sample_rate_hz: int,
    locator_decision: LocatorDecision | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "audio_path": str(audio_path),
        "sample_rate_hz": sample_rate_hz,
        "transcript": result.transcript,
        "normalized_transcript": result.normalized_transcript,
        "confidence": result.confidence,
        "chunk_sequence": result.chunk_sequence if result.chunk_sequence is not None else 0,
        "is_final": result.is_final,
    }
    if locator_decision is not None:
        payload["locator"] = locator_payload(locator_decision)
    return payload


def locator_payload(decision: LocatorDecision) -> dict[str, object]:
    return {
        "status": decision.status.value,
        "reason": decision.reason,
        "candidates": [
            {
                "ayah_ref": str(candidate.ayah_ref),
                "start_ref": str(candidate.start_ref),
                "matched_words": candidate.matched_words,
                "score": candidate.score,
            }
            for candidate in decision.candidates
        ],
    }


def locate_transcript(
    transcript: str,
    *,
    tanzil_path: Path,
    minimum_lock_words: int,
    use_mvp_scope: bool,
) -> LocatorDecision:
    corpus = QuranCorpus.from_tanzil_file(tanzil_path)
    if use_mvp_scope:
        corpus = mvp_corpus(corpus)
    return QuranLocator(corpus, minimum_lock_words=minimum_lock_words).locate(transcript)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run one opt-in Whisper ASR smoke transcription over a PCM16LE or mono PCM16 WAV file.",
    )
    parser.add_argument("audio_path", type=Path, help="Path to little-endian signed PCM16 audio or mono PCM16 WAV.")
    parser.add_argument("--model-id", default=DEFAULT_MODEL_ID, help="Hugging Face model ID to load.")
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=DEFAULT_SAMPLE_RATE_HZ,
        help="Raw PCM sample rate in Hz. WAV input uses the file's embedded sample rate.",
    )
    parser.add_argument("--language", default="ar", help="Recognition language hint.")
    parser.add_argument("--device", default=None, help="Optional transformers pipeline device.")
    parser.add_argument("--tanzil-path", type=Path, default=None, help="Optional Tanzil text file for locating the transcript.")
    parser.add_argument("--minimum-lock-words", type=int, default=3, help="Minimum words needed for a locator lock.")
    parser.add_argument("--mvp-scope", action="store_true", help="Scope locator corpus to Al-Fatihah and Juz Amma.")
    return parser


def _default_recognizer_factory(config: WhisperConfig) -> SpeechRecognizer:
    return WhisperRecognizer.from_transformers(config)


def main(
    argv: list[str] | None = None,
    *,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
    recognizer_factory: RecognizerFactory | None = None,
) -> int:
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    args = build_parser().parse_args(argv)

    config = WhisperConfig(
        model_id=args.model_id,
        language=args.language,
        device=args.device,
    )
    factory = recognizer_factory or _default_recognizer_factory

    try:
        audio = load_audio_file(args.audio_path, raw_sample_rate_hz=args.sample_rate)
        recognizer = factory(config)
        result = recognize_audio(audio, recognizer=recognizer)
        locator_decision = None
        if args.tanzil_path is not None:
            locator_decision = locate_transcript(
                result.transcript,
                tanzil_path=args.tanzil_path,
                minimum_lock_words=args.minimum_lock_words,
                use_mvp_scope=args.mvp_scope,
            )
    except (AudioInputError, FileNotFoundError, ValueError, WhisperBackendMissing) as exc:
        print(str(exc), file=stderr)
        return 2

    print(
        json.dumps(
            result_payload(
                result,
                audio_path=args.audio_path,
                sample_rate_hz=audio.sample_rate_hz,
                locator_decision=locator_decision,
            ),
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ),
        file=stdout,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
