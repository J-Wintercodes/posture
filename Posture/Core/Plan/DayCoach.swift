import Foundation
import Observation

/// Knows what the day looks like (calendar plus location) and says what is
/// needed after a stretch of sitting.
///
/// It runs in two ways:
///
/// - **Study mode** (`light`): no sensors, no audio, nothing running. The
///   check-ins are handed to iOS as scheduled notifications and the app can
///   sleep or be closed. This is the mode that costs no battery. It can be
///   started with Siri.
/// - **Tracking**: an AirPods session is live anyway, so the check-ins are
///   decided on the spot and Theo says them.
///
/// Both count as sitting in the day log. Outside of them it plans the quiet
/// things: the pain question before bed and calm suggestions at home.
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
    /// When the user last got onto the chair: the start, coming back from a
    /// break, or the end of a routine that is done standing or on the floor.
    /// A seated routine does not move it. Standing up is not suggested in
    /// the first half hour after it.
    @ObservationIgnored private var seatedSince = Date()
    @ObservationIgnored private var rotation = 0
    @ObservationIgnored private var lastStudyTouchAt = Date.distantPast

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let log: DayLogStore
    @ObservationIgnored private let calendar: CalendarService
    @ObservationIgnored private let power: LocationAndPowerGuard
    @ObservationIgnored private let coach: AudioCoachService
    @ObservationIgnored private let defaults: UserDefaults

    /// Study mode stops on its own this long after the last sign of life
    /// (start, opening the app, or a finished routine).
    static let lightSpan: TimeInterval = 4 * 3600
    /// A fired check-in is offered this long.
    static let dueLifetime: TimeInterval = 20 * 60
    static let checkInIDs: [String] = (0..<12).map { "checkin-\($0)" }

    private let lightKey = "posture.light.v1"
    private let homeArrivalKey = "posture.home.arrivalAt"
    private let daySlotKey = "posture.home.daySlot"

    private struct LightState: Codable {
        var anchor: Date
        var sittingSince: Date
        var endsAt: Date
        var rotation: Int
        var auto: Bool
        var placeID: String?
        /// Optional: states saved before it existed lack it.
        var seatedSince: Date?
    }

    init(settings: SettingsStore, store: SessionStore, log: DayLogStore, calendar: CalendarService,
         power: LocationAndPowerGuard, coach: AudioCoachService, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.store = store
        self.log = log
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
            libraryKeywords: config.libraryKeywords,
            homeKeywords: config.homeKeywords,
            gymKeywords: config.gymKeywords
        )
        Notifier.registerCategories(language: config.coachLanguage)
        refresh()
    }

    /// Works out the situation again and lays out every scheduled
    /// notification anew. Called when the app opens, when the calendar or
    /// the place changes and after a routine.
    func refresh(now: Date = Date()) {
        calendar.reloadIfOlder(than: 300)
        log.expire(now: now)
        if mode == .light { catchUpLight(now: now) }
        if let fired = due, now.timeIntervalSince(fired.at) > Self.dueLifetime { due = nil }

        // Study mode started before the location was known (Siri launches
        // the app cold): tie it to the place as soon as there is one.
        if mode == .light, lightPlaceID == nil, let here = currentPlace {
            lightPlaceID = here.id.uuidString
            persistLight()
        }

        let next = DayPlanner.resolve(plannerInput(now: now))
        if next != context { context = next }
        let advice: Advice?
        if mode == .off, next.situation == .home {
            // Not in a session at home: no timer, just a calm offer.
            advice = Advisor.homePick(for: next, hour: hour(of: now), doneToday: store.routinesDone(), lastDone: lastDone())
        } else {
            advice = Advisor.advice(
                for: next, hour: hour(of: now), index: rotation,
                doneToday: store.routinesDone(), sittingFor: sittingFor(at: now)
            )
        }
        if advice != suggestion { suggestion = advice }

        if mode == .light { scheduleLight(now: now) }
        scheduleAmbient(now: now)
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
        input.recentPain = log.recentPain(now: now)
        return input
    }

    private func hour(of date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    /// How long the user will have been on the chair at `date`. Nil outside
    /// study mode and tracking, where nobody knows.
    private func sittingFor(at date: Date) -> TimeInterval? {
        mode == .off ? nil : date.timeIntervalSince(seatedSince)
    }

    /// Routine id to the last time it was finished.
    private func lastDone() -> [String: Date] {
        var result: [String: Date] = [:]
        for entry in store.routineLog {
            if let known = result[entry.id], known >= entry.date { continue }
            result[entry.id] = entry.date
        }
        return result
    }

    private func lastHomeRoutineAt() -> Date? {
        let homeIDs = Set(RoutineCatalog.all.filter { $0.homeOnly }.map { $0.id })
        return store.routineLog.filter { homeIDs.contains($0.id) }.map { $0.date }.max()
    }

    // MARK: Study mode (reminders only)

    func startLight(auto: Bool = false, now: Date = Date()) {
        guard mode == .off else { return }
        mode = .light
        anchor = now
        sittingSince = now
        seatedSince = now
        rotation = 0
        due = nil
        lightEndsAt = now.addingTimeInterval(Self.lightSpan)
        lightIsAuto = auto
        // Leaving the place where study mode was started ends it.
        lightPlaceID = currentPlace?.id.uuidString
        log.open(.study, at: now)
        persistLight()
        refresh(now: now)
    }

    /// `at` is when study mode really ended, which can be in the past when
    /// it ran out while the app was asleep.
    func stopLight(at end: Date = Date()) {
        guard mode == .light else { return }
        mode = .off
        anchor = nil
        lightEndsAt = nil
        due = nil
        lightIsAuto = false
        lightPlaceID = nil
        log.close(.study, at: end)
        Notifier.cancel(ids: Self.checkInIDs)
        defaults.removeObject(forKey: lightKey)
    }

    /// The user opened the app: a sign of life, so study mode gets its full
    /// span again.
    func extendLight(now: Date = Date()) {
        guard mode == .light, let endsAt = lightEndsAt, now <= endsAt else { return }
        lightEndsAt = now.addingTimeInterval(Self.lightSpan)
        persistLight()
    }

    /// The check-ins fired as notifications while the app was asleep. Bring
    /// the counters up to date and offer the latest one if it is fresh.
    private func catchUpLight(now: Date) {
        guard mode == .light, let start = anchor, let endsAt = lightEndsAt else { return }
        if now > endsAt {
            stopLight(at: endsAt)
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
            let advice = Advisor.advice(
                for: situation, hour: hour(of: now), index: index,
                doneToday: store.routinesDone(), sittingFor: sittingFor(at: lastAt)
            )
            // An announcement has nothing to start, so nothing is offered.
            if let advice, !advice.isAnnouncement {
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
        input.recentPain = log.recentPain(now: now)
        input.doneToday = store.routinesDone()
        input.seatedSince = seatedSince
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
                routineID: slot.advice.isAnnouncement ? nil : slot.advice.routine.id,
                checkIn: true
            )
        }
        let unused = Array(Self.checkInIDs.dropFirst(slots.count))
        if !unused.isEmpty { Notifier.cancel(ids: unused) }
    }

    private func persistLight() {
        guard mode == .light, let anchor, let endsAt = lightEndsAt else { return }
        let state = LightState(
            anchor: anchor, sittingSince: sittingSince, endsAt: endsAt,
            rotation: rotation, auto: lightIsAuto, placeID: lightPlaceID,
            seatedSince: seatedSince
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: lightKey)
        }
    }

    /// The app may have been closed while study mode was on.
    private func restoreLight() {
        guard let data = defaults.data(forKey: lightKey),
              let state = try? JSONDecoder().decode(LightState.self, from: data) else {
            // No study mode on record. A sitting span that is still open
            // belongs to a session the app did not survive.
            log.closeOrphanedStudy()
            return
        }
        guard state.endsAt > Date() else {
            defaults.removeObject(forKey: lightKey)
            log.close(.study, at: state.endsAt)
            return
        }
        mode = .light
        anchor = state.anchor
        sittingSince = state.sittingSince
        seatedSince = state.seatedSince ?? state.sittingSince
        lightEndsAt = state.endsAt
        rotation = state.rotation
        lightIsAuto = state.auto
        lightPlaceID = state.placeID
        log.open(.study, at: state.anchor)
    }

    // MARK: Tracking session

    func trackingStarted(now: Date = Date()) {
        if mode == .light { stopLight(at: now) }
        mode = .tracking
        anchor = now
        sittingSince = now
        seatedSince = now
        rotation = 0
        due = nil
        lastStudyTouchAt = now
        refresh(now: now)
    }

    /// The tracked session saw the user sit down (still for half a minute).
    /// Only from here on does it count as sitting: walking around with
    /// AirPods in does not.
    func sittingBegan(at date: Date) {
        guard mode == .tracking else { return }
        log.open(.study, at: date)
        log.touchStudy(at: Date())
    }

    /// The user walked off, or the AirPods came out.
    func sittingEnded(at date: Date) {
        guard mode == .tracking else { return }
        log.close(.study, at: date)
    }

    func trackingEnded(now: Date = Date()) {
        guard mode == .tracking else { return }
        mode = .off
        anchor = nil
        due = nil
        log.close(.study, at: now)
        Notifier.clearDelivered(ids: [Notifier.liveCheckInID])
        refresh(now: now)
    }

    /// Called once a second by the running session while the user sits.
    func tick(now: Date = Date()) {
        guard mode == .tracking, let anchor else { return }
        if let fired = due, now.timeIntervalSince(fired.at) > Self.dueLifetime { due = nil }
        guard now.timeIntervalSince(anchor) >= intervalSeconds else { return }
        let minutes = CheckInPlanner.roundedMinutes(from: sittingSince, to: now, atLeast: settings.value.checkInMinutes)
        fire(.timer(minutes: minutes), now: now)
    }

    /// Called once a second by the running session, sitting or not. Keeps
    /// the sitting span's "last seen" fresh, so a session the app does not
    /// survive still ends at the right time.
    func heartbeat(now: Date = Date()) {
        guard mode == .tracking, now.timeIntervalSince(lastStudyTouchAt) >= 60 else { return }
        lastStudyTouchAt = now
        log.touchStudy(at: now)
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
        seatedSince = now
        due = nil
    }

    private func fire(_ trigger: CheckInTrigger, now: Date) {
        let index = rotation
        rotation += 1
        anchor = now
        refresh(now: now)
        let picked = Advisor.advice(
            for: context, hour: hour(of: now), index: index,
            doneToday: store.routinesDone(), sittingFor: sittingFor(at: now)
        )
        guard let advice = picked else { return }
        // In a lecture it is only said, there is nothing to start.
        let announcement = advice.isAnnouncement
        due = announcement ? nil : Due(advice: advice, trigger: trigger, at: now)
        let language = settings.value.coachLanguage
        coach.deliver(.checkIn(
            spoken: AdviceText.spoken(advice, trigger: trigger, language: language),
            title: AdviceText.title(advice, language: language),
            body: AdviceText.body(advice, trigger: trigger, language: language),
            routineID: announcement ? nil : advice.routine.id
        ))
    }

    // MARK: Quiet notifications

    /// A real arrival at home (a geofence crossing, not "already there").
    func noteHomeArrival(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: homeArrivalKey)
    }

    private func storedDate(_ key: String) -> Date? {
        let stamp = defaults.double(forKey: key)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// The pain question before bed and the calm suggestions at home. Laid
    /// out for the coming days, so they arrive even if the app is not
    /// opened; leaving home takes the home ones back.
    private func scheduleAmbient(now: Date) {
        let config = settings.value
        var input = AmbientPlanner.Input()
        input.now = now
        input.language = config.coachLanguage
        input.painCheckOn = config.painCheckEnabled
        input.bedMinutes = config.bedMinutes
        input.painDays = Set(log.pain.keys)
        input.homeSuggestionsOn = config.homeSuggestionsEnabled
        input.isHome = context.situation == .home
        input.leavingIsNoticed = power.hasAlwaysAccess
        input.studyModeOn = mode != .off
        input.homeArrivalAt = storedDate(homeArrivalKey)
        input.lastHomeRoutineAt = lastHomeRoutineAt()
        input.plannedDaySlot = storedDate(daySlotKey)
        input.doneToday = store.routinesDone()
        input.lastDone = lastDone()
        input.events = calendar.events
        input.recentPain = log.recentPain(now: now)

        let planned = AmbientPlanner.plan(input)
        for item in planned {
            Notifier.schedule(
                title: item.title,
                body: item.body,
                id: item.id,
                at: item.date,
                routineID: item.routineID,
                painDay: item.painDay,
                sound: item.painDay != nil,
                wallClock: true
            )
        }
        let used = Set(planned.map { $0.id })
        let unused = AmbientPlanner.allIDs.filter { !used.contains($0) }
        if !unused.isEmpty { Notifier.cancel(ids: unused) }

        // Remember today's daytime suggestion, so there is only one a day.
        if let today = planned.first(where: { $0.id == "home-day-0" }) {
            defaults.set(today.date.timeIntervalSince1970, forKey: daySlotKey)
        } else if let stored = storedDate(daySlotKey), stored > now {
            // It was taken back before it fired (the user left home), so it
            // does not count as today's suggestion.
            defaults.removeObject(forKey: daySlotKey)
        }
    }

    // MARK: Shared

    /// A routine was finished (suggested or picked by hand).
    func routineCompleted(_ routine: Routine, now: Date = Date()) {
        let wasSuggested = due == nil && suggestion?.routine.id == routine.id
        due = nil
        if wasSuggested { rotation += 1 }
        Notifier.clearDelivered(ids: Self.checkInIDs + [Notifier.liveCheckInID] + AmbientPlanner.homeIDs)
        if mode != .off {
            anchor = now
            sittingSince = now
            // Only a routine that takes the user off the chair counts as
            // having got up.
            if routine.id == RoutineCatalog.standUp.id || routine.homeOnly {
                seatedSince = now
            }
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

    /// The pain question was answered.
    func painAnswered() {
        Notifier.clearDelivered(ids: AmbientPlanner.painIDs)
        refresh()
    }

    /// The phone left a saved place.
    func placeLeft(_ id: String) {
        if mode == .light, lightPlaceID == id { stopLight() }
        refresh()
    }
}
