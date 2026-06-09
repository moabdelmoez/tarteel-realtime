import Foundation
import Testing
@testable import TarteelClientCore

struct RecitationSessionStateTests {
    @Test func lockedEventMovesStateIntoListeningMode() {
        let event = RecitationEvent(
            type: .locked,
            transcript: "مَلِكِ النَّاسِ",
            confidence: 1.0,
            chunkSequence: 0,
            reason: "unique_match",
            candidateRefs: [],
            ayahText: "مَلِكِ النَّاسِ",
            ayahRef: "114:2",
            startRef: "114:2:1",
            nextExpectedRef: nil,
            consumedWords: 2,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )

        let state = RecitationSessionState().applying(event)

        #expect(state.phase == .listening)
        #expect(state.currentAyahRef == "114:2")
        #expect(state.currentAyahText == "مَلِكِ النَّاسِ")
        #expect(state.headline == "Locked on 114:2")
        #expect(state.detail == "مَلِكِ النَّاسِ")
        #expect(state.debugLastEventText == "locked (unique_match)")
        #expect(state.debugAyahText == "114:2")
        #expect(state.debugTranscriptText == "مَلِكِ النَّاسِ")
    }

    @Test func lockedEventShowsCanonicalAyahInsteadOfRawTranscript() {
        let event = RecitationEvent(
            type: .locked,
            transcript: "raw asr noise",
            confidence: 0.7,
            chunkSequence: 4,
            reason: "tolerant_match",
            candidateRefs: [],
            ayahText: "أَلْهَاكُمُ التَّكَاثُرُ",
            ayahRef: "102:1",
            startRef: "102:1:1",
            nextExpectedRef: nil,
            consumedWords: 2,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )

        let state = RecitationSessionState().applying(event)

        #expect(state.currentAyahRef == "102:1")
        #expect(state.currentAyahText == "أَلْهَاكُمُ التَّكَاثُرُ")
        #expect(state.detail == "أَلْهَاكُمُ التَّكَاثُرُ")
        #expect(state.lastTranscript == "raw asr noise")
    }

    @Test func wrongEventMovesStateIntoCorrectionMode() {
        let event = RecitationEvent(
            type: .wrong,
            transcript: "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
            confidence: 1.0,
            chunkSequence: 1,
            reason: "word_mismatch",
            candidateRefs: [],
            ayahText: nil,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: nil,
            consumedWords: 3,
            expectedRef: "114:1:4",
            expectedWord: "النَّاسِ",
            recognizedWord: "الْفَلَقِ"
        )

        let state = RecitationSessionState(phase: .listening).applying(event)

        #expect(state.phase == .needsCorrection)
        #expect(state.headline == "Correction needed")
        #expect(state.detail == "Expected النَّاسِ, heard الْفَلَقِ")
    }

    @Test func preLockBufferingEventShowsGatheringAudio() {
        let event = RecitationEvent(
            type: .locating,
            transcript: "",
            confidence: 0.0,
            chunkSequence: 0,
            reason: "waiting_for_audio_buffer",
            candidateRefs: [],
            ayahText: nil,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: nil,
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )

        let state = RecitationSessionState().applying(event)

        #expect(state.phase == .connecting)
        #expect(state.headline == "Gathering audio")
        #expect(state.detail == "Keep reciting")
        #expect(state.debugLastEventText == "locating (waiting_for_audio_buffer)")
        #expect(state.debugAyahText == "none")
        #expect(state.debugTranscriptText == "none")
    }

    @Test func preLockCoreMLBufferingEventUsesGatheringAudioState() {
        let event = RecitationEvent(
            type: .locating,
            transcript: "",
            confidence: 0.0,
            chunkSequence: 0,
            reason: "waiting_for_coreml_audio_buffer",
            candidateRefs: [],
            ayahText: nil,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: nil,
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )

        let state = RecitationSessionState().applying(event)

        #expect(state.phase == .connecting)
        #expect(state.headline == "Gathering audio")
        #expect(state.detail == "Keep reciting")
    }

    @Test func postLockBufferingEventKeepsListeningState() {
        let event = RecitationEvent(
            type: .uncertain,
            transcript: "",
            confidence: 0.0,
            chunkSequence: 4,
            reason: "waiting_for_audio_buffer",
            candidateRefs: [],
            ayahText: nil,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: "114:2:3",
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )
        let lockedState = RecitationSessionState(
            phase: .listening,
            currentAyahRef: "114:2",
            currentAyahText: "مَلِكِ النَّاسِ",
            headline: "Locked on 114:2",
            detail: "مَلِكِ النَّاسِ"
        )

        let state = lockedState.applying(event)

        #expect(state.phase == .listening)
        #expect(state.currentAyahRef == "114:2")
        #expect(state.currentAyahText == "مَلِكِ النَّاسِ")
        #expect(state.headline == "Listening")
        #expect(state.detail == "مَلِكِ النَّاسِ")
    }

    @Test func postLockBufferingEventDoesNotHideLastMeaningfulEvent() {
        let lockedEvent = RecitationEvent(
            type: .locked,
            transcript: "رَسُولٌ مِنَ اللَّهِ",
            confidence: 0.8,
            chunkSequence: 10,
            reason: "tolerant_progression",
            candidateRefs: [],
            ayahText: "رسول من الله يتلو صحفا مطهرة",
            ayahRef: "98:2",
            startRef: "98:2:1",
            nextExpectedRef: "98:2:4",
            consumedWords: 3,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )
        let bufferingEvent = RecitationEvent(
            type: .uncertain,
            transcript: "",
            confidence: 0.0,
            chunkSequence: 11,
            reason: "waiting_for_audio_buffer",
            candidateRefs: [],
            ayahText: nil,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: "98:2:4",
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )

        let lockedState = RecitationSessionState().applying(lockedEvent)
        let nextState = lockedState.applying(bufferingEvent)

        #expect(nextState == lockedState)
    }

    @Test func postLockLocatingEventShowsCanonicalAyahInsteadOfRawTranscript() {
        let event = RecitationEvent(
            type: .locating,
            transcript: "بل ستنت نفعل",
            confidence: 0.0,
            chunkSequence: 22,
            reason: "no_match",
            candidateRefs: [],
            ayahText: nil,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: nil,
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )
        let lockedState = RecitationSessionState(
            phase: .listening,
            currentAyahRef: "102:7",
            currentAyahText: "ثم لترونها عين اليقين",
            headline: "Listening",
            detail: "ثم لترونها عين اليقين"
        )

        let state = lockedState.applying(event)

        #expect(state.phase == .listening)
        #expect(state.currentAyahRef == "102:7")
        #expect(state.currentAyahText == "ثم لترونها عين اليقين")
        #expect(state.headline == "Listening")
        #expect(state.detail == "ثم لترونها عين اليقين")
        #expect(state.lastTranscript == "بل ستنت نفعل")
    }

    @Test func progressEventCanAdvanceDisplayedAyahWhenMetadataIsPresent() {
        let event = RecitationEvent(
            type: .progress,
            transcript: "أَعْطَيْنَاكَ الْكَوْثَرَ فَصَلِّرََبِّكَ وَانْحَرْ",
            confidence: 0.88,
            chunkSequence: 15,
            reason: "coreml_local_tolerant_match",
            candidateRefs: ["108:2"],
            ayahText: "فصل لربك وانحر",
            ayahRef: "108:2",
            startRef: "108:2:1",
            nextExpectedRef: "108:3:1",
            consumedWords: 3,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )
        let lockedState = RecitationSessionState(
            phase: .listening,
            currentAyahRef: "108:1",
            currentAyahText: "إنا أعطيناك الكوثر",
            headline: "Locked on 108:1",
            detail: "إنا أعطيناك الكوثر"
        )

        let state = lockedState.applying(event)

        #expect(state.phase == .listening)
        #expect(state.currentAyahRef == "108:2")
        #expect(state.currentAyahText == "فصل لربك وانحر")
        #expect(state.detail == "فصل لربك وانحر")
        #expect(state.lastTranscript == "أَعْطَيْنَاكَ الْكَوْثَرَ فَصَلِّرََبِّكَ وَانْحَرْ")
    }

    @Test func repeatedPreLockBufferingDoesNotHideLastMeaningfulDiagnostic() {
        let noMatchEvent = RecitationEvent(
            type: .locating,
            transcript: "hello",
            confidence: 0.4,
            chunkSequence: 42,
            reason: "no_match",
            candidateRefs: [],
            ayahText: nil,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: nil,
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )
        let bufferingEvent = RecitationEvent(
            type: .locating,
            transcript: "",
            confidence: 0.0,
            chunkSequence: 43,
            reason: "waiting_for_audio_buffer",
            candidateRefs: [],
            ayahText: nil,
            ayahRef: nil,
            startRef: nil,
            nextExpectedRef: nil,
            consumedWords: 0,
            expectedRef: nil,
            expectedWord: nil,
            recognizedWord: nil
        )

        let noMatchState = RecitationSessionState().applying(noMatchEvent)
        let nextState = noMatchState.applying(bufferingEvent)

        #expect(nextState == noMatchState)
        #expect(nextState.debugLastEventText == "locating (no_match)")
        #expect(nextState.debugTranscriptText == "hello")
    }
}
