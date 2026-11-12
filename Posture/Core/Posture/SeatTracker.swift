import Foundation

/// Decides when the user is actually sitting during a tracked session, so
/// that walking around with AirPods in does not count as sitting.
///
/// Sitting begins once the body has been still for `confirm` seconds, and is
/// then counted from the start of that still stretch. It ends when the user
/// has walked off (the engine's "away"), counted back to the moment the
/// movement began. Shifting on the chair or reaching for something does not
/// end it.
struct SeatTracker {
    enum Change: Equatable {
        case sat(since: Date)
        case left(at: Date)
    }

    /// Seconds of stillness before it counts as sitting.
    var confirm: TimeInterval = 30

    private(set) var isSeated = false
    private var stillSince: Date?
    private var movingSince: Date?

    /// Feed with every reading. `onFeet` is the engine's moving or away,
    /// `away` only the latter.
    mutating func update(onFeet: Bool, away: Bool, now: Date) -> Change? {
        if onFeet {
            if movingSince == nil { movingSince = now }
            stillSince = nil
            if isSeated, away {
                isSeated = false
                return .left(at: movingSince ?? now)
            }
            return nil
        }
        movingSince = nil
        if stillSince == nil { stillSince = now }
        if !isSeated, let since = stillSince, now.timeIntervalSince(since) >= confirm {
            isSeated = true
            return .sat(since: since)
        }
        return nil
    }

    /// The stream stopped (AirPods out, session paused or ended).
    mutating func stop(now: Date) -> Change? {
        stillSince = nil
        movingSince = nil
        guard isSeated else { return nil }
        isSeated = false
        return .left(at: now)
    }
}
