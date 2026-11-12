import Foundation

/// Watches a session for the moments where a nudge is not enough any more
/// and a short break or the 30 second reset is the better advice.
struct FatigueMonitor {
    var cooldown = 15.0 * 60
    var longSitSeconds = 50.0 * 60

    private(set) var minuteAverages: [Double] = []
    private var bucketSeconds = 0.0
    private var bucketSum = 0.0
    private var nudgeTimes: [TimeInterval] = []
    private var seatedSeconds = 0.0
    private var lastSuggestion = -Double.infinity

    mutating func ingest(_ r: PostureReading) -> BreakReason? {
        for event in r.events {
            switch event {
            case .nudge:
                nudgeTimes.append(r.t)
            case .away:
                seatedSeconds = 0
            default:
                break
            }
        }
        nudgeTimes.removeAll { r.t - $0 > 8 * 60 }

        if r.context != .away, r.context != .moving {
            seatedSeconds += r.dt
        }
        if r.isScored {
            bucketSeconds += r.dt
            bucketSum += r.score * r.dt
            if bucketSeconds >= 60 {
                minuteAverages.append(bucketSum / bucketSeconds)
                if minuteAverages.count > 20 { minuteAverages.removeFirst() }
                bucketSeconds = 0
                bucketSum = 0
            }
        }

        // Never interrupt phone use or a walk with a suggestion.
        guard r.isScored, r.t - lastSuggestion >= cooldown else { return nil }

        let reason: BreakReason?
        if nudgeTimes.count >= 3 {
            reason = .repeatedSlouch
        } else if isFading {
            reason = .fatigueTrend
        } else if seatedSeconds >= longSitSeconds {
            reason = .longSit
        } else {
            reason = nil
        }
        if reason != nil {
            lastSuggestion = r.t
            nudgeTimes.removeAll()
            seatedSeconds = 0
        }
        return reason
    }

    /// A fatigue curve: the per-minute score has been sliding for a while
    /// and has ended up clearly lower than where it started.
    private var isFading: Bool {
        let window = Array(minuteAverages.suffix(10))
        guard window.count >= 6 else { return false }
        let n = Double(window.count)
        let meanX = (n - 1) / 2
        let meanY = window.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for (i, y) in window.enumerated() {
            let dx = Double(i) - meanX
            num += dx * (y - meanY)
            den += dx * dx
        }
        let slope = den > 0 ? num / den : 0
        let head = window.prefix(3).reduce(0, +) / 3
        let tail = window.suffix(3).reduce(0, +) / 3
        return slope <= -1.0 && head - tail >= 8 && tail <= 82
    }
}
