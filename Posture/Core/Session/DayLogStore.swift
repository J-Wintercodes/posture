import Foundation
import Observation

/// Sitting time and the evening pain answers, stored as one small JSON file
/// in Application Support.
///
/// Sitting is the time study mode is on (anywhere) or the phone is inside a
/// saved library, less the time spent moving. With the AirPods in, they say
/// when the user sits. Without them, the walking the iPhone recorded is
/// taken off (`MotionHistory`). That record is copied in here, because iOS
/// only keeps it for a week.
@MainActor
@Observable
final class DayLogStore {
    private(set) var spans: [SittingSpan] = []
    /// Day key ("2026-11-12") to pain level 0...10.
    private(set) var pain: [String: Int] = [:]
    /// Stretches spent moving, as far as they fall into study mode or a
    /// library stay without the AirPods.
    private(set) var moving: [DateInterval] = []

    /// The iPhone's motion record has been read up to here.
    @ObservationIgnored private var motionReadUntil: Date?
    @ObservationIgnored private var isReadingMotion = false

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let calendar = Calendar.current

    private struct Disk: Codable {
        var spans: [SittingSpan]
        var pain: [String: Int]
        /// Optional: files written before they existed lack them.
        var moving: [DateInterval]?
        var motionReadUntil: Date?
    }

    /// Spans older than this are dropped.
    private let keepDays = 120.0

    init(filename: String = "daylog.json") {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: filename)
        if let data = try? Data(contentsOf: url), let disk = try? JSONDecoder().decode(Disk.self, from: data) {
            spans = disk.spans
            pain = disk.pain
            moving = disk.moving ?? []
            motionReadUntil = disk.motionReadUntil
        }
    }

    private func save() {
        let disk = Disk(spans: spans, pain: pain, moving: moving, motionReadUntil: motionReadUntil)
        if let data = try? JSONEncoder().encode(disk) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Sitting

    /// The spans a tracked session or study mode keeps open. A library stay
    /// is not one of them: the geofence ends it.
    private static let sessionSources: Set<SittingSpan.Source> = [.study, .seated, .airpods]

    /// Starts counting. Does nothing if the same thing is already counting.
    func open(_ source: SittingSpan.Source, placeID: String? = nil, at date: Date = Date()) {
        let alreadyOpen = spans.contains { $0.source == source && $0.end == nil && $0.placeID == placeID }
        guard !alreadyOpen else { return }
        spans.append(SittingSpan(source: source, placeID: placeID, start: date, end: nil, lastSeen: date))
        prune(now: date)
        save()
    }

    /// Stops counting. With a place id only that library is closed.
    func close(_ source: SittingSpan.Source, placeID: String? = nil, at date: Date = Date()) {
        var changed = false
        for index in spans.indices where spans[index].source == source && spans[index].end == nil {
            if let placeID, spans[index].placeID != placeID { continue }
            let limit = spans[index].start.addingTimeInterval(SittingMath.cap(for: source))
            spans[index].end = max(spans[index].start, min(date, limit))
            changed = true
        }
        if changed { save() }
    }

    /// Notes that study mode is still alive. Called about once a minute by
    /// a tracked session.
    func touchStudy(at date: Date = Date()) {
        var changed = false
        for index in spans.indices where Self.sessionSources.contains(spans[index].source) && spans[index].end == nil {
            spans[index].lastSeen = date
            changed = true
        }
        if changed { save() }
    }

    /// A study span that was never closed (the app was killed while a
    /// session ran) ends where it was last seen.
    func closeOrphanedStudy() {
        var changed = false
        for index in spans.indices where Self.sessionSources.contains(spans[index].source) && spans[index].end == nil {
            spans[index].end = max(spans[index].start, spans[index].lastSeen ?? spans[index].start)
            changed = true
        }
        if changed { save() }
    }

    /// Open spans that ran into their cap are closed for good.
    func expire(now: Date = Date()) {
        var changed = false
        for index in spans.indices where spans[index].end == nil {
            let limit = spans[index].start.addingTimeInterval(SittingMath.cap(for: spans[index].source))
            if now >= limit {
                spans[index].end = limit
                changed = true
            }
        }
        if changed { save() }
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-keepDays * 24 * 3600)
        spans.removeAll { ($0.end ?? now) < cutoff }
        moving.removeAll { $0.end < cutoff }
    }

    func sittingSeconds(on day: Date, now: Date = Date()) -> TimeInterval {
        SittingMath.seconds(spans, on: day, now: now, calendar: calendar, moving: moving)
    }

    /// Copies the iPhone's record of walking, running, cycling and driving
    /// for the time since the last read, as far as it falls into study mode
    /// or a library stay without AirPods. Called when the app opens and
    /// when study mode ends. Cheap: iOS has recorded it anyway.
    func readMotion(from history: MotionHistory, now: Date = Date()) async {
        guard !isReadingMotion, history.isAvailable else { return }
        let earliest = now.addingTimeInterval(-MotionHistory.reach)
        // A few minutes of overlap: the last reading before may have been
        // cut off at "now" back then.
        let from = max(earliest, (motionReadUntil ?? earliest).addingTimeInterval(-600))
        guard now > from else { return }
        let wanted = SittingMath.estimated(spans, from: from, to: now, now: now)
        guard !wanted.isEmpty else {
            motionReadUntil = now
            save()
            return
        }
        isReadingMotion = true
        let found = await history.moving(from: from, to: now)
        isReadingMotion = false
        guard let found else { return }

        let fresh = SittingMath.intersect(
            wanted,
            SittingMath.merge(found.map { (start: $0.start, end: $0.end) })
        )
        // What was read before stays up to `from`, the rest is replaced.
        var kept: [DateInterval] = []
        for move in moving where move.start < from {
            kept.append(DateInterval(start: move.start, end: min(move.end, from)))
        }
        moving = kept + fresh.map { DateInterval(start: $0.start, end: $0.end) }
        motionReadUntil = now
        save()
    }

    // MARK: Pain

    func setPain(_ level: Int, dayKey: String) {
        pain[dayKey] = min(max(level, 0), 10)
        save()
    }

    func clearPain(dayKey: String) {
        pain[dayKey] = nil
        save()
    }

    func painLevel(on day: Date) -> Int? {
        pain[DayKey.key(for: day, calendar: calendar)]
    }

    /// The latest answer from last night or the night before. Older ones
    /// say nothing about today.
    func recentPain(now: Date = Date()) -> Int? {
        let evening = DayKey.eveningDay(for: now, calendar: calendar)
        if let tonight = painLevel(on: evening) { return tonight }
        guard let before = calendar.date(byAdding: .day, value: -1, to: evening) else { return nil }
        return painLevel(on: before)
    }

    #if DEBUG
    func eraseAll() {
        spans = []
        pain = [:]
        save()
    }
    #endif
}
