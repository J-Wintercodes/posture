import CoreMotion
import LocalAuthentication
import Observation
import UIKit

/// Answers one question for the engine: is the user on the phone right now?
///
/// Three signals, any of which silences the coach:
/// - the app is in the foreground,
/// - the device is unlocked (protected data is available),
/// - the iPhone is in the hand: it is tilted or it carries the small tremor
///   a table never has.
@MainActor
@Observable
final class PhoneContextService {
    private(set) var context = PhoneContext()

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var rotation = 0.0
    @ObservationIgnored private var acceleration = 0.0
    @ObservationIgnored private var lastHandledAt = -Double.infinity
    @ObservationIgnored private var hasPasscode = true
    @ObservationIgnored private var isRunning = false

    func start() {
        #if targetEnvironment(simulator)
        // The Simulator is always "in use"; leave the context empty so the
        // scripted session is scored.
        return
        #else
        guard !isRunning else { return }
        isRunning = true

        // Without a passcode protected data never becomes unavailable, so the
        // unlock signal would be stuck on. Ignore it on such devices.
        hasPasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)

        var initial = PhoneContext()
        initial.isAppActive = UIApplication.shared.applicationState == .active
        initial.isUnlocked = hasPasscode && UIApplication.shared.isProtectedDataAvailable
        context = initial

        let center = NotificationCenter.default
        observe(center, UIApplication.didBecomeActiveNotification) { $0.isAppActive = true }
        observe(center, UIApplication.willResignActiveNotification) { $0.isAppActive = false }
        observe(center, UIApplication.protectedDataDidBecomeAvailableNotification) { [hasPasscode] in $0.isUnlocked = hasPasscode }
        observe(center, UIApplication.protectedDataWillBecomeUnavailableNotification) { $0.isUnlocked = false }

        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.1
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
        #endif
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motion.stopDeviceMotionUpdates()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        context = PhoneContext()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping (inout PhoneContext) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var next = self.context
                change(&next)
                if next != self.context { self.context = next }
            }
        }
        observers.append(token)
    }

    private func ingest(rotation rot: Double, acceleration acc: Double, flatness: Double, at t: TimeInterval) {
        rotation += 0.3 * (rot - rotation)
        acceleration += 0.3 * (acc - acceleration)
        let restingFlat = flatness > 0.96 && rotation < 0.03 && acceleration < 0.012
        if !restingFlat, rotation > 0.06 || acceleration > 0.025 {
            lastHandledAt = t
        }
        let handheld = t - lastHandledAt < 4
        if handheld != context.isHandheld {
            context.isHandheld = handheld
        }
    }
}
