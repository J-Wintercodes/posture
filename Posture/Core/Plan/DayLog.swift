import Foundation

// The day log: how long the user sat, and how much pain there was in the
// evening. Pure Swift so the arithmetic can be unit-tested.

enum DayKey {
    /// "2026-11-12" for the day `date` falls on.
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The day an evening answer belongs to. Shortly after midnight it is
    /// still "last night".
    static func eveningDay(for date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        if calendar.component(.hour, from: date) < 4,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: start) {
            return yesterday
        }
        return start
    }

    /// When the bedtime check of `day` fires. A bedtime after midnight
    /// (before 4 a.m.) belongs to the evening before.
    static func bedtime(on day: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        var base = start
        if clamped < 4 * 60, let next = calendar.date(byAdding: .day, value: 1, to: start) {
            base = next
        }
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: base) ?? base
    }
}

/// A stretch of time that goes into the sitting count.
///
/// Sitting is study mode time, less the time spent moving. Where the AirPods
/// are in, they decide; where they are not, the iPhone's own record of
/// walking, running, cycling and driving is taken off.
struct SittingSpan: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        /// The phone was inside a saved library. Counts like study mode.
        case library
        /// Study mode (with or without AirPods) or a tracked session was on.
        /// Counts, less the moving the iPhone saw, and less the time the
        /// AirPods were in (there `seated` decides).
        case study
        /// The AirPods saw the user sitting still. Counts as it is.
        case seated
        /// The AirPods were in and sending motion. Inside it only `seated`
        /// counts.
        case airpods
    }

    var id = UUID()
    var source: Source
    var placeID: String?
    var start: Date
    /// Nil while the span is still running.
    var end: Date?
    /// Last moment the app saw the span alive. Used to close a span whose
    /// end was never recorded (the app was killed during a session).
    var lastSeen: Date?
}

/// One reading of the iPhone's motion coprocessor: from `start` until the
/// next reading the user was moving (walking, running, cycling, driving) or
/// not.
struct ActivitySample: Equatable {
    var start: Date
    var moving: Bool
}

enum SittingMath {
    typealias Part = (start: Date, end: Date)

    /// An open span stops counting after this long, in case its end was
    /// missed (a geofence exit that never arrived, for example).
    static func cap(for source: SittingSpan.Source) -> TimeInterval {
        source == .library ? 12 * 3600 : 6 * 3600
    }

    /// Start and end of a span as of `now`. Nil when it is empty.
    static func interval(of span: SittingSpan, now: Date) -> (start: Date, end: Date)? {
        let end: Date
        if let closed = span.end {
            end = closed
        } else {
            end = min(now, span.start.addingTimeInterval(cap(for: span.source)))
        }
        guard end > span.start else { return nil }
        return (start: span.start, end: end)
    }

    /// The spans of the given sources between `from` and `to`, sorted and
    /// with overlaps joined.
    static func parts(_ spans: [SittingSpan], _ sources: Set<SittingSpan.Source>, from: Date, to: Date, now: Date) -> [Part] {
        var parts: [Part] = []
        for span in spans where sources.contains(span.source) {
            guard let range = interval(of: span, now: now) else { continue }
            let start = max(range.start, from)
            let end = min(range.end, to)
            if end > start { parts.append((start: start, end: end)) }
        }
        return merge(parts)
    }

    /// Sorts and joins overlapping or touching parts.
    static func merge(_ parts: [Part]) -> [Part] {
        let sorted = parts.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var result: [Part] = []
        for part in sorted {
            if let last = result.last, part.start <= last.end {
                result[result.count - 1].end = max(last.end, part.end)
            } else {
                result.append(part)
            }
        }
        return result
    }

    /// `base` with everything in `cuts` taken out. Both must be merged.
    static func subtract(_ base: [Part], _ cuts: [Part]) -> [Part] {
        guard !cuts.isEmpty else { return base }
        var result: [Part] = []
        for part in base {
            var start = part.start
            for cut in cuts where cut.end > start && cut.start < part.end {
                if cut.start > start { result.append((start: start, end: cut.start)) }
                start = max(start, cut.end)
                if start >= part.end { break }
            }
            if start < part.end { result.append((start: start, end: part.end)) }
        }
        return result
    }

    /// What `a` and `b` have in common. Both must be merged.
    static func intersect(_ a: [Part], _ b: [Part]) -> [Part] {
        subtract(a, subtract(a, b))
    }

    static func length(_ parts: [Part]) -> TimeInterval {
        parts.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// The time that is only estimated: study mode or a library stay
    /// without the AirPods in. The moving the iPhone saw is taken off this.
    static func estimated(_ spans: [SittingSpan], from: Date, to: Date, now: Date) -> [Part] {
        let unmeasured = parts(spans, [.library, .study], from: from, to: to, now: now)
        return subtract(unmeasured, parts(spans, [.airpods], from: from, to: to, now: now))
    }

    /// The stretches between `from` and `to` that count as sitting.
    static func sitting(_ spans: [SittingSpan], moving: [DateInterval] = [], from: Date, to: Date, now: Date) -> [Part] {
        let measured = parts(spans, [.seated], from: from, to: to, now: now)
        let moves = merge(moving.compactMap { move -> Part? in
            let start = max(move.start, from)
            let end = min(move.end, to)
            return end > start ? (start: start, end: end) : nil
        })
        let rest = subtract(estimated(spans, from: from, to: to, now: now), moves)
        return merge(measured + rest)
    }

    /// Seconds between `from` and `to` that count as sitting. Overlaps
    /// (study mode inside a library stay) count once.
    static func seconds(_ spans: [SittingSpan], from: Date, to: Date, now: Date, moving: [DateInterval] = []) -> TimeInterval {
        length(sitting(spans, moving: moving, from: from, to: to, now: now))
    }

    /// Seconds sat on the calendar day of `day`.
    static func seconds(_ spans: [SittingSpan], on day: Date, now: Date, calendar: Calendar = .current, moving: [DateInterval] = []) -> TimeInterval {
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: .day, value: 1, to: from) ?? from.addingTimeInterval(24 * 3600)
        return seconds(spans, from: from, to: to, now: now, moving: moving)
    }

    /// Turns the coprocessor's readings into the stretches spent moving.
    /// Each reading lasts until the next one, the last one until `end`.
    static func movingParts(_ samples: [ActivitySample], until end: Date) -> [DateInterval] {
        let sorted = samples.sorted { $0.start < $1.start }
        var parts: [Part] = []
        for (index, sample) in sorted.enumerated() where sample.moving {
            let stop = index + 1 < sorted.count ? sorted[index + 1].start : end
            let clipped = min(stop, end)
            if clipped > sample.start { parts.append((start: sample.start, end: clipped)) }
        }
        return merge(parts).map { DateInterval(start: $0.start, end: $0.end) }
    }
}

/// The evening pain scale, 0 (none) to 10 (worst).
enum PainScale {
    /// The quick answers offered on the notification itself.
    static let quick: [Int] = [0, 3, 5, 8]

    static func label(_ level: Int, language: CoachLanguage) -> String {
        let de = language == .de
        switch level {
        case ...0: return de ? "Keine" : "None"
        case 1...3: return de ? "Leicht" : "Mild"
        case 4...6: return de ? "Mittel" : "Moderate"
        default: return de ? "Stark" : "Strong"
        }
    }

    /// From this level on, the coach only suggests gentle routines.
    static let gentleFrom = 6
}
