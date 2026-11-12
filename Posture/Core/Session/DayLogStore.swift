import Foundation
import Observation

/// Sitting time and the evening pain answers, stored as one small JSON file
/// in Application Support.
///
/// Sitting is counted from two sources and nothing else:
/// - the time the phone is inside a saved library (geofence),
/// - the time study mode is on, wherever that is. At home this is the only
///   thing that counts.
@MainActor
@Observable
final class DayLogStore {
    private(set) var spans: [SittingSpan] = []
    /// Day key ("2026-11-12") to pain level 0...10.
    private(set) var pain: [String: Int] = [:]

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let calendar = Calendar.current

    private struct Disk: Codable {
        var spans: [SittingSpan]
        var pain: [String: Int]
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
        }
    }

    private func save() {
        let disk = Disk(spans: spans, pain: pain)
        if let data = try? JSONEncoder().encode(disk) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Sitting

    var hasOpenStudy: Bool {
        spans.contains { $0.source == .study && $0.end == nil }
    }

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
        for index in spans.indices where spans[index].source == .study && spans[index].end == nil {
            spans[index].lastSeen = date
            changed = true
        }
        if changed { save() }
    }

    /// A study span that was never closed (the app was killed while a
    /// session ran) ends where it was last seen.
    func closeOrphanedStudy() {
        var changed = false
        for index in spans.indices where spans[index].source == .study && spans[index].end == nil {
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
    }

    func sittingSeconds(on day: Date, now: Date = Date()) -> TimeInterval {
        SittingMath.seconds(spans, on: day, now: now, calendar: calendar)
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
