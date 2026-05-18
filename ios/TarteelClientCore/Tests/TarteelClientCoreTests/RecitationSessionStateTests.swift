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
        #expect(state.headline == "Locked on 114:2")
        #expect(state.detail == "مَلِكِ النَّاسِ")
        #expect(state.debugLastEventText == "locked (unique_match)")
        #expect(state.debugAyahText == "114:2")
        #expect(state.debugTranscriptText == "مَلِكِ النَّاسِ")
    }

    @Test func wrongEventMovesStateIntoCorrectionMode() {
        let event = RecitationEvent(
            type: .wrong,
            transcript: "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ",
            confidence: 1.0,
            chunkSequence: 1,
            reason: "word_mismatch",
            candidateRefs: [],
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

    @Test func postLockBufferingEventKeepsListeningState() {
        let event = RecitationEvent(
            type: .uncertain,
            transcript: "",
            confidence: 0.0,
            chunkSequence: 4,
            reason: "waiting_for_audio_buffer",
            candidateRefs: [],
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
            headline: "Locked on 114:2",
            detail: "مَلِكِ النَّاسِ"
        )

        let state = lockedState.applying(event)

        #expect(state.phase == .listening)
        #expect(state.currentAyahRef == "114:2")
        #expect(state.headline == "Listening")
        #expect(state.detail == "Keep reciting")
    }

    @Test func repeatedPreLockBufferingDoesNotHideLastMeaningfulDiagnostic() {
        let noMatchEvent = RecitationEvent(
            type: .locating,
            transcript: "hello",
            confidence: 0.4,
            chunkSequence: 42,
            reason: "no_match",
            candidateRefs: [],
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
