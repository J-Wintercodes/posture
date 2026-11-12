import Foundation

/// One minute of a session, keyed by minute of day (0...1439).
struct MinuteBucket: Codable, Hashable {
    var minute: Int
    var scored: Double
    var good: Double
    var scoreSum: Double

    var average: Double { scored > 0 ? scoreSum / scored : 0 }
}

/// A finished (or checkpointed) tracking session: one "chapter" of a day.
struct SessionRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var start: Date
    var end: Date
    /// Seconds that counted towards the score (phone use and walks excluded).
    var scoredSeconds: Double
    var goodSeconds: Double
    var scoreSum: Double
    var nudges: Int
    var breaksSuggested: Int
    var minutes: [MinuteBucket]
    /// 64 cells of seconds, see `ZoneGrid`.
    var zones: [Double]
    var placeName: String?
    var autoStarted: Bool

    var averageScore: Int { scoredSeconds > 0 ? Int((scoreSum / scoredSeconds).rounded()) : 0 }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Everything known about one calendar day.
struct DaySummary: Identifiable {
    var date: Date
    var sessions: [SessionRecord]

    var id: Date { date }
    var scored: Double { sessions.reduce(0) { $0 + $1.scoredSeconds } }
    var good: Double { sessions.reduce(0) { $0 + $1.goodSeconds } }
    var nudges: Int { sessions.reduce(0) { $0 + $1.nudges } }

    var score: Int? {
        let seconds = scored
        guard seconds > 0 else { return nil }
        return Int((sessions.reduce(0) { $0 + $1.scoreSum } / seconds).rounded())
    }

    var goodFraction: Double { scored > 0 ? good / scored : 0 }

    /// A day shows as tracked once five minutes were scored.
    var isActive: Bool { scored >= 5 * 60 }

    var minutes: [MinuteBucket] {
        var merged: [Int: MinuteBucket] = [:]
        for session in sessions {
            for bucket in session.minutes {
                if var existing = merged[bucket.minute] {
                    existing.scored += bucket.scored
                    existing.good += bucket.good
                    existing.scoreSum += bucket.scoreSum
                    merged[bucket.minute] = existing
                } else {
                    merged[bucket.minute] = bucket
                }
            }
        }
        return merged.values.sorted { $0.minute < $1.minute }
    }
}

/// Accumulates a running session. Lives in the SessionManager.
struct SessionDraft {
    let id = UUID()
    let start: Date
    var placeName: String?
    var autoStarted: Bool
    var scored = 0.0
    var good = 0.0
    var scoreSum = 0.0
    var nudges = 0
    var breaks = 0
    var minutes: [Int: MinuteBucket] = [:]
    var zones = [Double](repeating: 0, count: ZoneGrid.side * ZoneGrid.side)

    mutating func accumulate(_ r: PostureReading, minuteOfDay: Int) {
        if r.context != .moving, r.context != .away {
            zones[ZoneGrid.index(pitch: r.pitch, roll: r.roll)] += r.dt
        }
        guard r.isScored, r.dt > 0 else { return }
        scored += r.dt
        scoreSum += r.score * r.dt
        var bucket = minutes[minuteOfDay] ?? MinuteBucket(minute: minuteOfDay, scored: 0, good: 0, scoreSum: 0)
        bucket.scored += r.dt
        bucket.scoreSum += r.score * r.dt
        if r.isGood {
            good += r.dt
            bucket.good += r.dt
        }
        minutes[minuteOfDay] = bucket
    }

    func record(end: Date) -> SessionRecord {
        SessionRecord(
            id: id,
            start: start,
            end: end,
            scoredSeconds: scored,
            goodSeconds: good,
            scoreSum: scoreSum,
            nudges: nudges,
            breaksSuggested: breaks,
            minutes: minutes.values.sorted { $0.minute < $1.minute },
            zones: zones,
            placeName: placeName,
            autoStarted: autoStarted
        )
    }
}
