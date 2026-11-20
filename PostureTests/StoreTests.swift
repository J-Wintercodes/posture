import XCTest
@testable import Posture

final class SessionStoreTests: XCTestCase {
    private func record(daysAgo: Double, now: Date) -> SessionRecord {
        let start = now.addingTimeInterval(-daysAgo * 24 * 3600)
        return SessionRecord(
            id: UUID(), start: start, end: start.addingTimeInterval(600),
            scoredSeconds: 600, goodSeconds: 500, scoreSum: 600 * 80, nudges: 0, breaksSuggested: 0,
            minutes: [], zones: [], placeName: nil, autoStarted: false
        )
    }

    @MainActor
    func testOldSessionsArePrunedWhenANewOneStarts() {
        let name = "journal-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: name)) }
        let store = SessionStore(filename: name)
        let now = Date()
        let old = record(daysAgo: Double(SessionStore.keepDays) + 20, now: now)
        store.upsert(old)
        XCTAssertEqual(store.sessions.count, 1)

        var recent = record(daysAgo: 1, now: now)
        store.upsert(recent)
        XCTAssertEqual(store.sessions.map(\.id), [recent.id])

        // A checkpoint of a running session updates it in place and keeps it.
        recent.nudges = 3
        store.upsert(recent)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.nudges, 3)
    }
}
