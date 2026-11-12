import AVFoundation
import CoreMotion
import Observation

/// Wraps `CMHeadphoneMotionManager`. Several owners (the session, the
/// calibration screen) can hold the stream at once; it stops when the last
/// one lets go. In the Simulator it plays a scripted desk scene instead.
@MainActor
@Observable
final class HeadphoneMotionService: NSObject {
    private(set) var isStreaming = false
    private(set) var routeName: String?
    private(set) var authorization: CMAuthorizationStatus = CMHeadphoneMotionManager.authorizationStatus()

    /// True when motion-capable headphones are plausibly in the ears.
    var isConnected: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return isStreaming || routeName != nil
        #endif
    }

    @ObservationIgnored var onConnectionChange: (() -> Void)?
    @ObservationIgnored private(set) var latest: HeadSample?

    @ObservationIgnored private let manager = CMHeadphoneMotionManager()
    @ObservationIgnored private let activity = CMMotionActivityManager()
    @ObservationIgnored private var listeners: [UUID: (HeadSample) -> Void] = [:]
    @ObservationIgnored private var holders = 0
    @ObservationIgnored private var lastFrameAt = Date.distantPast
    @ObservationIgnored private var simulationTimer: Timer?
    @ObservationIgnored private var synthetic = SyntheticHead()

    override init() {
        super.init()
        manager.delegate = self
        refreshRoute()
        _ = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRoute()
                self?.onConnectionChange?()
            }
        }
    }

    // MARK: Authorization

    /// Brings up the Motion & Fitness prompt without needing AirPods in the
    /// ears: a throwaway activity query asks for the same permission.
    func requestAuthorization() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            authorization = CMHeadphoneMotionManager.authorizationStatus()
            return
        }
        let now = Date()
        activity.queryActivityStarting(from: now, to: now, to: .main) { [weak self] _, _ in
            Task { @MainActor in
                self?.authorization = CMHeadphoneMotionManager.authorizationStatus()
            }
        }
    }

    // MARK: Stream ownership

    func addListener(_ handler: @escaping (HeadSample) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    func acquire() {
        holders += 1
        if holders == 1 { startUpdates() }
    }

    func release() {
        holders = max(0, holders - 1)
        if holders == 0 { stopUpdates() }
    }

    /// Called once a second by the session to notice a silent stream.
    func checkStreamHealth() {
        if isStreaming, Date().timeIntervalSince(lastFrameAt) > 3 {
            isStreaming = false
        }
    }

    // MARK: Internals

    private func startUpdates() {
        #if targetEnvironment(simulator)
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1 / synthetic.sampleRate, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emitSynthetic() }
        }
        #else
        guard manager.isDeviceMotionAvailable else { return }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let sample = HeadSample(
                t: motion.timestamp,
                gravity: Vec3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
                rotationRate: Vec3(x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z),
                userAcceleration: Vec3(x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z)
            )
            MainActor.assumeIsolated { self.publish(sample) }
        }
        #endif
    }

    private func stopUpdates() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        #if !targetEnvironment(simulator)
        manager.stopDeviceMotionUpdates()
        #endif
        isStreaming = false
        latest = nil
    }

    private func emitSynthetic() {
        guard holders > 0 else { return }
        let pose = DemoScenario.pose(at: synthetic.time)
        publish(synthetic.next(forward: pose.forward, lateral: pose.lateral, lively: pose.lively))
    }

    private func publish(_ sample: HeadSample) {
        latest = sample
        lastFrameAt = Date()
        if !isStreaming {
            isStreaming = true
            authorization = CMHeadphoneMotionManager.authorizationStatus()
        }
        for handler in listeners.values { handler(sample) }
    }

    fileprivate func connectionChanged(connected: Bool) {
        if !connected { isStreaming = false }
        refreshRoute()
        onConnectionChange?()
    }

    private func refreshRoute() {
        let wireless: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first { wireless.contains($0.portType) }
        let name = output?.portName
        if name != routeName { routeName = name }
    }
}

extension HeadphoneMotionService: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.connectionChanged(connected: true) }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.connectionChanged(connected: false) }
    }
}
