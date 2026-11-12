import XCTest
@testable import Posture

/// Shared clock for the day-plan tests: Thursday, 12 November 2026, Berlin.
private enum PlanClock {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour, minute: minute)) ?? Date()
    }

    static func event(_ kind: EventKind, _ title: String, from: Date, to: Date) -> PlannedEvent {
        PlannedEvent(id: title, title: title, start: from, end: to, kind: kind)
    }
}

final class EventClassifierTests: XCTestCase {
    private let uni = EventClassifier.keywords(EventClassifier.defaultUniKeywords)
    private let gym = EventClassifier.keywords(EventClassifier.defaultGymKeywords)

    private func kind(_ title: String, location: String? = nil, calendar: String? = nil) -> EventKind {
        EventClassifier.kind(title: title, location: location, calendarName: calendar, uni: uni, gym: gym)
    }

    func testKeywordListIsSplitAndCleaned() {
        XCTAssertEqual(EventClassifier.keywords(" Gym, fitness ,, Training "), ["gym", "fitness", "training"])
    }

    func testLecturesAndGym() {
        XCTAssertEqual(kind("Vorlesung Analysis II"), .uni)
        XCTAssertEqual(kind("VL Statistik"), .uni)
        XCTAssertEqual(kind("Übung Lineare Algebra"), .uni)
        XCTAssertEqual(kind("Gym"), .gym)
        XCTAssertEqual(kind("Krafttraining Beine"), .gym)
        XCTAssertEqual(kind("Zahnarzt"), .other)
    }

    func testLocationAndCalendarNameCount() {
        XCTAssertEqual(kind("Analysis II", location: "Hörsaal 3"), .uni)
        XCTAssertEqual(kind("Analysis II", calendar: "Uni"), .uni)
        XCTAssertEqual(kind("Beine", location: "McFit Mitte"), .gym)
    }

    func testShortWordsNeedAWholeWord() {
        // "uni" must not hit "Community", "sport" must not hit "Transport".
        XCTAssertEqual(kind("Community Treffen"), .other)
        XCTAssertEqual(kind("Transport Möbel"), .other)
        XCTAssertEqual(kind("Evlin anrufen"), .other)
    }

    func testGymWinsOverUni() {
        XCTAssertEqual(kind("Unisport Volleyball"), .gym)
        XCTAssertEqual(kind("Training", calendar: "Uni"), .gym)
    }
}

final class DayPlannerTests: XCTestCase {
    private func input(at now: Date, events: [PlannedEvent] = [], place: PlaceKind? = nil) -> DayPlanner.Input {
        var input = DayPlanner.Input()
        input.now = now
        input.events = events
        input.placeKind = place
        input.placeName = place?.defaultName
        return input
    }

    func testCalendarIsBelievedWhenLocationIsUnknown() {
        let lecture = PlanClock.event(.uni, "Vorlesung", from: PlanClock.at(10, 15), to: PlanClock.at(11, 45))
        let context = DayPlanner.resolve(input(at: PlanClock.at(10, 30), events: [lecture]))
        XCTAssertEqual(context.situation, .uni)
        XCTAssertEqual(context.source, .calendar)
        XCTAssertFalse(context.calendarOverruled)
    }

    func testLocationBeatsTheCalendar() {
        // The calendar says lecture, the phone is at home: the lecture was skipped.
        let lecture = PlanClock.event(.uni, "Vorlesung", from: PlanClock.at(10, 15), to: PlanClock.at(11, 45))
        let context = DayPlanner.resolve(input(at: PlanClock.at(10, 30), events: [lecture], place: .home))
        XCTAssertEqual(context.situation, .home)
        XCTAssertEqual(context.source, .location)
        XCTAssertTrue(context.calendarOverruled)
    }

    func testSavedGymThatThePhoneIsNotAtOverrulesTheCalendar() {
        let training = PlanClock.event(.gym, "Gym", from: PlanClock.at(18), to: PlanClock.at(19, 30))
        var query = input(at: PlanClock.at(18, 20), events: [training])
        query.savedKinds = [.home, .gym]
        query.locationKnown = true
        let context = DayPlanner.resolve(query)
        XCTAssertEqual(context.situation, .elsewhere)
        XCTAssertTrue(context.calendarOverruled)

        // Without a saved gym there is nothing to check against.
        query.savedKinds = [.home]
        XCTAssertEqual(DayPlanner.resolve(query).situation, .gym)
    }

    func testGymSoonAndAfterGym() {
        let training = PlanClock.event(.gym, "Gym", from: PlanClock.at(18), to: PlanClock.at(19, 30))
        let before = DayPlanner.resolve(input(at: PlanClock.at(17, 20), events: [training], place: .library))
        XCTAssertEqual(before.gymInMinutes, 40)
        XCTAssertFalse(before.afterGym)

        let early = DayPlanner.resolve(input(at: PlanClock.at(15), events: [training], place: .library))
        XCTAssertNil(early.gymInMinutes)

        let after = DayPlanner.resolve(input(at: PlanClock.at(20), events: [training], place: .home))
        XCTAssertTrue(after.afterGym)
        XCTAssertNil(after.gymInMinutes)
    }

    func testOtherEntriesAreIgnored() {
        let dentist = PlanClock.event(.other, "Zahnarzt", from: PlanClock.at(10), to: PlanClock.at(11))
        let context = DayPlanner.resolve(input(at: PlanClock.at(10, 30), events: [dentist]))
        XCTAssertEqual(context.situation, .elsewhere)
        XCTAssertNil(context.event)
    }
}

final class AdvisorTests: XCTestCase {
    private func context(_ situation: Situation) -> DayContext {
        var context = DayContext()
        context.situation = situation
        return context
    }

    func testFloorRoutinesOnlyAtHome() {
        for situation in [Situation.library, .uni, .elsewhere] {
            for index in 0..<12 {
                let advice = Advisor.advice(for: context(situation), hour: 14, index: index)
                XCTAssertEqual(advice?.routine.homeOnly, false, "\(situation) at check-in \(index)")
            }
        }
        let atHome = (0..<6).compactMap { Advisor.advice(for: context(.home), hour: 14, index: $0)?.routine }
        XCTAssertTrue(atHome.contains { $0.homeOnly })
        XCTAssertTrue(atHome.contains(RoutineCatalog.backStrength))
        XCTAssertTrue(atHome.contains(RoutineCatalog.nerveGlide))
    }

    func testLectureIsAlwaysTheQuietReset() {
        for index in 0..<5 {
            XCTAssertEqual(Advisor.advice(for: context(.uni), hour: 11, index: index)?.routine, RoutineCatalog.lectureReset)
        }
    }

    func testGymIsSilent() {
        XCTAssertNil(Advisor.advice(for: context(.gym), hour: 18, index: 0))
    }

    func testNoStrengthBeforeTheGym() {
        var home = context(.home)
        home.gymInMinutes = 45
        for index in 0..<8 {
            let advice = Advisor.advice(for: home, hour: 16, index: index)
            XCTAssertNotEqual(advice?.routine, RoutineCatalog.backStrength)
            XCTAssertNotEqual(advice?.routine, RoutineCatalog.downshift)
            XCTAssertEqual(advice?.note, .gymSoon(minutes: 45))
        }
    }

    func testEveningAndAfterGymWindDown() {
        let evening = (0..<4).compactMap { Advisor.advice(for: context(.home), hour: 21, index: $0)?.routine }
        XCTAssertTrue(evening.contains(RoutineCatalog.downshift))
        XCTAssertFalse(evening.contains(RoutineCatalog.backStrength))

        var after = context(.home)
        after.afterGym = true
        let afterGym = (0..<4).compactMap { Advisor.advice(for: after, hour: 15, index: $0)?.routine }
        XCTAssertTrue(afterGym.contains(RoutineCatalog.downshift))
        XCTAssertFalse(afterGym.contains(RoutineCatalog.backStrength))
    }

    func testOncePerDayRoutinesAreSkippedWhenDone() {
        let done: Set<String> = [RoutineCatalog.backStrength.id]
        // Index 3 is the strength slot of the home cycle.
        XCTAssertEqual(Advisor.advice(for: context(.home), hour: 14, index: 3)?.routine, RoutineCatalog.backStrength)
        XCTAssertNotEqual(Advisor.advice(for: context(.home), hour: 14, index: 3, doneToday: done)?.routine, RoutineCatalog.backStrength)
    }

    func testAvailability() {
        XCTAssertTrue(Advisor.isAvailable(RoutineCatalog.spineFlow, in: .home))
        XCTAssertFalse(Advisor.isAvailable(RoutineCatalog.spineFlow, in: .library))
        XCTAssertTrue(Advisor.isAvailable(RoutineCatalog.eyeReset, in: .uni))
    }

    func testRoutineLengths() {
        XCTAssertEqual(RoutineCatalog.eyeReset.seconds, 30)
        XCTAssertEqual(RoutineCatalog.eyeReset.durationLabel, "30s")
        XCTAssertEqual(RoutineCatalog.standUp.durationLabel, "2 min")
        XCTAssertEqual(RoutineCatalog.spineFlow.durationWords(.de), "3 Minuten")
        XCTAssertEqual(Set(RoutineCatalog.all.map { $0.id }).count, RoutineCatalog.all.count)
        XCTAssertEqual(RoutineCatalog.routine(id: "downshift"), RoutineCatalog.downshift)
    }
}

final class CheckInPlannerTests: XCTestCase {
    private func input(start: Date, hours: Double = 4, minutes: Int = 30) -> CheckInPlanner.Input {
        var input = CheckInPlanner.Input()
        input.now = start
        input.anchor = start
        input.endsAt = start.addingTimeInterval(hours * 3600)
        input.intervalMinutes = minutes
        input.calendar = PlanClock.calendar
        input.maxSlots = 12
        return input
    }

    func testEveryIntervalUntilTheEnd() {
        let start = PlanClock.at(9)
        let slots = CheckInPlanner.plan(input(start: start))
        XCTAssertEqual(slots.count, 8)
        XCTAssertEqual(slots.first?.date, start.addingTimeInterval(30 * 60))
        XCTAssertEqual(slots.last?.date, start.addingTimeInterval(4 * 3600))
        XCTAssertEqual(slots.filter { $0.isLast }.count, 1)
        XCTAssertEqual(slots.last?.isLast, true)
    }

    func testPastSlotsAreSkippedAndRotationContinues() {
        let start = PlanClock.at(9)
        var query = input(start: start)
        query.now = start.addingTimeInterval(70 * 60)
        let slots = CheckInPlanner.plan(query)
        XCTAssertEqual(slots.first?.date, start.addingTimeInterval(90 * 60))
        // Third check-in of the library/elsewhere cycle.
        XCTAssertEqual(slots.first?.advice.routine, RoutineCatalog.deskMobility)
    }

    func testCalendarShapesLaterSlots() {
        let start = PlanClock.at(9)
        var query = input(start: start)
        query.events = [
            PlanClock.event(.uni, "Vorlesung", from: PlanClock.at(10, 15), to: PlanClock.at(11, 45)),
            PlanClock.event(.gym, "Gym", from: PlanClock.at(12), to: PlanClock.at(13, 30))
        ]
        let slots = CheckInPlanner.plan(query)
        let byTime = Dictionary(uniqueKeysWithValues: slots.map { ($0.date, $0.advice) })

        // 10:30 and 11:30 fall into the lecture.
        XCTAssertEqual(byTime[PlanClock.at(10, 30)]?.routine, RoutineCatalog.lectureReset)
        XCTAssertEqual(byTime[PlanClock.at(11, 30)]?.routine, RoutineCatalog.lectureReset)
        // 12:00 is the start of the gym entry, 12:30 and 13:00 are inside it: silence.
        XCTAssertNil(byTime[PlanClock.at(12)])
        XCTAssertNil(byTime[PlanClock.at(12, 30)])
        XCTAssertNil(byTime[PlanClock.at(13)])
    }

    func testHomeOverridesALectureInTheCalendar() {
        let start = PlanClock.at(10)
        var query = input(start: start)
        query.placeKind = .home
        query.events = [PlanClock.event(.uni, "Vorlesung", from: PlanClock.at(10, 15), to: PlanClock.at(11, 45))]
        let slots = CheckInPlanner.plan(query)
        XCTAssertFalse(slots.contains { $0.advice.routine == RoutineCatalog.lectureReset })
        XCTAssertTrue(slots.contains { $0.advice.routine.homeOnly })
    }

    func testTextsNameTheRoutine() {
        let advice = Advice(routine: RoutineCatalog.spineFlow, note: .home)
        XCTAssertEqual(AdviceText.title(advice, language: .de), "Zeit für: Wirbelsäulen-Flow · 3 min")
        let body = AdviceText.body(advice, trigger: .timer(minutes: 60), language: .de)
        XCTAssertEqual(body, "60 Minuten ohne Pause. Du bist zuhause, also ab auf den Boden.")
        let spoken = AdviceText.spoken(advice, trigger: .timer(minutes: 60), language: .en)
        XCTAssertTrue(spoken.contains("a spine mobility flow on the floor"))

        // Reminders only: no claim about how long the user has been sitting.
        let reminder = AdviceText.body(advice, trigger: .interval(minutes: 30), language: .en)
        XCTAssertEqual(reminder, "Another 30 minutes gone. You're home, so use the floor.")
        XCTAssertEqual(CheckInPlanner.roundedMinutes(from: PlanClock.at(9), to: PlanClock.at(10, 2), atLeast: 30), 60)
        XCTAssertEqual(CheckInPlanner.roundedMinutes(from: PlanClock.at(9), to: PlanClock.at(9, 10), atLeast: 30), 30)
    }
}
