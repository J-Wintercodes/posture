import XCTest
@testable import Posture

/// Shared clock for the day-plan tests: Thursday, 12 November 2026, Berlin.
private enum PlanClock {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    static func at(_ hour: Int, _ minute: Int = 0, day: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? Date()
    }

    static func event(_ kind: EventKind, _ title: String, from: Date, to: Date) -> PlannedEvent {
        PlannedEvent(id: title, title: title, start: from, end: to, kind: kind)
    }
}

final class EventClassifierTests: XCTestCase {
    private let library = EventClassifier.keywords(EventClassifier.defaultLibraryKeywords)
    private let home = EventClassifier.keywords(EventClassifier.defaultHomeKeywords)
    private let gym = EventClassifier.keywords(EventClassifier.defaultGymKeywords)

    private func kind(_ title: String) -> EventKind {
        EventClassifier.kind(title: title, library: library, home: home, gym: gym)
    }

    func testKeywordListIsSplitAndCleaned() {
        XCTAssertEqual(EventClassifier.keywords(" Gym, fitness ,, Training "), ["gym", "fitness", "training"])
    }

    func testOnlyTheStudyTitlesCount() {
        XCTAssertEqual(kind("lernen bib"), .library)
        XCTAssertEqual(kind("Lernen Bib"), .library)
        XCTAssertEqual(kind("Lernen Bibliothek Mathe"), .library)
        XCTAssertEqual(kind("lernen zuhause"), .home)
        XCTAssertEqual(kind("Lernen zuhause Statistik"), .home)
    }

    func testLecturesAndRoomsAreIgnored() {
        XCTAssertEqual(kind("Vorlesung Analysis II"), .other)
        XCTAssertEqual(kind("VL Statistik Hörsaal 3"), .other)
        XCTAssertEqual(kind("Übung Lineare Algebra"), .other)
        XCTAssertEqual(kind("Seminar Raum 2.14 Bibliothek"), .other)
        XCTAssertEqual(kind("Lernen"), .other)
        XCTAssertEqual(kind("Zahnarzt"), .other)
    }

    func testGym() {
        XCTAssertEqual(kind("Gym"), .gym)
        XCTAssertEqual(kind("Krafttraining Beine"), .gym)
        XCTAssertEqual(kind("Trainingsplan"), .gym)
        // A short word must stand alone.
        XCTAssertEqual(kind("Gymnasium Elternabend"), .other)
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
        let block = PlanClock.event(.library, "lernen bib", from: PlanClock.at(10, 15), to: PlanClock.at(11, 45))
        let context = DayPlanner.resolve(input(at: PlanClock.at(10, 30), events: [block]))
        XCTAssertEqual(context.situation, .library)
        XCTAssertEqual(context.source, .calendar)
        XCTAssertFalse(context.calendarOverruled)

        let atHome = PlanClock.event(.home, "lernen zuhause", from: PlanClock.at(14), to: PlanClock.at(16))
        XCTAssertEqual(DayPlanner.resolve(input(at: PlanClock.at(15), events: [atHome])).situation, .home)
    }

    func testLocationBeatsTheCalendar() {
        // The calendar says library, the phone is at home.
        let block = PlanClock.event(.library, "lernen bib", from: PlanClock.at(10, 15), to: PlanClock.at(11, 45))
        let context = DayPlanner.resolve(input(at: PlanClock.at(10, 30), events: [block], place: .home))
        XCTAssertEqual(context.situation, .home)
        XCTAssertEqual(context.source, .location)
        XCTAssertTrue(context.calendarOverruled)

        // Calendar and location agree: nothing is overruled.
        let agree = DayPlanner.resolve(input(at: PlanClock.at(10, 30), events: [block], place: .library))
        XCTAssertEqual(agree.situation, .library)
        XCTAssertFalse(agree.calendarOverruled)
    }

    func testSavedPlaceThatThePhoneIsNotAtOverrulesTheCalendar() {
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

        // "lernen zuhause" in the calendar, home is saved, the phone is not there.
        let atHome = PlanClock.event(.home, "lernen zuhause", from: PlanClock.at(14), to: PlanClock.at(16))
        var away = input(at: PlanClock.at(15), events: [atHome])
        away.savedKinds = [.home]
        away.locationKnown = true
        XCTAssertEqual(DayPlanner.resolve(away).situation, .elsewhere)
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
        let lecture = PlanClock.event(.other, "Vorlesung", from: PlanClock.at(10), to: PlanClock.at(11))
        let context = DayPlanner.resolve(input(at: PlanClock.at(10, 30), events: [lecture]))
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

    func testPainMeansOnlyGentleWork() {
        var sore = context(.home)
        sore.recentPain = 7
        XCTAssertTrue(sore.needsGentle)
        for index in 0..<8 {
            let advice = Advisor.advice(for: sore, hour: 14, index: index)
            XCTAssertNotEqual(advice?.routine, RoutineCatalog.backStrength)
            XCTAssertNotEqual(advice?.routine, RoutineCatalog.nerveGlide)
            XCTAssertEqual(advice?.note, .gentle)
        }
        let pick = Advisor.homePick(for: sore, hour: 14)
        XCTAssertEqual(pick.note, .gentle)
        XCTAssertTrue([RoutineCatalog.spineFlow, RoutineCatalog.downshift].contains(pick.routine))

        var fine = context(.home)
        fine.recentPain = 3
        XCTAssertFalse(fine.needsGentle)
    }

    func testCalmHomePickRotatesByWhatWasDoneLongestAgo() {
        let home = context(.home)
        // Nothing done yet: the first candidate.
        XCTAssertEqual(Advisor.homePick(for: home, hour: 14).routine, RoutineCatalog.spineFlow)
        XCTAssertEqual(Advisor.homePick(for: home, hour: 14).note, .homeRelaxed)

        // Spine flow yesterday, the other two never: strength comes first.
        var last: [String: Date] = [RoutineCatalog.spineFlow.id: PlanClock.at(18, day: 11)]
        XCTAssertEqual(Advisor.homePick(for: home, hour: 14, lastDone: last).routine, RoutineCatalog.backStrength)

        // Strength done this morning: it is once a day, so nerve glides.
        last[RoutineCatalog.backStrength.id] = PlanClock.at(9)
        let done: Set<String> = [RoutineCatalog.backStrength.id]
        XCTAssertEqual(Advisor.homePick(for: home, hour: 14, doneToday: done, lastDone: last).routine, RoutineCatalog.nerveGlide)

        // In the evening it is the breathing routine.
        XCTAssertEqual(Advisor.homePick(for: home, hour: 21).routine, RoutineCatalog.downshift)
        XCTAssertEqual(Advisor.homePick(for: home, hour: 21, doneToday: [RoutineCatalog.downshift.id]).routine, RoutineCatalog.spineFlow)
    }

    func testNoStandUpInTheFirstHalfHourOfSitting() {
        for index in 0..<8 {
            let early = Advisor.advice(for: context(.library), hour: 14, index: index, sittingFor: 20 * 60)
            XCTAssertNotEqual(early?.routine, RoutineCatalog.standUp, "check-in \(index)")
        }
        // Index 1 is the stand-up slot of the library cycle. Sat down 20
        // minutes ago: the next routine of the cycle takes it.
        XCTAssertEqual(
            Advisor.advice(for: context(.library), hour: 14, index: 1, sittingFor: 20 * 60)?.routine,
            RoutineCatalog.deskMobility
        )
        // From half an hour on, and when nobody knows, it is offered.
        XCTAssertEqual(
            Advisor.advice(for: context(.library), hour: 14, index: 1, sittingFor: 30 * 60)?.routine,
            RoutineCatalog.standUp
        )
        XCTAssertEqual(Advisor.advice(for: context(.library), hour: 14, index: 1)?.routine, RoutineCatalog.standUp)
    }

    func testLectureIsOnlyAnAnnouncement() {
        XCTAssertEqual(Advisor.advice(for: context(.uni), hour: 10, index: 0)?.isAnnouncement, true)
        XCTAssertEqual(Advisor.advice(for: context(.library), hour: 10, index: 0)?.isAnnouncement, false)
        XCTAssertEqual(Advisor.advice(for: context(.home), hour: 10, index: 0)?.isAnnouncement, false)

        // No routine is named, in the notification or by Theo.
        let lecture = Advice(routine: RoutineCatalog.lectureReset, note: .lecture)
        XCTAssertEqual(AdviceText.title(lecture, language: .de), "Kurzer Check-in")
        XCTAssertEqual(
            AdviceText.body(lecture, trigger: .interval(minutes: 30), language: .de),
            "Wieder 30 Minuten um. Kurz aufrichten und durchatmen."
        )
        XCTAssertEqual(
            AdviceText.spoken(lecture, trigger: .timer(minutes: 45), language: .en),
            "45 minutes without a break. Sit tall for a moment and take a breath."
        )
    }

    func testAvailability() {
        XCTAssertTrue(Advisor.isAvailable(RoutineCatalog.spineFlow, in: .home))
        XCTAssertFalse(Advisor.isAvailable(RoutineCatalog.spineFlow, in: .library))
        XCTAssertTrue(Advisor.isAvailable(RoutineCatalog.eyeReset, in: .library))
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

    func testNoStandUpBeforeHalfAnHourOfSitting() {
        let start = PlanClock.at(9)
        var query = input(start: start, minutes: 10)
        query.seatedSince = start
        let slots = CheckInPlanner.plan(query)
        let byTime = Dictionary(uniqueKeysWithValues: slots.map { ($0.date, $0.advice.routine) })
        // 09:20 is the stand-up slot of the cycle, after 20 minutes of sitting.
        XCTAssertEqual(byTime[PlanClock.at(9, 20)], RoutineCatalog.deskMobility)
        // 09:40 is the next one, and by then it has been 40 minutes.
        XCTAssertEqual(byTime[PlanClock.at(9, 40)], RoutineCatalog.standUp)
    }

    func testCalendarShapesLaterSlots() {
        let start = PlanClock.at(9)
        var query = input(start: start)
        query.events = [
            PlanClock.event(.home, "lernen zuhause", from: PlanClock.at(10, 15), to: PlanClock.at(11, 45)),
            PlanClock.event(.gym, "Gym", from: PlanClock.at(12), to: PlanClock.at(13, 30))
        ]
        let slots = CheckInPlanner.plan(query)
        let byTime = Dictionary(uniqueKeysWithValues: slots.map { ($0.date, $0.advice) })

        // 09:30 and 10:00 are before the study block: nothing for the floor.
        XCTAssertEqual(byTime[PlanClock.at(9, 30)]?.routine.homeOnly, false)
        XCTAssertEqual(byTime[PlanClock.at(10)]?.routine.homeOnly, false)
        // 11:00 falls into "lernen zuhause" and is the strength slot of the
        // home cycle, but the gym is an hour away: mobility instead.
        XCTAssertEqual(byTime[PlanClock.at(11)]?.note, .gymSoon(minutes: 60))
        XCTAssertNotEqual(byTime[PlanClock.at(11)]?.routine, RoutineCatalog.backStrength)
        // 12:00 is the start of the gym entry, 12:30 and 13:00 are inside it: silence.
        XCTAssertNil(byTime[PlanClock.at(12)])
        XCTAssertNil(byTime[PlanClock.at(12, 30)])
        XCTAssertNil(byTime[PlanClock.at(13)])
    }

    func testHomeOverridesALibraryBlockInTheCalendar() {
        let start = PlanClock.at(10)
        var query = input(start: start)
        query.placeKind = .home
        query.events = [PlanClock.event(.library, "lernen bib", from: PlanClock.at(10, 15), to: PlanClock.at(11, 45))]
        let slots = CheckInPlanner.plan(query)
        XCTAssertTrue(slots.contains { $0.advice.routine.homeOnly })
        XCTAssertFalse(slots.contains { $0.advice.note == .library })
    }

    func testTextsNameTheRoutine() {
        let advice = Advice(routine: RoutineCatalog.spineFlow, note: .home)
        XCTAssertEqual(AdviceText.title(advice, language: .de), "Zeit für: Wirbelsäulen-Flow · 3 min")
        let body = AdviceText.body(advice, trigger: .timer(minutes: 60), language: .de)
        XCTAssertEqual(body, "60 Minuten ohne Pause. Du bist zuhause, also gern auf dem Boden.")
        let spoken = AdviceText.spoken(advice, trigger: .timer(minutes: 60), language: .en)
        XCTAssertTrue(spoken.contains("a spine mobility flow on the floor"))

        // Study mode: no claim about how long the user has been sitting.
        let reminder = AdviceText.body(advice, trigger: .interval(minutes: 30), language: .en)
        XCTAssertEqual(reminder, "Another 30 minutes gone. You're home, so use the floor if you like.")
        XCTAssertEqual(CheckInPlanner.roundedMinutes(from: PlanClock.at(9), to: PlanClock.at(10, 2), atLeast: 30), 60)
        XCTAssertEqual(CheckInPlanner.roundedMinutes(from: PlanClock.at(9), to: PlanClock.at(9, 10), atLeast: 30), 30)
    }
}

final class SittingMathTests: XCTestCase {
    private func span(_ source: SittingSpan.Source, _ start: Date, _ end: Date?) -> SittingSpan {
        SittingSpan(source: source, placeID: nil, start: start, end: end, lastSeen: nil)
    }

    private func seconds(_ spans: [SittingSpan], now: Date, day: Date? = nil) -> TimeInterval {
        SittingMath.seconds(spans, on: day ?? now, now: now, calendar: PlanClock.calendar)
    }

    func testLibraryAndStudyAddUp() {
        let spans = [
            span(.library, PlanClock.at(9), PlanClock.at(12)),
            span(.study, PlanClock.at(15), PlanClock.at(16, 30))
        ]
        XCTAssertEqual(seconds(spans, now: PlanClock.at(20)), 4.5 * 3600)
    }

    func testOverlapCountsOnce() {
        // Study mode switched on inside a library stay.
        let spans = [
            span(.library, PlanClock.at(9), PlanClock.at(12)),
            span(.study, PlanClock.at(10), PlanClock.at(11)),
            span(.study, PlanClock.at(11, 30), PlanClock.at(13))
        ]
        XCTAssertEqual(seconds(spans, now: PlanClock.at(20)), 4 * 3600)
    }

    func testOpenSpanCountsUntilNowAndIsCapped() {
        let open = [span(.study, PlanClock.at(14), nil)]
        XCTAssertEqual(seconds(open, now: PlanClock.at(15, 30)), 1.5 * 3600)
        // Forgotten: study mode stops counting after six hours.
        XCTAssertEqual(seconds(open, now: PlanClock.at(23)), 6 * 3600)
    }

    func testSpanAcrossMidnightIsSplitByDay() {
        let late = [span(.study, PlanClock.at(22), PlanClock.at(1, day: 13))]
        XCTAssertEqual(seconds(late, now: PlanClock.at(8, day: 13), day: PlanClock.at(12)), 2 * 3600)
        XCTAssertEqual(seconds(late, now: PlanClock.at(8, day: 13), day: PlanClock.at(12, day: 13)), 3600)
    }

    func testNothingMeansZero() {
        XCTAssertEqual(seconds([], now: PlanClock.at(12)), 0)
        XCTAssertEqual(seconds([span(.study, PlanClock.at(10), PlanClock.at(10))], now: PlanClock.at(12)), 0)
    }

    func testDayKeysAndBedtime() {
        let calendar = PlanClock.calendar
        XCTAssertEqual(DayKey.key(for: PlanClock.at(9), calendar: calendar), "2026-11-12")
        // Half past midnight still belongs to the evening before.
        XCTAssertEqual(DayKey.key(for: DayKey.eveningDay(for: PlanClock.at(0, 30, day: 13), calendar: calendar), calendar: calendar), "2026-11-12")
        XCTAssertEqual(DayKey.key(for: DayKey.eveningDay(for: PlanClock.at(22), calendar: calendar), calendar: calendar), "2026-11-12")
        XCTAssertEqual(DayKey.bedtime(on: PlanClock.at(9), minutes: 22 * 60 + 30, calendar: calendar), PlanClock.at(22, 30))
        // A bedtime of 00:30 fires on the next calendar day.
        XCTAssertEqual(DayKey.bedtime(on: PlanClock.at(9), minutes: 30, calendar: calendar), PlanClock.at(0, 30, day: 13))
    }
}

final class AmbientPlannerTests: XCTestCase {
    private func input(at now: Date) -> AmbientPlanner.Input {
        var input = AmbientPlanner.Input()
        input.now = now
        input.calendar = PlanClock.calendar
        input.language = .de
        return input
    }

    func testPainQuestionEveryEveningExceptAnsweredDays() {
        var query = input(at: PlanClock.at(10))
        query.homeSuggestionsOn = false
        query.painDays = ["2026-11-13"]
        let planned = AmbientPlanner.plan(query)
        XCTAssertEqual(planned.count, 6)
        XCTAssertEqual(planned.first?.date, PlanClock.at(22, 30))
        XCTAssertEqual(planned.first?.painDay, "2026-11-12")
        XCTAssertEqual(planned.first?.id, "pain-0")
        XCTAssertFalse(planned.contains { $0.painDay == "2026-11-13" })
        XCTAssertTrue(planned.allSatisfy { $0.routineID == nil })
    }

    func testTonightIsSkippedOnceBedtimeHasPassed() {
        var query = input(at: PlanClock.at(23))
        query.homeSuggestionsOn = false
        let planned = AmbientPlanner.plan(query)
        XCTAssertEqual(planned.first?.painDay, "2026-11-13")

        query.painCheckOn = false
        XCTAssertTrue(AmbientPlanner.plan(query).isEmpty)
    }

    func testCalmSuggestionsOnlyAtHomeAndOutsideStudyMode() {
        var query = input(at: PlanClock.at(10))
        query.painCheckOn = false
        XCTAssertTrue(AmbientPlanner.plan(query).isEmpty)

        query.isHome = true
        let today = AmbientPlanner.plan(query)
        XCTAssertEqual(today.map { $0.id }, ["home-day-0", "home-eve-0"])
        XCTAssertEqual(today[0].date, PlanClock.at(16))
        XCTAssertEqual(today[0].routineID, RoutineCatalog.spineFlow.id)
        XCTAssertEqual(today[1].date, PlanClock.at(21, 30))
        XCTAssertEqual(today[1].routineID, RoutineCatalog.downshift.id)
        XCTAssertTrue(today[0].body.contains("Wenn du magst"))
        XCTAssertTrue(today[0].body.hasSuffix("Ganz in Ruhe, kein Muss."))

        query.studyModeOn = true
        XCTAssertTrue(AmbientPlanner.plan(query).isEmpty)
    }

    func testTomorrowIsOnlyPlannedWhenLeavingIsNoticed() {
        var query = input(at: PlanClock.at(10))
        query.painCheckOn = false
        query.isHome = true
        query.leavingIsNoticed = true
        let planned = AmbientPlanner.plan(query)
        XCTAssertEqual(planned.map { $0.id }, ["home-day-0", "home-eve-0", "home-day-1", "home-eve-1"])
        XCTAssertEqual(planned[2].date, PlanClock.at(16, day: 13))
    }

    func testDaytimeSuggestionFollowsTheArrival() {
        var query = input(at: PlanClock.at(18, 5))
        query.painCheckOn = false
        query.isHome = true
        query.homeArrivalAt = PlanClock.at(18)
        let planned = AmbientPlanner.plan(query)
        XCTAssertEqual(planned.first?.id, "home-day-0")
        XCTAssertEqual(planned.first?.date, PlanClock.at(18, 30))

        // Home too late: the daytime one would crowd the evening one.
        query.now = PlanClock.at(20, 5)
        query.homeArrivalAt = PlanClock.at(20)
        XCTAssertEqual(AmbientPlanner.plan(query).map { $0.id }, ["home-eve-0"])
    }

    func testOnlyOneDaytimeSuggestionADayAndNoneRightAfterARoutine() {
        var query = input(at: PlanClock.at(17))
        query.painCheckOn = false
        query.isHome = true
        // Today's four o'clock one has already gone out.
        query.plannedDaySlot = PlanClock.at(16)
        query.homeArrivalAt = PlanClock.at(16, 50)
        XCTAssertEqual(AmbientPlanner.plan(query).map { $0.id }, ["home-eve-0"])

        // A floor routine at 15:00 makes the 16:00 offer pointless.
        var done = input(at: PlanClock.at(15, 10))
        done.painCheckOn = false
        done.isHome = true
        done.lastHomeRoutineAt = PlanClock.at(15)
        XCTAssertEqual(AmbientPlanner.plan(done).map { $0.id }, ["home-eve-0"])

        // And one at 20:30 makes the evening offer pointless.
        var evening = input(at: PlanClock.at(20, 40))
        evening.painCheckOn = false
        evening.isHome = true
        evening.lastHomeRoutineAt = PlanClock.at(20, 30)
        XCTAssertTrue(AmbientPlanner.plan(evening).isEmpty)
    }

    func testPainMakesTheSuggestionGentle() {
        var query = input(at: PlanClock.at(10))
        query.painCheckOn = false
        query.isHome = true
        query.recentPain = 8
        let planned = AmbientPlanner.plan(query)
        XCTAssertEqual(planned.first?.routineID, RoutineCatalog.spineFlow.id)
        XCTAssertEqual(planned.first?.body.contains("Wegen der Schmerzen heute nur Sanftes."), true)
    }
}
