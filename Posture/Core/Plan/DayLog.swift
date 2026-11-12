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

/// A stretch of sitting.
struct SittingSpan: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        /// The phone was inside a saved library. Being there counts.
        case library
        /// Study mode (reminders or a tracked session) was on. At home this
        /// is the only thing that counts.
        case study
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

enum SittingMath {
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

    /// Seconds between `from` and `to` that are covered by at least one
    /// span. Overlaps (study mode inside a library stay) count once.
    static func seconds(_ spans: [SittingSpan], from: Date, to: Date, now: Date) -> TimeInterval {
        var parts: [(start: Date, end: Date)] = []
        for span in spans {
            guard let range = interval(of: span, now: now) else { continue }
            let start = max(range.start, from)
            let end = min(range.end, to)
            if end > start { parts.append((start: start, end: end)) }
        }
        parts.sort { $0.start < $1.start }

        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for part in parts {
            if let running = current {
                if part.start <= running.end {
                    current = (start: running.start, end: max(running.end, part.end))
                } else {
                    total += running.end.timeIntervalSince(running.start)
                    current = part
                }
            } else {
                current = part
            }
        }
        if let running = current {
            total += running.end.timeIntervalSince(running.start)
        }
        return total
    }

    /// Seconds sat on the calendar day of `day`.
    static func seconds(_ spans: [SittingSpan], on day: Date, now: Date, calendar: Calendar = .current) -> TimeInterval {
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: .day, value: 1, to: from) ?? from.addingTimeInterval(24 * 3600)
        return seconds(spans, from: from, to: to, now: now)
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
