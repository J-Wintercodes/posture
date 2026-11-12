import Foundation
import Observation

/// The journal: every session and every completed reset, stored as one JSON
/// file in Application Support, plus the queries the screens need.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [SessionRecord] = []
    private(set) var resets: [Date] = []

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let calendar = Calendar.current

    private struct Disk: Codable {
        var sessions: [SessionRecord]
        var resets: [Date]
    }

    init(filename: String = "journal.json") {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: filename)
        if let data = try? Data(contentsOf: url), let disk = try? JSONDecoder().decode(Disk.self, from: data) {
            sessions = disk.sessions
            resets = disk.resets
        }
    }

    // MARK: Writing

    func upsert(_ record: SessionRecord) {
        if let index = sessions.firstIndex(where: { $0.id == record.id }) {
            sessions[index] = record
        } else {
            sessions.append(record)
        }
        save()
    }

    func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func addReset(at date: Date = Date()) {
        resets.append(date)
        save()
    }

    private func save() {
        let disk = Disk(sessions: sessions, resets: resets)
        if let data = try? JSONEncoder().encode(disk) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Queries

    func summary(on day: Date) -> DaySummary {
        let start = calendar.startOfDay(for: day)
        let list = sessions
            .filter { calendar.isDate($0.start, inSameDayAs: start) }
            .sorted { $0.start < $1.start }
        return DaySummary(date: start, sessions: list)
    }

    /// The last `count` days, oldest first, ending today.
    func lastDays(_ count: Int, endingAt end: Date = Date()) -> [DaySummary] {
        (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end).map { summary(on: $0) }
        }
    }

    /// Monday to Sunday of the week that contains `date`.
    func calendarWeek(containing date: Date = Date()) -> [DaySummary] {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        guard let interval = iso.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { offset in
            iso.date(byAdding: .day, value: offset, to: interval.start).map { summary(on: $0) }
        }
    }

    /// Consecutive active days. Today extends the streak but does not break it.
    var streak: Int {
        var count = 0
        var day = Date()
        if !summary(on: day).isActive {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while summary(on: day).isActive {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    func resetsCount(on day: Date = Date()) -> Int {
        resets.filter { calendar.isDate($0, inSameDayAs: day) }.count
    }

    /// Posture zone seconds summed over the last `days` days.
    func zoneGrid(days: Int = 7) -> [Double] {
        var grid = [Double](repeating: 0, count: ZoneGrid.side * ZoneGrid.side)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return grid }
        for session in sessions where session.start >= cutoff && session.zones.count == grid.count {
            for i in grid.indices { grid[i] += session.zones[i] }
        }
        return grid
    }

    /// Average score per hour of day across the whole journal.
    func hourlyProfile() -> [Double?] {
        var seconds = [Double](repeating: 0, count: 24)
        var sums = [Double](repeating: 0, count: 24)
        for session in sessions {
            for bucket in session.minutes {
                let hour = min(max(bucket.minute / 60, 0), 23)
                seconds[hour] += bucket.scored
                sums[hour] += bucket.scoreSum
            }
        }
        return (0..<24).map { seconds[$0] >= 120 ? sums[$0] / seconds[$0] : nil }
    }

    // MARK: Sample data

    #if DEBUG
    /// Fills the past six days with plausible sessions so the charts can be
    /// looked at without a week of wearing AirPods.
    func loadSampleWeek() {
        var seed: UInt64 = 0xDEAD_BEEF_CAFE
        func random() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 10_000) / 10_000
        }
        let today = calendar.startOfDay(for: Date())
        for dayOffset in 1...6 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            if dayOffset == 4 { continue }
            for (startMinute, length) in [(9 * 60 + 5, 50), (14 * 60 + 20, 40)] {
                let base = 74 + random() * 18 - (startMinute > 13 * 60 ? 6 : 0)
                var draft = SessionDraft(start: day.addingTimeInterval(Double(startMinute) * 60), placeName: "University / Library", autoStarted: true)
                for m in 0..<length {
                    let fade = Double(m) / Double(length) * 9
                    let score = min(max(base - fade + random() * 8 - 4, 35), 99)
                    let pitch = (100 - score) * 0.45 + random() * 4 - 2
                    let roll = random() * 10 - 5
                    for _ in 0..<6 {
                        let reading = PostureReading(
                            t: 0, dt: 10, pitch: pitch + random() * 6 - 3, roll: roll + random() * 4 - 2,
                            score: score, zone: .aligned, context: .focused, entry: .none, load: 0,
                            isScored: true, events: []
                        )
                        draft.accumulate(reading, minuteOfDay: startMinute + m)
                    }
                }
                draft.nudges = Int(random() * 4)
                let end = draft.start.addingTimeInterval(Double(length) * 60)
                sessions.append(draft.record(end: end))
            }
        }
        save()
    }

    func eraseAll() {
        sessions = []
        resets = []
        save()
    }
    #endif
}
