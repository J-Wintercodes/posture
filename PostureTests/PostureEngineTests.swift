import XCTest
@testable import Posture

/// Drives the engine with synthetic AirPods frames. Each test is one desk
/// situation the heuristic has to get right.
final class PostureEngineTests: XCTestCase {
    private struct Outcome {
        var nudges: [NudgeKind] = []
        var levels: [Int] = []
        var events: [PostureEvent] = []
        var last: PostureReading?
        var scoredSeconds = 0.0
        var contexts: Set<PostureContext> = []
    }

    /// Runs `seconds` of a pose function through the engine.
    private func run(
        _ engine: inout PostureEngine,
        head: inout SyntheticHead,
        seconds: Double,
        phone: PhoneContext = PhoneContext(),
        lively: Bool = false,
        walking: Bool = false,
        into outcome: inout Outcome,
        pose: (Double) -> (forward: Double, lateral: Double)
    ) {
        let frames = Int(seconds * head.sampleRate)
        for i in 0..<frames {
            let p = pose(Double(i) / head.sampleRate)
            let reading = engine.ingest(
                head.next(forward: p.forward, lateral: p.lateral, lively: lively, walking: walking),
                phone: phone
            )
            for event in reading.events {
                outcome.events.append(event)
                if case .nudge(let kind, let level) = event {
                    outcome.nudges.append(kind)
                    outcome.levels.append(level)
                }
            }
            if reading.isScored { outcome.scoredSeconds += reading.dt }
            outcome.contexts.insert(reading.context)
            outcome.last = reading
        }
    }

    private func calibrated() -> (PostureEngine, SyntheticHead, Outcome) {
        var engine = PostureEngine()
        var head = SyntheticHead()
        var outcome = Outcome()
        run(&engine, head: &head, seconds: 10, into: &outcome) { _ in (0, 0) }
        return (engine, head, outcome)
    }

    private func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    // MARK: Tests

    func testSittingUprightStaysQuiet() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 120, into: &outcome) { _ in (0, 0) }
        XCTAssertTrue(outcome.nudges.isEmpty)
        XCTAssertGreaterThan(outcome.last?.score ?? 0, 95)
        XCTAssertEqual(outcome.last?.zone, .aligned)
    }

    func testLeaningTowardsTheScreenIsNormal() {
        var (engine, head, outcome) = calibrated()
        // Ten minutes with the head a little forward, the way people sit
        // at a monitor or laptop. That is not a slouch.
        run(&engine, head: &head, seconds: 20, into: &outcome) { t in (12 * self.ease(t / 20), 0) }
        run(&engine, head: &head, seconds: 600, into: &outcome) { _ in (12, 0) }
        XCTAssertTrue(outcome.nudges.isEmpty)
        XCTAssertEqual(outcome.last?.zone, .aligned)
        XCTAssertGreaterThan(outcome.last?.score ?? 0, 90)
        XCTAssertEqual(outcome.last?.load ?? 1, 0, accuracy: 0.001)
    }

    func testSlowSlouchGetsNudged() {
        var (engine, head, outcome) = calibrated()
        // Sink 23 degrees over half a minute, then stay there.
        run(&engine, head: &head, seconds: 30, into: &outcome) { t in (23 * t / 30, 0) }
        run(&engine, head: &head, seconds: 40, into: &outcome) { _ in (23, 0) }
        XCTAssertEqual(outcome.nudges.first, .slouch)
        XCTAssertEqual(outcome.last?.entry, .creep)
        XCTAssertLessThan(outcome.last?.score ?? 100, 70)
    }

    func testRecoveryAfterNudgeIsAcknowledged() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 30, into: &outcome) { t in (23 * t / 30, 0) }
        run(&engine, head: &head, seconds: 40, into: &outcome) { _ in (23, 0) }
        run(&engine, head: &head, seconds: 2, into: &outcome) { t in (23 * (1 - self.ease(t / 2)), 0) }
        run(&engine, head: &head, seconds: 10, into: &outcome) { _ in (0, 0) }
        XCTAssertTrue(outcome.events.contains(.recovered))
        XCTAssertEqual(outcome.last?.zone, .aligned)
    }

    func testQuickLookAtNotesIsLeftAlone() {
        var (engine, head, outcome) = calibrated()
        // A fast nod down to the page, a minute of writing, and back up.
        run(&engine, head: &head, seconds: 0.6, into: &outcome) { t in (28 * self.ease(t / 0.6), 0) }
        run(&engine, head: &head, seconds: 60, lively: true, into: &outcome) { _ in (28, 0) }
        XCTAssertEqual(outcome.last?.context, .lookingDown)
        XCTAssertEqual(outcome.last?.entry, .glance)
        XCTAssertTrue(outcome.nudges.isEmpty)
        // Looking at notes costs a little, but not what a slouch would cost.
        XCTAssertGreaterThan(outcome.last?.score ?? 0, 75)
    }

    func testVeryLongLookDownEventuallyGetsANeckNudge() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 0.6, into: &outcome) { t in (28 * self.ease(t / 0.6), 0) }
        run(&engine, head: &head, seconds: 400, into: &outcome) { _ in (28, 0) }
        XCTAssertEqual(outcome.nudges.first, .neck)
    }

    func testSipOfWaterIsIgnored() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 0.5, into: &outcome) { t in (-25 * self.ease(t / 0.5), 0) }
        run(&engine, head: &head, seconds: 4, into: &outcome) { _ in (-25, 0) }
        run(&engine, head: &head, seconds: 0.5, into: &outcome) { t in (-25 * (1 - self.ease(t / 0.5)), 0) }
        run(&engine, head: &head, seconds: 20, into: &outcome) { _ in (0, 0) }
        XCTAssertTrue(outcome.nudges.isEmpty)
        XCTAssertGreaterThan(outcome.last?.score ?? 0, 90)
    }

    func testPhoneUseSilencesTheCoach() {
        var (engine, head, outcome) = calibrated()
        let scoredBefore = outcome.scoredSeconds
        var phone = PhoneContext()
        phone.isHandheld = true
        run(&engine, head: &head, seconds: 0.6, phone: phone, into: &outcome) { t in (30 * self.ease(t / 0.6), 0) }
        run(&engine, head: &head, seconds: 180, phone: phone, into: &outcome) { _ in (30, 0) }
        XCTAssertTrue(outcome.nudges.isEmpty)
        XCTAssertEqual(outcome.last?.context, .phone)
        XCTAssertEqual(outcome.scoredSeconds, scoredBefore, accuracy: 0.001)
    }

    func testUnlockedPhoneLyingOnTheDeskDoesNotSilenceTheCoach() {
        var (engine, head, outcome) = calibrated()
        // Unlocked, but nobody is touching it: the slouch still counts.
        var phone = PhoneContext()
        phone.isUnlocked = true
        run(&engine, head: &head, seconds: 30, phone: phone, into: &outcome) { t in (23 * t / 30, 0) }
        run(&engine, head: &head, seconds: 40, phone: phone, into: &outcome) { _ in (23, 0) }
        XCTAssertEqual(outcome.nudges.first, .slouch)
        XCTAssertFalse(outcome.contexts.contains(.phone))
    }

    func testWalkingAwayPausesScoring() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 40, walking: true, into: &outcome) { _ in (6, 0) }
        XCTAssertTrue(outcome.events.contains(.away))
        XCTAssertEqual(outcome.last?.context, .away)
        XCTAssertFalse(outcome.last?.isScored ?? true)

        run(&engine, head: &head, seconds: 20, into: &outcome) { _ in (0, 0) }
        XCTAssertTrue(outcome.events.contains(.returned))
        XCTAssertEqual(outcome.last?.context, .focused)
        XCTAssertTrue(outcome.nudges.isEmpty)
    }

    func testBaselineNeverLearnsASlouch() {
        var (engine, head, outcome) = calibrated()
        // Twenty minutes of sitting slightly forward. The auto-zero may
        // follow, but only up to its cap.
        run(&engine, head: &head, seconds: 20 * 60, into: &outcome) { _ in (4.5, 0) }
        XCTAssertLessThanOrEqual(engine.offsetForward, engine.tuning.maxForwardOffset + 0.001)
        XCTAssertTrue(outcome.nudges.isEmpty)

        // A real slouch on top of that is still a slouch.
        run(&engine, head: &head, seconds: 30, into: &outcome) { t in (4.5 + 20 * t / 30, 0) }
        run(&engine, head: &head, seconds: 60, into: &outcome) { _ in (24.5, 0) }
        XCTAssertEqual(outcome.nudges.first, .slouch)
    }

    func testSittingMoreUprightIsAdoptedQuickly() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 180, into: &outcome) { _ in (-4, 0) }
        XCTAssertLessThan(engine.offsetForward, -3)
        XCTAssertTrue(outcome.nudges.isEmpty)
    }

    func testEveryBadSpellGetsBothSounds() {
        var (engine, head, outcome) = calibrated()
        // Slouch, sit up, and slouch again fifteen seconds later. Both
        // spells must announce themselves and both recoveries must chime,
        // with no cooldown swallowing the second round.
        for _ in 0..<2 {
            run(&engine, head: &head, seconds: 30, into: &outcome) { t in (23 * t / 30, 0) }
            run(&engine, head: &head, seconds: 40, into: &outcome) { _ in (23, 0) }
            run(&engine, head: &head, seconds: 2, into: &outcome) { t in (23 * (1 - self.ease(t / 2)), 0) }
            run(&engine, head: &head, seconds: 15, into: &outcome) { _ in (0, 0) }
        }
        let sounds = outcome.events.filter { event in
            if case .nudge(_, let level) = event { return level == 0 }
            return event == .recovered
        }
        XCTAssertEqual(sounds, [.nudge(.slouch, level: 0), .recovered, .nudge(.slouch, level: 0), .recovered])
    }

    func testWalkingOffEndsABadSpellSilently() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 30, into: &outcome) { t in (23 * t / 30, 0) }
        run(&engine, head: &head, seconds: 40, into: &outcome) { _ in (23, 0) }
        XCTAssertEqual(outcome.levels, [0])
        run(&engine, head: &head, seconds: 40, walking: true, into: &outcome) { _ in (23, 0) }
        run(&engine, head: &head, seconds: 20, into: &outcome) { _ in (0, 0) }
        XCTAssertFalse(outcome.events.contains(.recovered))
    }

    func testRemindersBackOffWhileASpellLasts() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 30, into: &outcome) { t in (26 * t / 30, 0) }
        run(&engine, head: &head, seconds: 300, into: &outcome) { _ in (26, 0) }
        // One sound when it turns bad, then reminders after 40, 80, 160 s.
        // Without back-off five minutes of slouching would nag every 40 s.
        XCTAssertGreaterThanOrEqual(outcome.levels.count, 2)
        XCTAssertLessThanOrEqual(outcome.levels.count, 4)
        XCTAssertEqual(outcome.levels, Array(0..<outcome.levels.count))
    }

    func testUprightSetMakesTheCurrentPoseZero() {
        var (engine, head, outcome) = calibrated()
        run(&engine, head: &head, seconds: 5, into: &outcome) { _ in (12, 4) }
        engine.setUprightNow()
        run(&engine, head: &head, seconds: 10, into: &outcome) { _ in (12, 4) }
        XCTAssertEqual(outcome.last?.pitch ?? 99, 0, accuracy: 1.0)
        XCTAssertEqual(outcome.last?.roll ?? 99, 0, accuracy: 1.0)
        XCTAssertEqual(outcome.last?.zone, .aligned)
    }
}
