import Foundation
import Observation
import UIKit

/// What the live screen draws. Published at most ~12 times a second while
/// the app is on screen, once a second behind the lock screen.
struct LiveSnapshot: Equatable {
    var pitch = 0.0
    var roll = 0.0
    var score = 100
    var zone: PostureZone = .aligned
    var context: PostureContext = .settling
    var load = 0.0
}

/// Owns a tracking session from start to end: feeds motion frames through
/// the engine, keeps the journal entry, hands coach cues to Theo and pauses
/// everything when the battery guard says so.
@MainActor
@Observable
final class SessionManager {
    enum PauseReason: Equatable {
        case lowPower, headphonesOut
    }

    enum Phase: Equatable {
        case idle
        case live
        case paused(PauseReason)
    }

    enum Trigger: Equatable {
        case manual
        case auto(placeName: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var snapshot = LiveSnapshot()
    /// Zone and context of the latest reading, on their own. `snapshot`
    /// changes with every frame; a view that only needs these two reads
    /// them here and is not redrawn twelve times a second.
    private(set) var zone: PostureZone = .aligned
    private(set) var context: PostureContext = .settling
    /// When the running session began. Nil while idle.
    private(set) var startedAt: Date?
    private(set) var elapsed: TimeInterval = 0
    private(set) var uprightSetAt: Date?
    private(set) var isAutoStarted = false
    /// True once the user has been still long enough to count as sitting.
    private(set) var isSitting = false
    /// The AirPod the motion currently comes from.
    private(set) var sensorSide: SensorSide = .unknown

    var isRunning: Bool { phase != .idle }

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let headphones: HeadphoneMotionService
    @ObservationIgnored private let phone: PhoneContextService
    @ObservationIgnored private let power: LocationAndPowerGuard
    @ObservationIgnored private let coach: AudioCoachService
    @ObservationIgnored private let day: DayCoach
    @ObservationIgnored private let lockScreenCard: LiveActivityController

    @ObservationIgnored private var engine = PostureEngine()
    @ObservationIgnored private var fatigue = FatigueMonitor()
    @ObservationIgnored private var draft: SessionDraft?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var holdsStream = false
    @ObservationIgnored private var lastFrameAt = Date()
    @ObservationIgnored private var lastPublishT = 0.0
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var minuteOfDay = 0
    @ObservationIgnored private var secondsSinceCheckpoint = 0
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var seat = SeatTracker()

    /// A paused session is closed after this long so nothing idles forever.
    /// With the AirPods out the silent audio engine is all that still runs,
    /// and it is the expensive part, so that wait is the shorter one.
    private func maxPause(for reason: PauseReason) -> TimeInterval {
        reason == .lowPower ? 15 * 60 : 8 * 60
    }

    init(settings: SettingsStore, store: SessionStore, headphones: HeadphoneMotionService,
         phone: PhoneContextService, power: LocationAndPowerGuard, coach: AudioCoachService,
         day: DayCoach) {
        self.settings = settings
        self.store = store
        self.headphones = headphones
        self.phone = phone
        self.power = power
        self.coach = coach
        self.day = day
        self.lockScreenCard = LiveActivityController()
    }

    // MARK: Start / end

    @discardableResult
    func start(trigger: Trigger = .manual) -> Bool {
        guard phase == .idle else { return false }
        let config = settings.value
        coach.mode = config.feedback
        coach.language = config.coachLanguage
        coach.voiceID = config.coachVoiceID
        do {
            try coach.beginSession()
        } catch {
            // Without the audio session the app cannot stay alive in the
            // background. A manual session may still run in the foreground.
            if trigger != .manual { return false }
        }

        engine = PostureEngine(tuning: config.tuning, anchor: config.baseline)
        fatigue = FatigueMonitor()
        // Long sitting is the day coach's job now: it checks in on a timer
        // and knows what fits the place and the calendar.
        fatigue.longSitSeconds = .infinity
        var placeName: String?
        if case .auto(let name) = trigger { placeName = name }
        isAutoStarted = placeName != nil
        let newDraft = SessionDraft(start: Date(), placeName: placeName, autoStarted: isAutoStarted)
        draft = newDraft
        startedAt = newDraft.start
        snapshot = LiveSnapshot()
        zone = .aligned
        context = .settling
        elapsed = 0
        uprightSetAt = nil
        lastFrameAt = Date()
        minuteOfDay = Self.minuteOfDay(Date())
        secondsSinceCheckpoint = 0
        isForeground = UIApplication.shared.applicationState == .active
        seat = SeatTracker()
        isSitting = false
        sensorSide = .unknown

        listener = headphones.addListener { [weak self] sample in self?.ingest(sample) }
        holdStream(true)
        phone.start()
        phase = .live
        day.trackingStarted()

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        coach.deliver(.sessionStarted(auto: isAutoStarted))
        if power.isLowPowerMode { pause(.lowPower) }
        lockScreenCard.begin(startedAt: draft?.start ?? Date(), placeName: placeName, state: cardState)
        return true
    }

    func end() {
        guard phase != .idle else { return }
        ticker?.invalidate()
        ticker = nil
        if let listener { headphones.removeListener(listener) }
        listener = nil
        holdStream(false)
        phone.stop()
        applySeat(seat.stop(now: Date()))

        if let draft {
            if draft.scored >= 20 {
                store.upsert(draft.record(end: Date()))
            } else {
                store.remove(id: draft.id)
            }
        }
        draft = nil
        startedAt = nil
        coach.deliver(.sessionEnded)
        coach.endSession()
        lockScreenCard.end()
        phase = .idle
        day.trackingEnded()
    }

    /// What the Lock Screen card shows right now.
    private var cardState: PostureActivityAttributes.ContentState {
        let status: PostureActivityAttributes.Status
        switch phase {
        case .paused(.lowPower):
            status = .pausedLowPower
        case .paused(.headphonesOut):
            status = .headphonesOut
        case .live, .idle:
            switch snapshot.context {
            case .moving, .away:
                status = .away
            case .lookingDown:
                status = .lookingDown
            case .focused, .phone, .settling:
                switch snapshot.zone {
                case .aligned: status = .aligned
                case .drifting: status = .drifting
                case .slouching: status = .slouching
                }
            }
        }
        return PostureActivityAttributes.ContentState(status: status, score: snapshot.score)
    }

    // MARK: User actions

    /// "Upright set": the current sitting position becomes the zero point.
    func setUpright() {
        engine.setUprightNow()
        if let anchor = engine.anchor {
            settings.update { $0.baseline = anchor }
        }
        uprightSetAt = Date()
        coach.deliver(.uprightSet)
    }

    /// Plays both posture beeps, to hear what they sound like.
    func playTestTones() {
        guard phase != .idle else { return }
        coach.playTestTones()
    }

    /// Keeps the coach quiet while a guided routine is on screen.
    func holdForExercise(seconds: Double) {
        engine.hold(seconds: seconds)
    }

    // MARK: Battery guard

    /// Called whenever Low Power Mode or the battery state changes.
    func powerStateChanged() {
        switch phase {
        case .live where power.isLowPowerMode:
            pause(.lowPower)
        case .paused(.lowPower) where !power.isLowPowerMode:
            resume()
        default:
            break
        }
    }

    private func pause(_ reason: PauseReason) {
        guard phase == .live else { return }
        phase = .paused(reason)
        pausedAt = Date()
        // No motion, no sitting: the count stops here.
        applySeat(seat.stop(now: Date()))
        if reason == .lowPower {
            // Stop every sensor. Only the silent audio session stays up so
            // the session can pick up again when Low Power Mode ends.
            holdStream(false)
            phone.stop()
            coach.deliver(.pausedLowPower)
        }
    }

    private func resume() {
        guard case .paused(let reason) = phase else { return }
        // AirPods out for a few minutes was a break from sitting.
        if reason == .headphonesOut, let pausedAt, Date().timeIntervalSince(pausedAt) > 120 {
            day.noteBreak()
        }
        phase = .live
        pausedAt = nil
        lastFrameAt = Date()
        if reason == .lowPower {
            holdStream(true)
            phone.start()
        }
        coach.deliver(.resumed)
    }

    private func holdStream(_ wanted: Bool) {
        guard wanted != holdsStream else { return }
        holdsStream = wanted
        if wanted {
            headphones.acquire()
        } else {
            headphones.release()
        }
    }

    // MARK: Frames

    private func ingest(_ sample: HeadSample) {
        if phase == .paused(.headphonesOut) { resume() }
        guard phase == .live else { return }
        lastFrameAt = Date()

        let reading = engine.ingest(sample, phone: phone.context)
        draft?.accumulate(reading, minuteOfDay: minuteOfDay)
        if sample.side != sensorSide { sensorSide = sample.side }

        // Sitting only counts while the body is still. Walking around with
        // AirPods in is not sitting.
        let away = reading.context == .away
        applySeat(seat.update(onFeet: away || reading.context == .moving, away: away, now: lastFrameAt))

        for event in reading.events {
            switch event {
            case .nudge(let kind, let level):
                draft?.nudges += 1
                coach.deliver(.nudge(kind, level: level))
            case .recovered:
                coach.deliver(.recovered)
            case .returned:
                // Got up and came back: the sitting clock starts again.
                day.noteBreak()
            case .away, .rebaselined:
                break
            }
        }
        if let reason = fatigue.ingest(reading) {
            draft?.breaks += 1
            day.fatigue(reason)
        }

        // Nobody is looking while the phone is locked: one update a second
        // is enough for the Lock Screen card.
        let publishGap = isForeground ? 0.08 : 1.0
        if sample.t - lastPublishT >= publishGap || sample.t < lastPublishT {
            lastPublishT = sample.t
            let next = LiveSnapshot(
                pitch: reading.pitch,
                roll: reading.roll,
                score: Int(reading.score.rounded()),
                zone: reading.zone,
                context: reading.context,
                load: reading.load
            )
            if next != snapshot { snapshot = next }
            if next.zone != zone { zone = next.zone }
            if next.context != context { context = next.context }
        }
    }

    private func applySeat(_ change: SeatTracker.Change?) {
        guard let change else { return }
        switch change {
        case .sat(let since):
            isSitting = true
            day.sittingBegan(at: since)
        case .left(let at):
            isSitting = false
            day.sittingEnded(at: at)
        }
    }

    private func tick() {
        guard let draft else { return }
        let now = Date()
        elapsed = now.timeIntervalSince(draft.start)
        minuteOfDay = Self.minuteOfDay(now)
        isForeground = UIApplication.shared.applicationState == .active
        headphones.checkStreamHealth()
        phone.refresh()

        // Settings changed in the profile apply to the running session.
        let config = settings.value
        coach.mode = config.feedback
        coach.language = config.coachLanguage
        coach.voiceID = config.coachVoiceID
        engine.tuning = config.tuning
        // Keeps the app alive behind the lock screen.
        coach.ensureRunning()
        day.heartbeat(now: now)

        switch phase {
        case .live:
            if now.timeIntervalSince(lastFrameAt) > 6 {
                pause(.headphonesOut)
            } else if snapshot.context != .away, snapshot.context != .moving {
                // No check-in while the user is on their feet anyway. Coming
                // back restarts the sitting clock.
                day.tick(now: now)
            }
            secondsSinceCheckpoint += 1
            if secondsSinceCheckpoint >= 30, draft.scored >= 20 {
                secondsSinceCheckpoint = 0
                store.upsert(draft.record(end: now))
            }
        case .paused(let reason):
            if let pausedAt, now.timeIntervalSince(pausedAt) > maxPause(for: reason) {
                end()
            }
        case .idle:
            break
        }
        if phase != .idle { lockScreenCard.sync(cardState) }
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
