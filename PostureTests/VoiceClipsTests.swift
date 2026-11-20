import XCTest
@testable import Posture

/// Theo's recorded voice: Swift must find the files that
/// tools/voice/make_voice.py wrote.
final class VoiceClipsTests: XCTestCase {
    /// Reference names printed by make_voice.py (`clip_name`).
    func testFileNamesMatchTheGenerator() {
        XCTAssertEqual(VoiceClips.clipName("Weiter geht's.", language: .de), "v_de_86dcc2927063d208")
        XCTAssertEqual(VoiceClips.clipName("Rückbeuge im Stehen.", language: .de), "v_de_8b06c4142517577e")
        XCTAssertEqual(VoiceClips.clipName("Back on.", language: .en), "v_en_adc9ed4a0e4c8260")
    }

    /// Same cuts as `chunks` in make_voice.py.
    func testSentencesAreCutLikeTheGenerator() {
        XCTAssertEqual(
            VoiceClips.sentences(of: "  Hallo,  ich bin Theo. Schultern locker, Rücken lang.  Gym in 5 Minuten: los! Ok? ja"),
            ["Hallo, ich bin Theo.", "Schultern locker, Rücken lang.", "Gym in 5 Minuten: los!", "Ok?", "ja"]
        )
    }

    /// Everything Theo can say has a recording. Fails after a spoken text was
    /// changed without running make_voice.py again (the app then falls back
    /// to the iOS voice for that text).
    func testEverySpokenTextIsRecorded() {
        var missing: [String] = []
        func check(_ text: String, _ language: CoachLanguage) {
            if VoiceClips.files(for: text, language: language) == nil {
                missing.append("\(language.rawValue): \(text)")
            }
        }

        let cues: [CoachCue] = [
            .sessionStarted(auto: false), .sessionStarted(auto: true), .sessionEnded,
            .pausedLowPower, .resumed, .uprightSet
        ]
        let notes: [Advice.Note] = [
            .plain, .home, .library, .lecture, .gymSoon(minutes: 1), .gymSoon(minutes: 90),
            .afterGym, .evening, .homeRelaxed, .gentle
        ]
        let triggers: [CheckInTrigger] = [
            .timer(minutes: 5), .timer(minutes: 45), .timer(minutes: 300),
            .fatigue(.fatigueTrend), .fatigue(.repeatedSlouch), .fatigue(.longSit)
        ]

        for language in CoachLanguage.allCases {
            check(CoachScript.preview(language: language), language)
            for cue in cues {
                if let line = CoachScript.line(for: cue, language: language, variant: 0) {
                    check(line, language)
                }
            }
            for routine in RoutineCatalog.all {
                for note in notes {
                    for trigger in triggers {
                        let advice = Advice(routine: routine, note: note)
                        check(AdviceText.spoken(advice, trigger: trigger, language: language), language)
                    }
                }
                // RoutinePlayerView reads each step aloud.
                for step in routine.steps {
                    check("\(step.title.text(language)). \(step.cue.text(language))", language)
                }
            }
        }
        XCTAssertEqual(missing, [], "Run tools/voice/make_voice.py")
    }
}
