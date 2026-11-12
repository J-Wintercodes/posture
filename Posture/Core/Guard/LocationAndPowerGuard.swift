import CoreLocation
import Observation
import UIKit

/// Geofences for the focus places plus the battery guard.
///
/// Region monitoring wakes the app in the background when the user arrives;
/// the power side reports Low Power Mode and battery level so that sessions
/// neither start nor keep sampling when the phone is short on energy.
@MainActor
@Observable
final class LocationAndPowerGuard: NSObject {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var batteryLevel: Double?
    private(set) var isCharging = false
    private(set) var insidePlaceIDs: Set<String> = []

    @ObservationIgnored var onArrival: ((String) -> Void)?
    @ObservationIgnored var onPowerStateChange: (() -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var locationWaiters: [(CLLocation?) -> Void] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var hasAlwaysAccess: Bool { authorization == .authorizedAlways }
    var hasAnyAccess: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus

        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshPower()
        let names: [Notification.Name] = [
            .NSProcessInfoPowerStateDidChange,
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPower()
                    self?.onPowerStateChange?()
                }
            }
            observers.append(token)
        }
    }

    // MARK: Power

    private func refreshPower() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let level = UIDevice.current.batteryLevel
        batteryLevel = level >= 0 ? Double(level) : nil
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }

    // MARK: Authorization

    /// Steps through the two-stage location prompt: first "While Using",
    /// then the upgrade to "Always" that background arrival needs.
    func requestAccess() {
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: One-shot location for saving a place

    func currentLocation(_ completion: @escaping (CLLocation?) -> Void) {
        guard hasAnyAccess else {
            completion(nil)
            return
        }
        locationWaiters.append(completion)
        manager.requestLocation()
    }

    fileprivate func resolveLocation(_ location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        waiters.forEach { $0(location) }
    }

    // MARK: Geofences

    func sync(places: [FocusPlace]) {
        let wanted = Set(places.map { $0.id.uuidString })
        for region in manager.monitoredRegions where !wanted.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        insidePlaceIDs.formIntersection(wanted)
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for place in places {
            let radius = min(max(place.radius, 80), manager.maximumRegionMonitoringDistance)
            let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            let region = CLCircularRegion(center: center, radius: radius, identifier: place.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            manager.requestState(for: region)
        }
    }

    fileprivate func setInside(_ id: String, _ inside: Bool, announce: Bool) {
        if inside {
            let isNew = insidePlaceIDs.insert(id).inserted
            if isNew || announce { onArrival?(id) }
        } else {
            insidePlaceIDs.remove(id)
        }
    }

    fileprivate func setAuthorization(_ status: CLAuthorizationStatus) {
        authorization = status
    }
}

extension LocationAndPowerGuard: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.setAuthorization(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.setInside(id, true, announce: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.setInside(id, false, announce: false) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let id = region.identifier
        let inside = state == .inside
        Task { @MainActor in self.setInside(id, inside, announce: false) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.resolveLocation(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resolveLocation(nil) }
    }
}
