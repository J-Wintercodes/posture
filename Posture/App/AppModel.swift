import Foundation
import Observation
import UserNotifications

/// Composition root. Builds the services once, wires them together and owns
/// what happens on arrival at a saved place.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let store: SessionStore
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
    /// False when iOS will not show the check-in notifications.
    private(set) var notificationsOn = true

    @ObservationIgnored private let router = NotificationRouter()
    @ObservationIgnored private var lastArrivalHintAt = Date.distantPast
    /// The place an auto-started tracking session belongs to.
    @ObservationIgnored private var autoTrackingPlaceID: String?

    private let snoozeKey = "posture.autostart.snoozedUntil"

    init() {
        let settings = SettingsStore()
        let store = SessionStore()
        let headphones = HeadphoneMotionService()
        let phone = PhoneContextService()
        let power = LocationAndPowerGuard()
        let coach = AudioCoachService()
        let calendar = CalendarService()
        let day = DayCoach(settings: settings, store: store, calendar: calendar, power: power, coach: coach)
        self.settings = settings
        self.store = store
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
        power.onPlacesChange = { [weak self] in self?.day.refresh() }
        power.onPowerStateChange = { [weak self] in
            self?.session.powerStateChanged()
            self?.attemptAutoTracking(arrived: false)
        }
        headphones.onConnectionChange = { [weak self] in self?.attemptAutoTracking(arrived: false) }
        calendar.onChange = { [weak self] in self?.day.refresh() }

        router.onOpenRoutine = { [weak self] id in
            Task { @MainActor in self?.openFromNotification(routineID: id) }
        }
        router.onCheckInShown = { [weak self] in
            Task { @MainActor in self?.day.refresh() }
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
        day.refresh()
        attemptAutoTracking(arrived: false)
        Task { notificationsOn = await Notifier.isAuthorized() }
    }

    /// The profile was closed: calendar switch, word lists or the interval
    /// may have changed.
    func settingsChanged() {
        day.applySettings()
    }

    // MARK: Tracking sessions

    func startManualSession() {
        if !session.isRunning {
            autoTrackingPlaceID = nil
            session.start(trigger: .manual)
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

    // MARK: Reminders only

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
        snooze()
    }

    // MARK: Routines

    /// Opens a routine if it may be done here. The floor work is for home.
    func open(_ routine: Routine) {
        guard Advisor.isAvailable(routine, in: day.context.situation) else { return }
        syncCoach()
        activeRoutine = routine
    }

    /// A check-in notification was tapped. If its routine no longer fits the
    /// place (it was planned for home and the phone has left), open what
    /// fits now instead.
    private func openFromNotification(routineID: String) {
        day.refresh()
        let wanted = RoutineCatalog.routine(id: routineID)
        if let wanted, Advisor.isAvailable(wanted, in: day.context.situation) {
            open(wanted)
        } else if let fallback = day.due?.advice.routine ?? day.suggestion?.routine {
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

    private func arrived(at id: String) {
        day.refresh()
        let config = settings.value
        guard config.onboardingDone else { return }
        switch config.arrivalAction {
        case .nothing:
            break
        case .reminders:
            attemptAutoReminders(placeID: id)
        case .tracking:
            attemptAutoTracking(arrived: true)
        }
    }

    private func left(_ id: String) {
        let hadReminders = day.mode == .light
        day.placeLeft(id)
        let name = place(withID: id)?.displayName ?? "your place"
        if hadReminders, day.mode == .off {
            Notifier.post(
                title: "Reminders stopped",
                body: "You left \(name).",
                id: "auto-stop",
                sound: false
            )
        }
        // A tracking session that started on arrival ends on leaving, so the
        // audio engine and the AirPods stream do not run on for nothing.
        if session.isRunning, session.isAutoStarted, autoTrackingPlaceID == id {
            session.end()
            showLive = false
            autoTrackingPlaceID = nil
            Notifier.post(
                title: "Posture session ended",
                body: "You left \(name).",
                id: "auto-stop",
                sound: false
            )
        }
    }

    private func attemptAutoReminders(placeID: String) {
        guard let place = place(withID: placeID), place.kind.startsOnArrival else { return }
        guard day.mode == .off, !session.isRunning, !isSnoozed else { return }
        day.startLight(auto: true)
        Notifier.post(
            title: "Reminders on",
            body: "You're at \(place.displayName). A check-in every \(settings.value.checkInMinutes) minutes. Nothing else is running.",
            id: "auto-start",
            sound: false
        )
    }

    /// Evaluated on arrival at a library, when AirPods connect, when the
    /// power state changes and when the app comes to the foreground. Only
    /// does something if the user picked "Tracking" for arrivals.
    func attemptAutoTracking(arrived: Bool) {
        let config = settings.value
        guard config.onboardingDone, config.arrivalAction == .tracking else { return }
        let place = config.places.first {
            $0.kind.startsOnArrival && power.insidePlaceIDs.contains($0.id.uuidString)
        }

        var input = AutoStartPolicy.Input()
        input.sessionActive = session.isRunning
        input.isLowPowerMode = power.isLowPowerMode
        input.batteryLevel = power.batteryLevel
        input.isCharging = power.isCharging
        input.minBattery = config.minBatteryForAutoStart
        input.placeName = place?.displayName
        input.headphonesConnected = headphones.isConnected
        input.snoozedUntil = snoozedUntil

        switch AutoStartPolicy.decide(input) {
        case .start(let placeName):
            if session.start(trigger: .auto(placeName: placeName)) {
                autoTrackingPlaceID = place?.id.uuidString
                Notifier.post(
                    title: "Posture session started",
                    body: "Tracking quietly at \(placeName). Keep your phone locked and carry on.",
                    id: "auto-start",
                    sound: false
                )
            }
        case .blocked(.noHeadphones) where arrived:
            // The app is only awake for a few seconds after a geofence
            // event. Leave a hint the user can act on.
            guard Date().timeIntervalSince(lastArrivalHintAt) > 30 * 60 else { return }
            lastArrivalHintAt = Date()
            Notifier.post(
                title: "You're at \(input.placeName ?? "the library")",
                body: "Put in your AirPods and tap to start a quiet posture session.",
                id: "arrival-hint"
            )
        case .blocked:
            break
        }
    }

    // MARK: Snooze

    /// Kept across launches: a relaunch at the library counts as an arrival.
    private var snoozedUntil: Date? {
        let stamp = UserDefaults.standard.double(forKey: snoozeKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    private var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return Date() < until
    }

    private func snooze(minutes: Double = 60) {
        UserDefaults.standard.set(Date().addingTimeInterval(minutes * 60).timeIntervalSince1970, forKey: snoozeKey)
    }
}
