import CoreMotion

/// Reads what the iPhone's motion coprocessor recorded: when the user was
/// walking, running, cycling or driving. iOS records this all the time and
/// keeps it for seven days, so reading it afterwards costs no battery and
/// needs no running app. Uses the same Motion & Fitness permission as the
/// AirPods.
///
/// It is the iPhone's view only: a phone left on the desk while the user
/// walks off sees no walking.
@MainActor
final class MotionHistory {
    /// How far back iOS keeps the record, with an hour to spare.
    static let reach: TimeInterval = 7 * 24 * 3600 - 3600

    private let manager = CMMotionActivityManager()

    var isAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
            && CMMotionActivityManager.authorizationStatus() == .authorized
    }

    /// The stretches between `from` and `to` spent moving. Nil when the
    /// record cannot be read (no permission, no coprocessor).
    func moving(from: Date, to: Date) async -> [DateInterval]? {
        guard isAvailable, to > from else { return nil }
        return await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: from, to: to, to: .main) { activities, error in
                guard error == nil, let activities else {
                    continuation.resume(returning: nil)
                    return
                }
                let samples = activities.map { activity in
                    ActivitySample(start: activity.startDate, moving: Self.isMoving(activity))
                }
                continuation.resume(returning: SittingMath.movingParts(samples, until: to))
            }
        }
    }

    /// Low-confidence readings are left out: they come and go while the
    /// phone lies still.
    private nonisolated static func isMoving(_ activity: CMMotionActivity) -> Bool {
        guard activity.confidence != .low else { return false }
        return activity.walking || activity.running || activity.cycling || activity.automotive
    }
}
