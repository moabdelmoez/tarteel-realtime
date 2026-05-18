# Quran Recitation MVP Technical Plan

## Summary

Build a technical validation MVP for a Tarteel-like iPhone recitation assistant focused on one strict loop: user taps mic, recites from anywhere in Juz Amma + Al-Fatihah, the app locates the surah/ayah, tracks recitation, stops on likely word-sequence mistakes, offers Al-Husary ayah playback, then requires the user to repeat the whole ayah.

The MVP is Hafs-only, words-only, cloud-first, optimized for quiet indoor hifz learners, and positioned as a memorization assistant, not a replacement for a qualified Quran teacher.

## Key Architecture

- iPhone app: Native SwiftUI + `AVAudioEngine` for microphone capture, voice-first UI, and ayah playback.
- Backend: Python FastAPI with WebSocket audio streaming, hosted first on RunPod GPU, with Lambda Cloud as backup.
- Recognition: Benchmark Quran-fine-tuned Whisper-family models first, e.g. `whisper-small-quran` and `tadabur-whisper-medium`.
- Streaming style: Rolling 1-3 second audio chunks, not true streaming ASR yet.
- Correction logic: ASR transcript feeds a deterministic Quran text aligner. The aligner returns `correct`, `wrong`, or `uncertain`.
- Privacy: No raw production audio retention. Store only non-audio telemetry: ayah IDs, confidence, decision type, latency, and anonymized error categories.

## Data And Interfaces

- Canonical Quran text: Pin Tanzil locally as the verified source of truth, with version/checksum recorded.
- Playback audio: Use QUL Al-Husary ayah-by-ayah data for internal MVP validation; audio rights review is required before public/commercial release.
- Main WebSocket events: `session_started`, `locating`, `lock_candidate`, `locked`, `progress`, `wrong`, `uncertain`, `play_help`, `resumed`, `session_stopped`.
- Core domain types: `QuranRef(surah, ayah, wordIndex)`, `RecognitionChunk`, `AlignmentState`, `CorrectionDecision`, `SessionMetrics`.

## Feature-by-Feature TDD Roadmap

1. Quran data foundation: Parse Tanzil, map surah/ayah/word IDs, normalize Arabic for matching, test against fixed fixtures.
2. Alignment engine: Use fake transcripts first; test correct recitation, skipped word, extra word, wrong word, repetition, hesitation, and self-correction.
3. Locator engine: Given partial transcripts, rank likely ayah candidates; test repeated Quran phrases and low-confidence ambiguity.
4. Offline evaluator: Feed prerecorded public/volunteer test clips; measure locator accuracy, mistake detection, latency, and uncertainty rate.
5. ASR adapter: Add Quran Whisper baseline behind a stable interface; benchmark models without changing aligner tests.
6. Streaming backend: WebSocket service with fake recognizer first, then real rolling ASR; test no raw-audio persistence.
7. iPhone prototype: Mic permission, start/stop session, listening states, correction prompt, Al-Husary playback, repeat-whole-ayah flow.
8. End-to-end validation: Run scripted recitation sessions over the live iPhone-to-server path before expanding corpus.

## Test Gates

- Locator locks onto correct ayah within about 5 seconds for most clean in-corpus starts; ambiguous starts show candidates.
- Real word-sequence mistakes stop the user within 1-2 words.
- Correct recitations should not receive false `wrong`; uncertain cases use "please repeat."
- Seeded mistakes in Juz Amma + Fatihah must be caught at a high rate before iPhone polish begins.
- No raw production audio is written to disk, logs, crash reports, or analytics.

## Assumptions

- MVP scope is Juz Amma + Al-Fatihah, not full Quran.
- User must repeat the whole ayah after correction.
- UI is English with Arabic Quran references where needed.
- The first public/beta release requires an audio licensing review and ideally scholar/Quran teacher review of wording and behavior.
- Current technical bet is feasible, but perfect "never miss any mistake" is not realistic; the strict product behavior is achieved by stopping on `wrong` or `uncertain`, never silently accepting uncertainty as correct.

## Reference Links

- Tarteel: https://tarteel.ai/
- Tanzil Quran Text Download: https://tanzil.net/download
- Tanzil Project docs: https://tanzil.net/docs/tanzil_project
- QUL Al-Husary ayah-by-ayah resource: https://qul.tarteel.ai/resources/recitation/111
- Whisper Small Quran: https://huggingface.co/basharalrfooh/whisper-small-quran
- Tadabur Whisper Medium: https://huggingface.co/rakansuliman/tadabur-whisper-medium
