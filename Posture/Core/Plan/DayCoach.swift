import Foundation
import Observation

/// Knows what the day looks like (calendar plus location) and says what is
/// needed after a stretch of sitting.
///
/// It runs in two ways:
///
/// - **Reminders only** (`light`): no sensors, no audio, nothing running.
///   The check-ins are handed to iOS as scheduled notifications and the app
///   can sleep or be closed. This is the mode that costs no battery.
/// - **Tracking**: an AirPods session is live anyway, so the check-ins are
///   decided on the spot and Theo says them.
@MainActor
@Observable
final class DayCoach {
    enum Mode: String, Codable {
        case off, light, tracking
    }

    /// A check-in that has fired and is waiting for the user.
    struct Due: Equatable {
        var advice: Advice
        var trigger: CheckInTrigger
        var at: Date
    }

    private(set) var mode: Mode = .off
    private(set) var context = DayContext()
    /// What fits right now. Nil in the gym.
    private(set) var suggestion: Advice?
    private(set) var due: Due?
    /// The check-in interval counts from here.
    private(set) var anchor: Date?
    private(set) var lightEndsAt: Date?
    private(set) var lightIsAuto = false

    @ObservationIgnored private(set) var lightPlaceID: String?
    @ObservationIgnored private var sittingSince = Date()
    @ObservationIgnored private var rotation = 0

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let calendar: CalendarService
    @ObservationIgnored private let power: LocationAndPowerGuard
    @ObservationIgnored private let coach: AudioCoachService
    @ObservationIgnored private let defaults: UserDefaults

    /// Reminders stop on their own this long after the last sign of life
    /// (start, or a finished routine).
    static let lightSpan: TimeInterval = 4 * 3600
    /// A fired check-in is offered this long.
    static let dueLifetime: TimeInterval = 20 * 60
    static let checkInIDs: [String] = (0..<12).map { "checkin-\($0)" }

    private let lightKey = "posture.light.v1"

    private struct LightState: Codable {
        var anchor: Date
        var sittingSince: Date
        var endsAt: Date
        var rotation: Int
        var auto: Bool
        var placeID: String?
    }

    init(settings: SettingsStore, store: SessionStore, calendar: CalendarService,
         power: LocationAndPowerGuard, coach: AudioCoachService, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.store = store
        self.calendar = calendar
        self.power = power
        self.coach = coach
        self.defaults = defaults
        restoreLight()
    }

    // MARK: Reading the day

    var intervalSeconds: TimeInterval {
        CheckInPlanner.interval(minutes: settings.value.checkInMinutes)
    }

    var nextCheckInAt: Date? {
        guard mode != .off, let anchor else { return nil }
        let step = intervalSeconds
        let passed = max(0, (Date().timeIntervalSince(anchor) / step).rounded(.down))
        return anchor.addingTimeInterval((passed + 1) * step)
    }

    /// The saved place the phone is at right now.
    var currentPlace: FocusPlace? {
        settings.value.places.first { power.insidePlaceIDs.contains($0.id.uuidString) }
    }

    /// Pushes the calendar settings (on/off, word lists) to the calendar
    /// reader and reads everything again.
    func applySettings() {
        let config = settings.value
        calendar.configure(
            enabled: config.calendarEnabled,
            uniKeywords: config.uniKeywords,
            gymKeywords: config.gymKeywords
        )
        refresh()
    }

    /// Works out the situation again. Called when the app opens, when the
    /// calendar or the place changes and after a routine.
    func refresh(now: Date = Date()) {
        calendar.reloadIfOlder(than: 300)
        if mode == .light { catchUpLight(now: now) }
        if let fired = due, now.timeIntervalSince(fired.at) > Self.dueLifetime { due = nil }

        let next = DayPlanner.resolve(plannerInput(now: now))
        if next != context { context = next }
        let advice = Advisor.advice(for: next, hour: hour(of: now), index: rotation, doneToday: store.routinesDone())
        if advice != suggestion { suggestion = advice }

        if mode == .light { scheduleLight(now: now) }
    }

    private func plannerInput(now: Date) -> DayPlanner.Input {
        let places = settings.value.places
        let here = currentPlace
        var input = DayPlanner.Input()
        input.now = now
        input.events = calendar.events
        input.placeKind = here?.kind
        input.placeName = here?.displayName
        input.savedKinds = Set(places.map { $0.kind })
        input.locationKnown = power.isLocationTrusted
        return input
    }

    private func hour(of date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    // MARK: Reminders only

    func startLight(auto: Bool = false, now: Date = Date()) {
        guard mode == .off else { return }
        mode = .light
        anchor = now
        sittingSince = now
        rotation = 0
        due = nil
        lightEndsAt = now.addingTimeInterval(Self.lightSpan)
        lightIsAuto = auto
        // Leaving the place where the reminders were started ends them.
        lightPlaceID = currentPlace?.id.uuidString
        persistLight()
        refresh(now: now)
    }

    func stopLight() {
        guard mode == .light else { return }
        mode = .off
        anchor = nil
        lightEndsAt = nil
        due = nil
        lightIsAuto = false
        lightPlaceID = nil
        Notifier.cancel(ids: Self.checkInIDs)
        defaults.removeObject(forKey: lightKey)
    }

    /// The check-ins fired as notifications while the app was asleep. Bring
    /// the counters up to date and offer the latest one if it is fresh.
    private func catchUpLight(now: Date) {
        guard mode == .light, let start = anchor, let endsAt = lightEndsAt else { return }
        if now > endsAt {
            stopLight()
            return
        }
        let step = intervalSeconds
        let passed = Int((now.timeIntervalSince(start) / step).rounded(.down))
        guard passed > 0 else { return }
        let lastAt = start.addingTimeInterval(Double(passed) * step)
        let index = rotation + passed - 1
        rotation += passed
        anchor = lastAt
        if now.timeIntervalSince(lastAt) < Self.dueLifetime {
            let situation = DayPlanner.resolve(plannerInput(now: now))
            if let advice = Advisor.advice(for: situation, hour: hour(of: now), index: index, doneToday: store.routinesDone()) {
                due = Due(advice: advice, trigger: .interval(minutes: settings.value.checkInMinutes), at: lastAt)
            }
        }
        persistLight()
    }

    /// Hands the coming check-ins to iOS. A request with an id that is
    /// already pending replaces it, so only the unused ids are cancelled.
    private func scheduleLight(now: Date) {
        guard mode == .light, let anchor, let endsAt = lightEndsAt else { return }
        let config = settings.value
        let here = currentPlace
        var input = CheckInPlanner.Input()
        input.now = now
        input.anchor = anchor
        input.endsAt = endsAt
        input.intervalMinutes = config.checkInMinutes
        input.rotation = rotation
        input.events = calendar.events
        input.placeKind = here?.kind
        input.placeName = here?.displayName
        input.savedKinds = Set(config.places.map { $0.kind })
        input.locationKnown = power.isLocationTrusted
        input.doneToday = store.routinesDone()
        input.maxSlots = Self.checkInIDs.count

        let slots = CheckInPlanner.plan(input)
        let language = config.coachLanguage
        for (index, slot) in slots.enumerated() {
            var body = AdviceText.body(slot.advice, trigger: .interval(minutes: config.checkInMinutes), language: language)
            if slot.isLast {
                body += language == .de
                    ? " Letzte Erinnerung für jetzt. Öffne Posture, um weiterzumachen."
                    : " Last reminder for now. Open Posture to keep going."
            }
            Notifier.schedule(
                title: AdviceText.title(slot.advice, language: language),
                body: body,
                id: Self.checkInIDs[index],
                at: slot.date,
                routineID: slot.advice.routine.id
            )
        }
        let unused = Array(Self.checkInIDs.dropFirst(slots.count))
        if !unused.isEmpty { Notifier.cancel(ids: unused) }
    }

    private func persistLight() {
        guard mode == .light, let anchor, let endsAt = lightEndsAt else { return }
        let state = LightState(
            anchor: anchor, sittingSince: sittingSince, endsAt: endsAt,
            rotation: rotation, auto: lightIsAuto, placeID: lightPlaceID
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: lightKey)
        }
    }

    /// The app may have been closed while reminders were on.
    private func restoreLight() {
        guard let data = defaults.data(forKey: lightKey),
              let state = try? JSONDecoder().decode(LightState.self, from: data) else { return }
        guard state.endsAt > Date() else {
            defaults.removeObject(forKey: lightKey)
            return
        }
        mode = .light
        anchor = state.anchor
        sittingSince = state.sittingSince
        lightEndsAt = state.endsAt
        rotation = state.rotation
        lightIsAuto = state.auto
        lightPlaceID = state.placeID
    }

    // MARK: Tracking session

    func trackingStarted(now: Date = Date()) {
        if mode == .light { stopLight() }
        mode = .tracking
        anchor = now
        sittingSince = now
        rotation = 0
        due = nil
        refresh(now: now)
    }

    func trackingEnded() {
        guard mode == .tracking else { return }
        mode = .off
        anchor = nil
        due = nil
        Notifier.clearDelivered(ids: [Notifier.liveCheckInID])
    }

    /// Called once a second by the running session.
    func tick(now: Date = Date()) {
        guard mode == .tracking, let anchor else { return }
        if let fired = due, now.timeIntervalSince(fired.at) > Self.dueLifetime { due = nil }
        guard now.timeIntervalSince(anchor) >= intervalSeconds else { return }
        let minutes = CheckInPlanner.roundedMinutes(from: sittingSince, to: now, atLeast: settings.value.checkInMinutes)
        fire(.timer(minutes: minutes), now: now)
    }

    /// The posture engine saw fatigue. That is a check-in too, and the timer
    /// starts over so the two do not pile up.
    func fatigue(_ reason: BreakReason, now: Date = Date()) {
        guard mode == .tracking else { return }
        fire(.fatigue(reason), now: now)
    }

    /// The user got up and came back: the sitting clock starts again.
    func noteBreak(now: Date = Date()) {
        guard mode == .tracking else { return }
        anchor = now
        sittingSince = now
        due = nil
    }

    private func fire(_ trigger: CheckInTrigger, now: Date) {
        let index = rotation
        rotation += 1
        anchor = now
        refresh(now: now)
        guard let advice = Advisor.advice(for: context, hour: hour(of: now), index: index, doneToday: store.routinesDone()) else {
            return
        }
        due = Due(advice: advice, trigger: trigger, at: now)
        let language = settings.value.coachLanguage
        coach.deliver(.checkIn(
            spoken: AdviceText.spoken(advice, trigger: trigger, language: language),
            title: AdviceText.title(advice, language: language),
            body: AdviceText.body(advice, trigger: trigger, language: language),
            routineID: advice.routine.id
        ))
    }

    // MARK: Shared

    /// A routine was finished (suggested or picked by hand).
    func routineCompleted(_ routine: Routine, now: Date = Date()) {
        let wasSuggested = due == nil && suggestion?.routine.id == routine.id
        due = nil
        if wasSuggested { rotation += 1 }
        Notifier.clearDelivered(ids: Self.checkInIDs + [Notifier.liveCheckInID])
        if mode != .off {
            anchor = now
            sittingSince = now
        }
        if mode == .light {
            lightEndsAt = now.addingTimeInterval(Self.lightSpan)
            persistLight()
        }
        refresh(now: now)
    }

    func dismissDue() {
        due = nil
        Notifier.clearDelivered(ids: [Notifier.liveCheckInID])
    }

    /// The phone left a saved place.
    func placeLeft(_ id: String) {
        if mode == .light, lightPlaceID == id { stopLight() }
        refresh()
    }
}
