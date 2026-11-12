import CoreMotion
import LocalAuthentication
import Observation
import UIKit

/// Answers one question for the engine: is the user on the phone right now?
///
/// One thing silences the coach: the iPhone is unlocked and in the hand. It
/// is tilted, or it carries the small tremor a table never has. The app
/// being on screen is not enough: a phone lying on the desk with the live
/// screen open must still get the tones.
///
/// A locked phone never counts as in use, however much it moves (pocket,
/// bag, a wobbly desk). And every signal expires on its own, so a missed
/// system notification can never keep the coach quiet for a whole session.
///
/// Because a locked phone never counts, its motion sensors are only switched
/// on while it is unlocked. For most of a session the phone lies locked on
/// the desk and this service then costs nothing.
@MainActor
@Observable
final class PhoneContextService {
    private(set) var context = PhoneContext()

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var rotation = 0.0
    @ObservationIgnored private var acceleration = 0.0
    @ObservationIgnored private var lastHandledAt = -Double.infinity
    @ObservationIgnored private var lastMotionFrameAt = Date.distantPast
    @ObservationIgnored private var hasPasscode = true
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var isAppActive = false
    @ObservationIgnored private var isUnlocked = false
    @ObservationIgnored private var isMoving = false

    func start() {
        #if targetEnvironment(simulator)
        // The Simulator is always "in use"; leave the context empty so the
        // scripted session is scored.
        return
        #else
        guard !isRunning else { return }
        isRunning = true

        // Without a passcode protected data never becomes unavailable, so
        // the lock state cannot be read. Such a device counts as unlocked.
        hasPasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)

        isAppActive = UIApplication.shared.applicationState == .active
        isUnlocked = !hasPasscode || UIApplication.shared.isProtectedDataAvailable
        isMoving = false
        publish()

        let center = NotificationCenter.default
        observe(center, UIApplication.didBecomeActiveNotification) { $0.isAppActive = true }
        observe(center, UIApplication.willResignActiveNotification) { $0.isAppActive = false }
        observe(center, UIApplication.protectedDataDidBecomeAvailableNotification) { $0.isUnlocked = true }
        observe(center, UIApplication.protectedDataWillBecomeUnavailableNotification) { $0.isUnlocked = !$0.hasPasscode }
        #endif
    }

    /// Runs the phone's motion sensors only while they can matter: the
    /// service is on and the phone is unlocked.
    private func syncMotion() {
        let wanted = isRunning && isUnlocked
        if wanted, !motion.isDeviceMotionActive {
            guard motion.isDeviceMotionAvailable else { return }
            rotation = 0
            acceleration = 0
            motion.deviceMotionUpdateInterval = 0.2
            motion.startDeviceMotionUpdates(to: .main) { [weak self] frame, _ in
                guard let self, let frame else { return }
                let r = frame.rotationRate
                let a = frame.userAcceleration
                let rot = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
                let acc = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
                let flat = abs(frame.gravity.z)
                let t = frame.timestamp
                MainActor.assumeIsolated { self.ingest(rotation: rot, acceleration: acc, flatness: flat, at: t) }
            }
        } else if !wanted, motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
            isMoving = false
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motion.stopDeviceMotionUpdates()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        isAppActive = false
        isUnlocked = false
        isMoving = false
        context = PhoneContext()
    }

    /// Called once a second by the session. Re-reads what can be read
    /// directly and drops a "handheld" that no motion frame backs up any
    /// more, so no signal can get stuck.
    func refresh() {
        guard isRunning else { return }
        isAppActive = UIApplication.shared.applicationState == .active
        isUnlocked = !hasPasscode || UIApplication.shared.isProtectedDataAvailable
        if isMoving, Date().timeIntervalSince(lastMotionFrameAt) > 2 {
            isMoving = false
        }
        publish()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping @MainActor (PhoneContextService) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                change(self)
                self.publish()
            }
        }
        observers.append(token)
    }

    private func ingest(rotation rot: Double, acceleration acc: Double, flatness: Double, at t: TimeInterval) {
        lastMotionFrameAt = Date()
        // Five frames a second instead of ten; the stronger smoothing step
        // keeps the same reaction time as before.
        rotation += 0.5 * (rot - rotation)
        acceleration += 0.5 * (acc - acceleration)
        let restingFlat = flatness > 0.96 && rotation < 0.03 && acceleration < 0.012
        if !restingFlat, rotation > 0.06 || acceleration > 0.025 {
            lastHandledAt = t
        }
        let moving = t - lastHandledAt < 4
        if moving != isMoving {
            isMoving = moving
            publish()
        }
    }

    private func publish() {
        syncMotion()
        var next = PhoneContext()
        next.isAppActive = isAppActive
        next.isUnlocked = isUnlocked
        next.isHandheld = isMoving && isUnlocked
        if next != context { context = next }
    }
}
