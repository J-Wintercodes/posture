import XCTest
@testable import Posture

final class AutoStartPolicyTests: XCTestCase {
    /// At the library with AirPods in and a full battery: everything lines up.
    private func readyInput() -> AutoStartPolicy.Input {
        var input = AutoStartPolicy.Input()
        input.placeName = "Library"
        input.headphonesConnected = true
        input.batteryLevel = 0.8
        return input
    }

    func testStartsWhenEverythingLinesUp() {
        XCTAssertEqual(AutoStartPolicy.decide(readyInput()), .start(placeName: "Library"))
    }

    func testLowPowerModeAlwaysBlocks() {
        var input = readyInput()
        input.isLowPowerMode = true
        input.isCharging = true
        input.batteryLevel = 1
        XCTAssertEqual(AutoStartPolicy.decide(input), .blocked(.lowPowerMode))
    }

    func testLowBatteryBlocksUnlessCharging() {
        var input = readyInput()
        input.batteryLevel = 0.12
        XCTAssertEqual(AutoStartPolicy.decide(input), .blocked(.lowBattery))
        input.isCharging = true
        XCTAssertEqual(AutoStartPolicy.decide(input), .start(placeName: "Library"))
    }

    func testNoWeeklySchedule() {
        // Late in the evening and at the weekend it still starts: there is
        // no schedule any more, only the place and the AirPods.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        var input = readyInput()
        input.now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 21, minute: 30)) ?? Date()
        XCTAssertEqual(AutoStartPolicy.decide(input), .start(placeName: "Library"))
    }

    func testDisabledBlocks() {
        var input = readyInput()
        input.enabled = false
        XCTAssertEqual(AutoStartPolicy.decide(input), .blocked(.disabled))
    }

    func testNeedsPlaceAndHeadphones() {
        var input = readyInput()
        input.headphonesConnected = false
        XCTAssertEqual(AutoStartPolicy.decide(input), .blocked(.noHeadphones))
        input.placeName = nil
        XCTAssertEqual(AutoStartPolicy.decide(input), .blocked(.notAtFocusPlace))
    }

    func testSnoozeAfterTheUserEndedAnAutoSession() {
        var input = readyInput()
        input.snoozedUntil = input.now.addingTimeInterval(600)
        XCTAssertEqual(AutoStartPolicy.decide(input), .blocked(.snoozed))
    }
}

final class FatigueMonitorTests: XCTestCase {
    private func reading(t: Double, score: Double, events: [PostureEvent] = []) -> PostureReading {
        PostureReading(
            t: t, dt: 1, pitch: 0, roll: 0, score: score, zone: .aligned, context: .focused,
            entry: .none, load: 0, isScored: true, events: events
        )
    }

    func testSteadySessionSuggestsNothing() {
        var monitor = FatigueMonitor()
        for second in 0..<(20 * 60) {
            XCTAssertNil(monitor.ingest(reading(t: Double(second), score: 90)))
        }
    }

    func testFadingScoreSuggestsABreak() {
        var monitor = FatigueMonitor()
        var suggestion: BreakReason?
        for second in 0..<(12 * 60) where suggestion == nil {
            // From 92 down to 68 over twelve minutes.
            let score = 92 - 24 * Double(second) / (12 * 60)
            suggestion = monitor.ingest(reading(t: Double(second), score: score))
        }
        XCTAssertEqual(suggestion, .fatigueTrend)
    }

    func testRepeatedNudgesSuggestABreak() {
        var monitor = FatigueMonitor()
        var suggestion: BreakReason?
        for second in 0..<400 where suggestion == nil {
            let nudge: [PostureEvent] = second % 100 == 50 ? [.nudge(.slouch, level: 0)] : []
            suggestion = monitor.ingest(reading(t: Double(second), score: 85, events: nudge))
        }
        XCTAssertEqual(suggestion, .repeatedSlouch)
    }

    func testSuggestionsRespectTheCooldown() {
        var monitor = FatigueMonitor()
        var count = 0
        for second in 0..<(10 * 60) {
            let nudge: [PostureEvent] = second % 30 == 0 ? [.nudge(.slouch, level: 0)] : []
            if monitor.ingest(reading(t: Double(second), score: 70, events: nudge)) != nil { count += 1 }
        }
        XCTAssertEqual(count, 1)
    }
}

final class ZoneGridTests: XCTestCase {
    func testCentreAndCorners() {
        XCTAssertEqual(ZoneGrid.index(pitch: 1, roll: 1), 3 * 8 + 4)
        XCTAssertEqual(ZoneGrid.index(pitch: 29, roll: -29), 0)
        XCTAssertEqual(ZoneGrid.index(pitch: -29, roll: 29), 63)
        XCTAssertEqual(ZoneGrid.index(pitch: 90, roll: -90), 0)
    }
}
