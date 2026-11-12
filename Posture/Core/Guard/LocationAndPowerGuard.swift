import CoreLocation
import Observation
import UIKit

/// Geofences for the saved places plus the battery guard.
///
/// Region monitoring wakes the app in the background when the user arrives
/// or leaves. It runs on cell towers and Wi-Fi, not GPS, so it costs next to
/// nothing. While the app is open a single location fix double-checks which
/// place the phone is really at. The power side reports Low Power Mode and
/// battery level so that sessions neither start nor keep sampling when the
/// phone is short on energy.
@MainActor
@Observable
final class LocationAndPowerGuard: NSObject {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var batteryLevel: Double?
    private(set) var isCharging = false
    private(set) var insidePlaceIDs: Set<String> = []

    @ObservationIgnored var onArrival: ((String) -> Void)?
    @ObservationIgnored var onDeparture: ((String) -> Void)?
    /// A real geofence crossing into a place, as opposed to "the app just
    /// found out it is already there".
    @ObservationIgnored var onEnter: ((String) -> Void)?
    /// The phone is confirmed not to be at this place (reported every time
    /// iOS says so, whether or not it was thought to be inside).
    @ObservationIgnored var onOutside: ((String) -> Void)?
    /// The set of places the phone is inside changed.
    @ObservationIgnored var onPlacesChange: (() -> Void)?
    @ObservationIgnored var onPowerStateChange: (() -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var locationWaiters: [(CLLocation?) -> Void] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastFixRequestAt = Date.distantPast
    @ObservationIgnored private var lastFixAt = Date.distantPast

    var hasAlwaysAccess: Bool { authorization == .authorizedAlways }
    var hasAnyAccess: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    /// True when "not inside any saved place" can be believed: geofences are
    /// live in the background, or a location fix was taken a moment ago.
    var isLocationTrusted: Bool {
        hasAlwaysAccess || Date().timeIntervalSince(lastFixAt) < 10 * 60
    }

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

    /// Asks iOS again which geofences the phone is inside. Cheap; the
    /// answers arrive through the delegate.
    func refreshStates() {
        for region in manager.monitoredRegions {
            manager.requestState(for: region)
        }
    }

    /// The location check behind the calendar: one fix at hundred-metre
    /// accuracy, compared against the saved places. Called when the app is
    /// opened, at most once every few minutes.
    func verifyPosition(places: [FocusPlace], minGap: TimeInterval = 180) {
        guard hasAnyAccess, !places.isEmpty else { return }
        guard Date().timeIntervalSince(lastFixRequestAt) >= minGap else { return }
        lastFixRequestAt = Date()
        currentLocation { [weak self] location in
            guard let self, let location,
                  location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 300 else { return }
            self.lastFixAt = Date()
            let slack = min(location.horizontalAccuracy, 100)
            for place in places {
                let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
                let inside = location.distance(from: center) <= max(place.radius, 80) + slack
                self.setInside(place.id.uuidString, inside, announce: false)
            }
            // Also tell listeners when nothing moved: "at none of the
            // places" has just become trustworthy.
            self.onPlacesChange?()
        }
    }

    /// `announce` marks a real geofence crossing, which is reported even if
    /// the set did not change (the app may have been relaunched for it).
    fileprivate func setInside(_ id: String, _ inside: Bool, announce: Bool) {
        if inside {
            let isNew = insidePlaceIDs.insert(id).inserted
            if isNew { onPlacesChange?() }
            if announce { onEnter?(id) }
            if isNew || announce { onArrival?(id) }
        } else {
            let wasInside = insidePlaceIDs.remove(id) != nil
            if wasInside { onPlacesChange?() }
            onOutside?(id)
            if wasInside || announce { onDeparture?(id) }
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
        Task { @MainActor in self.setInside(id, false, announce: true) }
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
