import Foundation

/// The quiet notifications that need no running session: the pain question
/// before bed, and at most two calm routine suggestions a day while the user
/// is at home. Pure Swift: it only lays out what should be scheduled.
enum AmbientPlanner {
    struct Input {
        var now = Date()
        var calendar = Calendar.current
        var language: CoachLanguage = .en

        var painCheckOn = true
        /// Minutes since midnight of the bedtime question.
        var bedMinutes = 22 * 60 + 30
        /// Day keys that already have a pain answer.
        var painDays: Set<String> = []

        var homeSuggestionsOn = true
        var isHome = false
        /// True when leaving home will wake the app (location "Always"), so
        /// suggestions for tomorrow can be planned and taken back in time.
        var leavingIsNoticed = false
        /// Study mode already checks in on its own timer.
        var studyModeOn = false
        /// Last real arrival at home (a geofence crossing).
        var homeArrivalAt: Date?
        /// When a floor routine was last finished.
        var lastHomeRoutineAt: Date?
        /// A daytime suggestion that was planned earlier. If it is from
        /// today and already in the past, there is no second one today.
        var plannedDaySlot: Date?
        var doneToday: Set<String> = []
        var lastDone: [String: Date] = [:]
        var events: [PlannedEvent] = []
        var recentPain: Int?
    }

    struct Planned: Equatable {
        var id: String
        var date: Date
        var title: String
        var body: String
        var routineID: String?
        var painDay: String?
    }

    static let painDays = 7
    static let painIDs: [String] = (0..<painDays).map { "pain-\($0)" }
    static let homeIDs: [String] = ["home-day-0", "home-day-1", "home-eve-0", "home-eve-1"]
    static var allIDs: [String] { painIDs + homeIDs }

    /// Hour of the daytime suggestion at home.
    static let dayHour = 16

    static func plan(_ input: Input) -> [Planned] {
        painChecks(input) + homeSuggestions(input)
    }

    // MARK: Pain question

    static func painChecks(_ input: Input) -> [Planned] {
        guard input.painCheckOn else { return [] }
        let de = input.language == .de
        let today = input.calendar.startOfDay(for: input.now)
        var planned: [Planned] = []
        for offset in 0..<painDays {
            guard let day = input.calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let key = DayKey.key(for: day, calendar: input.calendar)
            let fire = DayKey.bedtime(on: day, minutes: input.bedMinutes, calendar: input.calendar)
            guard fire > input.now, !input.painDays.contains(key) else { continue }
            planned.append(Planned(
                id: painIDs[offset],
                date: fire,
                title: de ? "Wie geht es deinem Rücken?" : "How is your back tonight?",
                body: de
                    ? "Hattest du heute Schmerzen? Gedrückt halten für eine schnelle Antwort, antippen für die Skala von 0 bis 10."
                    : "Any pain today? Press and hold for a quick answer, tap for the scale from 0 to 10.",
                routineID: nil,
                painDay: key
            ))
        }
        return planned
    }

    // MARK: Calm suggestions at home

    static func homeSuggestions(_ input: Input) -> [Planned] {
        guard input.homeSuggestionsOn, input.isHome, !input.studyModeOn else { return [] }
        let today = input.calendar.startOfDay(for: input.now)
        var planned: [Planned] = []
        // Tomorrow is only planned when leaving home is noticed, so that a
        // suggestion for home cannot arrive somewhere else.
        let days = input.leavingIsNoticed ? 2 : 1
        for offset in 0..<days {
            guard let day = input.calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let evening = DayKey.bedtime(on: day, minutes: input.bedMinutes, calendar: input.calendar)
                .addingTimeInterval(-60 * 60)

            if let slot = daySlot(input, day: day, isToday: offset == 0, evening: evening) {
                planned.append(suggestion(input, id: "home-day-\(offset)", at: slot, evening: false, today: offset == 0))
            }
            if evening > input.now, !recentlyDone(input, before: evening, hours: 2) {
                planned.append(suggestion(input, id: "home-eve-\(offset)", at: evening, evening: true, today: offset == 0))
            }
        }
        return planned
    }

    /// The daytime suggestion: four in the afternoon, or half an hour after
    /// coming home if that is later. Never close to the evening one, and not
    /// if a floor routine was done in the three hours before.
    static func daySlot(_ input: Input, day: Date, isToday: Bool, evening: Date) -> Date? {
        guard var slot = input.calendar.date(bySettingHour: dayHour, minute: 0, second: 0, of: day) else { return nil }
        if isToday {
            if let earlier = input.plannedDaySlot,
               input.calendar.isDate(earlier, inSameDayAs: input.now), earlier <= input.now {
                return nil
            }
            if let arrival = input.homeArrivalAt, input.calendar.isDate(arrival, inSameDayAs: input.now) {
                slot = max(slot, arrival.addingTimeInterval(30 * 60))
            }
        }
        guard slot > input.now, slot <= evening.addingTimeInterval(-90 * 60) else { return nil }
        if isToday, recentlyDone(input, before: slot, hours: 3) { return nil }
        return slot
    }

    private static func recentlyDone(_ input: Input, before date: Date, hours: Double) -> Bool {
        guard let last = input.lastHomeRoutineAt else { return false }
        return last <= date && date.timeIntervalSince(last) < hours * 3600
    }

    private static func suggestion(_ input: Input, id: String, at date: Date, evening: Bool, today: Bool) -> Planned {
        var query = DayPlanner.Input()
        query.now = date
        query.events = input.events
        query.placeKind = .home
        query.recentPain = input.recentPain
        let context = DayPlanner.resolve(query)
        let done = today ? input.doneToday : []
        let hour = evening ? 21 : input.calendar.component(.hour, from: date)
        let advice = Advisor.homePick(for: context, hour: hour, doneToday: done, lastDone: input.lastDone)

        let language = input.language
        let de = language == .de
        let routine = advice.routine
        let title: String
        if evening {
            title = de ? "Langsam runterfahren" : "Time to wind down"
        } else {
            title = de ? "Etwas für Rücken und Nerven?" : "Something for back and nerves?"
        }
        let offer = de
            ? "Wenn du magst: \(routine.name.de), \(routine.durationWords(.de))."
            : "If you like: \(routine.name.en), \(routine.durationWords(.en))."
        let hint = AdviceText.hint(advice, language: language)
        let calm = de ? "Ganz in Ruhe, kein Muss." : "No rush, only if you feel like it."
        let parts = hint.isEmpty || hint == calm ? [offer, calm] : [offer, hint, calm]
        return Planned(
            id: id,
            date: date,
            title: title,
            body: parts.joined(separator: " "),
            routineID: routine.id,
            painDay: nil
        )
    }
}
