import Foundation
import Observation
import UserNotifications

/// The pain question on screen. Carries the day it is about.
struct PainPrompt: Identifiable, Equatable {
    var dayKey: String
    var id: String { dayKey }
}

/// Composition root. Builds the services once, wires them together and owns
/// what happens on arrival at a saved place.
@MainActor
@Observable
final class AppModel {
    /// One instance for the screens and for Siri. An App Intent can launch
    /// the app in the background, without a window, and needs the same model.
    static let shared = AppModel()

    let settings: SettingsStore
    let store: SessionStore
    let log: DayLogStore
    let headphones: HeadphoneMotionService
    let phone: PhoneContextService
    let power: LocationAndPowerGuard
    let coach: AudioCoachService
    let calendar: CalendarService
    let day: DayCoach
    let session: SessionManager

    var showLive = false
    var showProfile = false
    var showCalibration = false
    /// The routine on screen, if any.
    var activeRoutine: Routine?
    /// The pain scale on screen, if any.
    var painPrompt: PainPrompt?
    /// False when iOS will not show the check-in notifications.
    private(set) var notificationsOn = true

    @ObservationIgnored private let router = NotificationRouter()
    @ObservationIgnored private var lastArrivalHintAt = Date.distantPast
    /// The place an auto-started tracking session belongs to.
    @ObservationIgnored private var autoTrackingPlaceID: String?
    /// The session at a library closed itself after waiting too long for the
    /// AirPods. A battery reading alone does not set it up again.
    @ObservationIgnored private var gaveUpWaiting = false

    /// What made the app look whether study mode should set itself up.
    enum AutoReason {
        case arrival, opened, headphones, power
    }

    private let snoozeKey = "posture.autostart.snoozedUntil"

    init() {
        let settings = SettingsStore()
        let store = SessionStore()
        let log = DayLogStore()
        let headphones = HeadphoneMotionService()
        let phone = PhoneContextService()
        let power = LocationAndPowerGuard()
        let coach = AudioCoachService()
        let calendar = CalendarService()
        let day = DayCoach(settings: settings, store: store, log: log, calendar: calendar, power: power, coach: coach)
        self.settings = settings
        self.store = store
        self.log = log
        self.headphones = headphones
        self.phone = phone
        self.power = power
        self.coach = coach
        self.calendar = calendar
        self.day = day
        self.session = SessionManager(
            settings: settings, store: store, headphones: headphones,
            phone: phone, power: power, coach: coach, day: day
        )

        power.onArrival = { [weak self] id in self?.arrived(at: id) }
        power.onDeparture = { [weak self] id in self?.left(id) }
        power.onEnter = { [weak self] id in self?.entered(id) }
        power.onOutside = { [weak self] id in self?.log.close(.library, placeID: id) }
        power.onPlacesChange = { [weak self] in self?.day.refresh() }
        power.onPowerStateChange = { [weak self] in
            self?.session.powerStateChanged()
            self?.attemptAutoStudy(.power)
        }
        headphones.onConnectionChange = { [weak self] in self?.attemptAutoStudy(.headphones) }
        session.onGaveUp = { [weak self] in
            self?.gaveUpWaiting = true
            self?.autoTrackingPlaceID = nil
        }
        calendar.onChange = { [weak self] in self?.day.refresh() }

        router.onOpenRoutine = { [weak self] id in
            Task { @MainActor in self?.openFromNotification(routineID: id) }
        }
        router.onCheckInShown = { [weak self] in
            Task { @MainActor in self?.day.refresh() }
        }
        router.onPainAnswer = { [weak self] level, dayKey in
            Task { @MainActor in self?.logPain(level, dayKey: dayKey) }
        }
        router.onOpenPainCheck = { [weak self] dayKey in
            Task { @MainActor in self?.painPrompt = PainPrompt(dayKey: dayKey) }
        }
        UNUserNotificationCenter.current().delegate = router

        power.sync(places: settings.value.places)
        day.applySettings()
    }

    // MARK: App lifecycle

    func appBecameActive() {
        // The location check: ask the geofences again and take one fix.
        power.refreshStates()
        power.verifyPosition(places: settings.value.places)
        calendar.reload()
        day.extendLight()
        day.refresh()
        attemptAutoStudy(.opened)
        Task { notificationsOn = await Notifier.isAuthorized() }
    }

    /// The profile was closed: calendar switch, word lists, the interval,
    /// the bedtime or the automatic at the library may have changed.
    func settingsChanged() {
        day.applySettings()
        for id in power.insidePlaceIDs { countLibraryStay(id) }
        if !settings.value.autoStudy, session.isRunning, session.isAutoStarted, autoTrackingPlaceID != nil {
            // The automatic was switched off while it was running.
            session.end()
            showLive = false
            autoTrackingPlaceID = nil
        } else {
            attemptAutoStudy(.opened)
        }
    }

    // MARK: Tracking sessions

    func startManualSession() {
        if !session.isRunning {
            // The user wants it now: an earlier "stop" no longer holds.
            clearSnooze()
            // At a library the session belongs to the place, exactly as if
            // it had set itself up: it waits for the AirPods and ends when
            // the phone leaves.
            if !startAutoStudy(explicit: true) {
                autoTrackingPlaceID = nil
                session.start(trigger: .manual)
            }
        }
        showLive = true
    }

    func endSession() {
        session.end()
        showLive = false
        autoTrackingPlaceID = nil
        // The user said stop: nothing starts on its own for the next hour,
        // even if the app is relaunched at the library.
        snooze()
    }

    // MARK: Study mode

    func startReminders() {
        guard !session.isRunning else { return }
        day.startLight(auto: false)
        Task {
            // Shows the system prompt only if it was never answered.
            _ = await Notifier.requestAuthorization()
            notificationsOn = await Notifier.isAuthorized()
        }
    }

    func stopReminders() {
        day.stopLight()
        day.refresh()
        snooze()
    }

    /// "Hey Siri, mach Lernmodus an". Returns what Siri says back.
    func startStudyMode() -> String {
        let de = settings.value.coachLanguage == .de
        let ready = de
            ? "Lernmodus ist bereit. Er läuft, sobald du mit AirPods sitzt."
            : "Study mode is ready. It runs as soon as you sit with your AirPods in."
        if session.isRunning {
            if session.isAutoStarted { return ready }
            return de ? "Das Tracking läuft schon und zählt als Sitzen." : "Tracking is already running and counts as sitting."
        }
        if day.mode == .light {
            return de ? "Der Lernmodus läuft schon." : "Study mode is already on."
        }
        // At a library it is the automatic that is switched back on. If the
        // battery guard is in the way, the check-ins without sensors below
        // are what is left.
        clearSnooze()
        if startAutoStudy(explicit: true) { return ready }
        day.startLight(auto: false)
        Task { notificationsOn = await Notifier.isAuthorized() }
        let minutes = settings.value.checkInMinutes
        return de
            ? "Lernmodus ist an. Ich melde mich alle \(minutes) Minuten."
            : "Study mode is on. I'll check in every \(minutes) minutes."
    }

    /// "Hey Siri, mach Lernmodus aus". Returns what Siri says back.
    func stopStudyMode() -> String {
        let de = settings.value.coachLanguage == .de
        if session.isRunning {
            endSession()
        } else if day.mode == .light {
            stopReminders()
        } else {
            return de ? "Der Lernmodus war nicht an." : "Study mode was not on."
        }
        let sat = Self.spokenDuration(log.sittingSeconds(on: Date()), de: de)
        return de ? "Lernmodus ist aus. Heute gesessen: \(sat)." : "Study mode is off. Sat today: \(sat)."
    }

    /// "2 Stunden 15 Minuten", for Siri to read out.
    static func spokenDuration(_ seconds: TimeInterval, de: Bool) -> String {
        let total = Int((max(0, seconds) / 60).rounded())
        let hours = total / 60
        let minutes = total % 60
        var parts: [String] = []
        if hours > 0 {
            if de {
                parts.append(hours == 1 ? "eine Stunde" : "\(hours) Stunden")
            } else {
                parts.append(hours == 1 ? "one hour" : "\(hours) hours")
            }
        }
        if minutes > 0 || hours == 0 {
            if de {
                parts.append(minutes == 1 ? "eine Minute" : "\(minutes) Minuten")
            } else {
                parts.append(minutes == 1 ? "one minute" : "\(minutes) minutes")
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: Pain

    /// The day an answer given right now belongs to.
    var tonightKey: String {
        DayKey.key(for: DayKey.eveningDay(for: Date()))
    }

    func askAboutPain() {
        painPrompt = PainPrompt(dayKey: tonightKey)
    }

    func logPain(_ level: Int, dayKey: String) {
        log.setPain(level, dayKey: dayKey)
        day.painAnswered()
    }

    // MARK: Routines

    /// Opens a routine if it may be done here. The floor work is for home.
    func open(_ routine: Routine) {
        guard Advisor.isAvailable(routine, in: day.context.situation) else { return }
        syncCoach()
        activeRoutine = routine
    }

    /// A check-in or suggestion was tapped. If its routine no longer fits
    /// the place (it was planned for home and the phone has left), open what
    /// fits now instead.
    private func openFromNotification(routineID: String) {
        day.refresh()
        let wanted = RoutineCatalog.routine(id: routineID)
        // In a lecture the suggestion is only an announcement, not a routine.
        let offered = day.suggestion.flatMap { $0.isAnnouncement ? nil : $0.routine }
        if let wanted, Advisor.isAvailable(wanted, in: day.context.situation) {
            open(wanted)
        } else if let fallback = day.due?.advice.routine ?? offered {
            open(fallback)
        } else {
            open(RoutineCatalog.eyeReset)
        }
    }

    func finished(_ routine: Routine) {
        store.logRoutine(routine.id)
        day.routineCompleted(routine)
    }

    /// Hands language, voice and feedback mode to Theo outside a session.
    func syncCoach() {
        let config = settings.value
        coach.mode = config.feedback
        coach.language = config.coachLanguage
        coach.voiceID = config.coachVoiceID
    }

    // MARK: Places

    func savePlaces(_ places: [FocusPlace]) {
        settings.update { $0.places = places }
        power.sync(places: places)
        day.refresh()
    }

    /// A new name does not touch the geofences, which go by id.
    func renamePlace(id: UUID, to name: String) {
        settings.update { value in
            if let index = value.places.firstIndex(where: { $0.id == id }) {
                value.places[index].name = name
            }
        }
    }

    private func place(withID id: String) -> FocusPlace? {
        settings.value.places.first { $0.id.uuidString == id }
    }

    // MARK: Arrival and departure

    /// The phone is at a saved place: either it just crossed in, or the app
    /// just found out.
    private func arrived(at id: String) {
        countLibraryStay(id)
        day.refresh()
        attemptAutoStudy(.arrival)
    }

    /// With the automatic on, sitting in a library is counted from what the
    /// AirPods see: it starts when the user sits and stops when they get up
    /// or take them out. Without it the whole stay counts, but only with
    /// location "Always": otherwise nobody would notice the leaving, and the
    /// count would run on.
    private func countLibraryStay(_ id: String) {
        guard let place = place(withID: id), place.kind == .library else { return }
        if settings.value.autoStudy {
            log.close(.library, placeID: id)
        } else if power.hasAlwaysAccess {
            log.open(.library, placeID: id)
        }
    }

    /// A real geofence crossing into a place.
    private func entered(_ id: String) {
        if place(withID: id)?.kind == .home {
            day.noteHomeArrival()
        }
    }

    private func left(_ id: String) {
        log.close(.library, placeID: id)
        let hadStudyMode = day.mode == .light
        day.placeLeft(id)
        let name = place(withID: id)?.displayName ?? "your place"
        if hadStudyMode, day.mode == .off {
            Notifier.post(
                title: "Study mode off",
                body: "You left \(name).",
                id: "auto-stop",
                sound: false
            )
        }
        // The session that belongs to this place ends on leaving, so the
        // audio engine and the AirPods stream do not run on for nothing.
        if session.isRunning, session.isAutoStarted, autoTrackingPlaceID == id {
            session.end()
            showLive = false
            autoTrackingPlaceID = nil
            Notifier.post(
                title: "Study mode off",
                body: "You left \(name).",
                id: "auto-stop",
                sound: false
            )
        }
        gaveUpWaiting = false
    }

    // MARK: Study mode on its own

    /// The library or focus place the phone is at, if study mode may run on
    /// its own there.
    private var autoPlace: FocusPlace? {
        let config = settings.value
        guard config.onboardingDone, config.autoStudy else { return nil }
        return config.places.first {
            $0.kind.startsOnArrival && power.insidePlaceIDs.contains($0.id.uuidString)
        }
    }

    /// `explicit`: the user asked for it right now, so study mode that was
    /// started by hand is replaced instead of being left alone.
    private func autoStartDecision(explicit: Bool = false) -> AutoStartPolicy.Decision {
        let config = settings.value
        var input = AutoStartPolicy.Input()
        input.enabled = config.onboardingDone && config.autoStudy
        input.sessionActive = session.isRunning || (!explicit && day.mode == .light)
        input.isLowPowerMode = power.isLowPowerMode
        input.batteryLevel = power.batteryLevel
        input.isCharging = power.isCharging
        input.minBattery = config.minBatteryForAutoStart
        input.placeName = autoPlace?.displayName
        input.snoozedUntil = snoozedUntil
        return AutoStartPolicy.decide(input)
    }

    /// Sets up the session that belongs to the library the phone is at. It
    /// waits there for the AirPods: study mode itself begins once the user
    /// sits with them in, pauses when they get up or take them out, and
    /// carries on when they are back.
    ///
    /// Nil when the rule says no, otherwise whether the session came up.
    private func setUpAutoStudy(explicit: Bool) -> Bool? {
        guard case .start(let placeName) = autoStartDecision(explicit: explicit),
              let place = autoPlace else { return nil }
        guard session.start(trigger: .auto(placeName: placeName)) else { return false }
        autoTrackingPlaceID = place.id.uuidString
        return true
    }

    private func startAutoStudy(explicit: Bool) -> Bool {
        setUpAutoStudy(explicit: explicit) == true
    }

    /// Evaluated on arrival at a library, when the app comes to the
    /// foreground, when AirPods connect and when the power state changes.
    func attemptAutoStudy(_ reason: AutoReason) {
        switch reason {
        case .arrival, .opened:
            gaveUpWaiting = false
        case .headphones:
            // The audio route changes for many reasons. Only AirPods going
            // in are one to set the session up again.
            guard headphones.isConnected else { return }
            gaveUpWaiting = false
        case .power:
            // The battery level changes all the time. It must not bring
            // back a session that just gave up waiting.
            guard !gaveUpWaiting else { return }
        }
        guard let started = setUpAutoStudy(explicit: false), let place = autoPlace else { return }
        if started {
            Notifier.post(
                title: "Study mode is ready",
                body: "You're at \(place.displayName). It starts once you sit down with your AirPods in, and pauses when you get up or take them out.",
                id: "auto-start",
                sound: false
            )
        } else {
            // The audio session could not be opened from the background, and
            // without it the app is asleep again in a few seconds. Leave a
            // hint the user can act on: opening the app sets it up.
            guard Date().timeIntervalSince(lastArrivalHintAt) > 30 * 60 else { return }
            lastArrivalHintAt = Date()
            Notifier.post(
                title: "You're at \(place.displayName)",
                body: "Tap to open Posture once, so study mode can start on its own.",
                id: "arrival-hint"
            )
        }
    }

    /// Why study mode is not set up although the phone is at a library. Nil
    /// when it is running, or when nothing is in the way.
    var autoStudyBlock: AutoStartPolicy.Block? {
        guard autoPlace != nil, !session.isRunning, day.mode != .light else { return nil }
        if case .blocked(let block) = autoStartDecision() { return block }
        return nil
    }

    // MARK: Snooze

    /// Kept across launches: a relaunch at the library counts as an arrival.
    var snoozedUntil: Date? {
        let stamp = UserDefaults.standard.double(forKey: snoozeKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    private func snooze(minutes: Double = 60) {
        UserDefaults.standard.set(Date().addingTimeInterval(minutes * 60).timeIntervalSince1970, forKey: snoozeKey)
    }

    private func clearSnooze() {
        UserDefaults.standard.removeObject(forKey: snoozeKey)
    }
}
