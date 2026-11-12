import Foundation

/// What the coach suggests, and the one-line reason that goes with it.
struct Advice: Equatable, Sendable {
    enum Note: Equatable, Sendable {
        case plain, home, library, lecture
        case gymSoon(minutes: Int)
        case afterGym, evening
    }

    var routine: Routine
    var note: Note
}

/// Why a check-in fires.
enum CheckInTrigger: Equatable, Sendable {
    /// Tracking: so many minutes of sitting without a break. The session
    /// knows this, because it sees the user get up.
    case timer(minutes: Int)
    /// Reminders only: the interval is over. Without sensors nobody knows
    /// whether there was a break, so nothing is claimed about it.
    case interval(minutes: Int)
    /// The posture engine saw fatigue during a tracked session.
    case fatigue(BreakReason)
}

/// Picks what is needed for the situation. A pure function of the day
/// context, the hour and how many check-ins there have been.
enum Advisor {
    /// Nil means "say nothing" (in the gym).
    static func advice(for context: DayContext, hour: Int, index: Int, doneToday: Set<String> = []) -> Advice? {
        let cycle: [Routine]
        let note: Advice.Note

        switch context.situation {
        case .gym:
            return nil

        case .uni:
            // In a lecture: only what nobody notices.
            return Advice(routine: RoutineCatalog.lectureReset, note: .lecture)

        case .home:
            if let minutes = context.gymInMinutes {
                // Mobility is a fine warm-up. Strength is saved for the gym,
                // and nothing that makes sleepy.
                cycle = [RoutineCatalog.eyeReset, RoutineCatalog.spineFlow, RoutineCatalog.standUp]
                note = .gymSoon(minutes: minutes)
            } else if context.afterGym {
                cycle = [RoutineCatalog.eyeReset, RoutineCatalog.downshift, RoutineCatalog.standUp, RoutineCatalog.spineFlow]
                note = .afterGym
            } else if hour >= 20 || hour < 5 {
                cycle = [RoutineCatalog.eyeReset, RoutineCatalog.downshift, RoutineCatalog.standUp, RoutineCatalog.spineFlow]
                note = .evening
            } else {
                cycle = [
                    RoutineCatalog.eyeReset, RoutineCatalog.spineFlow, RoutineCatalog.standUp,
                    RoutineCatalog.backStrength, RoutineCatalog.eyeReset, RoutineCatalog.nerveGlide
                ]
                note = .home
            }

        case .library, .elsewhere:
            if let minutes = context.gymInMinutes {
                cycle = [RoutineCatalog.eyeReset, RoutineCatalog.standUp]
                note = .gymSoon(minutes: minutes)
            } else {
                cycle = [RoutineCatalog.eyeReset, RoutineCatalog.standUp, RoutineCatalog.deskMobility, RoutineCatalog.standUp]
                note = context.situation == .library ? .library : .plain
            }
        }

        return Advice(routine: pick(from: cycle, index: index, doneToday: doneToday), note: note)
    }

    /// Walks the cycle from `index` and skips once-a-day routines that are
    /// already done.
    static func pick(from cycle: [Routine], index: Int, doneToday: Set<String>) -> Routine {
        guard !cycle.isEmpty else { return RoutineCatalog.eyeReset }
        let start = ((index % cycle.count) + cycle.count) % cycle.count
        for offset in 0..<cycle.count {
            let candidate = cycle[(start + offset) % cycle.count]
            if candidate.oncePerDay, doneToday.contains(candidate.id) { continue }
            return candidate
        }
        return RoutineCatalog.eyeReset
    }

    /// Whether a routine may be started in this situation. The floor work is
    /// for home only.
    static func isAvailable(_ routine: Routine, in situation: Situation) -> Bool {
        !routine.homeOnly || situation == .home
    }
}

/// The words around a check-in: notification title and body, and what Theo
/// says in the AirPods.
enum AdviceText {
    /// "Time for: Eye + Posture Reset · 30s"
    static func title(_ advice: Advice, language: CoachLanguage) -> String {
        let lead = language == .de ? "Zeit für" : "Time for"
        return "\(lead): \(advice.routine.name.text(language)) · \(advice.routine.durationLabel)"
    }

    static func body(_ advice: Advice, trigger: CheckInTrigger, language: CoachLanguage) -> String {
        join([lead(trigger, language: language), hint(advice, language: language)])
    }

    static func spoken(_ advice: Advice, trigger: CheckInTrigger, language: CoachLanguage) -> String {
        let routine = advice.routine
        let call = language == .de
            ? "Zeit für \(routine.spokenName.de), \(routine.durationWords(.de))."
            : "Time for \(routine.spokenName.en), \(routine.durationWords(.en))."
        return join([lead(trigger, language: language), call, hint(advice, language: language)])
    }

    static func lead(_ trigger: CheckInTrigger, language: CoachLanguage) -> String {
        let de = language == .de
        switch trigger {
        case .timer(let minutes):
            return de ? "\(minutes) Minuten ohne Pause." : "\(minutes) minutes without a break."
        case .interval(let minutes):
            return de ? "Wieder \(minutes) Minuten um." : "Another \(minutes) minutes gone."
        case .fatigue(.fatigueTrend):
            return de ? "Deine Haltung lässt seit ein paar Minuten nach." : "Your posture has been fading for a few minutes."
        case .fatigue(.repeatedSlouch):
            return de ? "Du sackst immer wieder ein." : "You keep sinking."
        case .fatigue(.longSit):
            return de ? "Du sitzt schon lange." : "You've been sitting a long while."
        }
    }

    /// Why this one, in one short sentence. Empty when there is nothing to add.
    static func hint(_ advice: Advice, language: CoachLanguage) -> String {
        let de = language == .de
        switch advice.note {
        case .plain:
            return ""
        case .home:
            guard advice.routine.homeOnly else { return "" }
            return de ? "Du bist zuhause, also ab auf den Boden." : "You're home, so use the floor."
        case .library:
            if advice.routine.id == RoutineCatalog.standUp.id {
                return de ? "Kurz raus aus dem Lesesaal." : "Step out of the reading room for a moment."
            }
            return de ? "Geht leise am Platz." : "Quiet enough for your seat."
        case .lecture:
            return de ? "Unauffällig, im Sitzen." : "Invisible, in your seat."
        case .gymSoon(let minutes):
            return de
                ? "Gym in \(minutes) Minuten: nur locker machen, die Kraft sparst du dir fürs Training."
                : "Gym in \(minutes) minutes: keep it light and save your strength for training."
        case .afterGym:
            return de ? "Nach dem Training: runterfahren statt nachlegen." : "After training: wind down instead of adding more."
        case .evening:
            return de ? "Abends lieber runterfahren." : "It's evening: time to wind down."
        }
    }

    private static func join(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Lays out the check-ins of a reminders-only session ahead of time, so they
/// can be handed to iOS as scheduled notifications and the app can sleep.
enum CheckInPlanner {
    struct Slot: Equatable {
        var date: Date
        var advice: Advice
        var isLast: Bool
    }

    struct Input {
        var now = Date()
        /// Check-ins fall on anchor + 1, 2, 3 ... intervals.
        var anchor = Date()
        /// Nothing is planned beyond this.
        var endsAt = Date()
        var intervalMinutes = 30
        /// Rotation index of the first check-in after the anchor.
        var rotation = 0
        var events: [PlannedEvent] = []
        var placeKind: PlaceKind?
        var placeName: String?
        var savedKinds: Set<PlaceKind> = []
        var locationKnown = false
        var doneToday: Set<String> = []
        var calendar = Calendar.current
        var maxSlots = 10
    }

    static func interval(minutes: Int) -> TimeInterval {
        Double(max(5, minutes)) * 60
    }

    /// The place is assumed to stay what it is now: leaving it wakes the app
    /// (geofence), and the plan is made again. The calendar is read for the
    /// time of each slot, so a lecture later today already gets the quiet
    /// routine and a gym entry gets silence.
    static func plan(_ input: Input) -> [Slot] {
        let step = interval(minutes: input.intervalMinutes)
        var slots: [Slot] = []
        for k in 1...200 {
            if slots.count >= input.maxSlots { break }
            let date = input.anchor.addingTimeInterval(Double(k) * step)
            if date > input.endsAt { break }
            if date <= input.now { continue }

            var query = DayPlanner.Input()
            query.now = date
            query.events = input.events
            query.placeKind = input.placeKind
            query.placeName = input.placeName
            query.savedKinds = input.savedKinds
            query.locationKnown = input.locationKnown
            let context = DayPlanner.resolve(query)
            let hour = input.calendar.component(.hour, from: date)
            guard let advice = Advisor.advice(for: context, hour: hour, index: input.rotation + k - 1, doneToday: input.doneToday) else {
                continue
            }
            slots.append(Slot(date: date, advice: advice, isLast: false))
        }
        if !slots.isEmpty {
            slots[slots.count - 1].isLast = true
        }
        return slots
    }

    /// Sitting time for the tracked session, rounded to five minutes.
    static func roundedMinutes(from start: Date, to end: Date, atLeast minimum: Int) -> Int {
        let minutes = end.timeIntervalSince(start) / 60
        let rounded = Int((minutes / 5).rounded()) * 5
        return max(rounded, max(5, minimum))
    }
}
