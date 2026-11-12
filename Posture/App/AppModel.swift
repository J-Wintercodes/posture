import Foundation
import Observation

/// Composition root. Builds the services once, wires them together and owns
/// the auto-start decision.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let store: SessionStore
    let headphones: HeadphoneMotionService
    let phone: PhoneContextService
    let power: LocationAndPowerGuard
    let coach: AudioCoachService
    let session: SessionManager

    var showLive = false
    var showReset = false
    var showProfile = false
    var showCalibration = false

    @ObservationIgnored private var autoStartSnoozedUntil: Date?
    @ObservationIgnored private var lastArrivalHintAt = Date.distantPast

    init() {
        let settings = SettingsStore()
        let store = SessionStore()
        let headphones = HeadphoneMotionService()
        let phone = PhoneContextService()
        let power = LocationAndPowerGuard()
        let coach = AudioCoachService()
        self.settings = settings
        self.store = store
        self.headphones = headphones
        self.phone = phone
        self.power = power
        self.coach = coach
        self.session = SessionManager(
            settings: settings, store: store, headphones: headphones,
            phone: phone, power: power, coach: coach
        )

        power.onArrival = { [weak self] _ in self?.attemptAutoStart(arrived: true) }
        power.onPowerStateChange = { [weak self] in
            self?.session.powerStateChanged()
            self?.attemptAutoStart(arrived: false)
        }
        headphones.onConnectionChange = { [weak self] in self?.attemptAutoStart(arrived: false) }
        power.sync(places: settings.value.places)
    }

    // MARK: Sessions

    func startManualSession() {
        if !session.isRunning {
            session.start(trigger: .manual)
        }
        showLive = true
    }

    func endSession() {
        let wasAuto = session.isAutoStarted
        session.end()
        showLive = false
        // If the user ends an auto-started session, do not start the next
        // one behind their back a minute later.
        if wasAuto {
            autoStartSnoozedUntil = Date().addingTimeInterval(60 * 60)
        }
    }

    func appBecameActive() {
        attemptAutoStart(arrived: false)
    }

    // MARK: Places

    func savePlaces(_ places: [FocusPlace]) {
        settings.update { $0.places = places }
        power.sync(places: places)
    }

    private var currentPlaceName: String? {
        settings.value.places.first { power.insidePlaceIDs.contains($0.id.uuidString) }?.name
    }

    // MARK: Auto-start

    /// Evaluated on arrival at a focus place, when AirPods connect, when the
    /// power state changes and when the app comes to the foreground.
    func attemptAutoStart(arrived: Bool) {
        let config = settings.value
        guard config.onboardingDone else { return }

        var input = AutoStartPolicy.Input()
        input.enabled = config.autoStartEnabled
        input.sessionActive = session.isRunning
        input.isLowPowerMode = power.isLowPowerMode
        input.batteryLevel = power.batteryLevel
        input.isCharging = power.isCharging
        input.minBattery = config.minBatteryForAutoStart
        input.workStartMinutes = config.workStartMinutes
        input.workEndMinutes = config.workEndMinutes
        input.workDays = config.workDays
        input.placeName = currentPlaceName
        input.headphonesConnected = headphones.isConnected
        input.snoozedUntil = autoStartSnoozedUntil

        switch AutoStartPolicy.decide(input) {
        case .start(let placeName):
            if session.start(trigger: .auto(placeName: placeName)) {
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
                title: "You're at \(input.placeName ?? "your focus place")",
                body: "Put in your AirPods and tap to start a quiet posture session.",
                id: "arrival-hint"
            )
        case .blocked:
            break
        }
    }
}
