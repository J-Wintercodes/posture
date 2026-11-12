import EventKit
import Observation

/// Reads the iPhone calendar (EventKit). Whatever is synced into the
/// Calendar app shows up here on its own: iCloud, Google, and subscribed
/// iCal feeds such as a university timetable. Nothing is fetched over the
/// network by this app and nothing is written.
@MainActor
@Observable
final class CalendarService {
    private(set) var hasAccess = false
    private(set) var wasDenied = false
    /// Study ("lernen bib", "lernen zuhause") and gym entries from a few
    /// hours back to a day ahead, sorted by start. Everything else in the
    /// calendar is left out.
    private(set) var events: [PlannedEvent] = []

    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var libraryKeywords: [String] = []
    @ObservationIgnored private var homeKeywords: [String] = []
    @ObservationIgnored private var gymKeywords: [String] = []
    @ObservationIgnored private var isEnabled = true
    @ObservationIgnored private var lastReloadAt = Date.distantPast

    init() {
        refreshAuthorization()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reload()
                self.onChange?()
            }
        }
    }

    private func refreshAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        hasAccess = status == .fullAccess
        wasDenied = status == .denied || status == .restricted
    }

    /// Shows the system prompt the first time. Afterwards iOS only answers
    /// with the stored decision.
    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        refreshAuthorization()
        reload()
        onChange?()
    }

    /// Takes the word lists from the settings and reads the calendar again.
    func configure(enabled: Bool, libraryKeywords: String, homeKeywords: String, gymKeywords: String) {
        isEnabled = enabled
        self.libraryKeywords = EventClassifier.keywords(libraryKeywords)
        self.homeKeywords = EventClassifier.keywords(homeKeywords)
        self.gymKeywords = EventClassifier.keywords(gymKeywords)
        reload()
    }

    /// Reads again if the last look is older than `seconds`.
    func reloadIfOlder(than seconds: TimeInterval) {
        if Date().timeIntervalSince(lastReloadAt) >= seconds { reload() }
    }

    func reload(now: Date = Date()) {
        refreshAuthorization()
        lastReloadAt = Date()
        guard hasAccess, isEnabled else {
            if !events.isEmpty { events = [] }
            return
        }
        let from = now.addingTimeInterval(-3 * 3600)
        let to = now.addingTimeInterval(24 * 3600)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        var found: [PlannedEvent] = []
        for event in store.events(matching: predicate) {
            guard !event.isAllDay, event.status != .canceled,
                  let start = event.startDate, let end = event.endDate, end > start else { continue }
            let title = event.title ?? ""
            let kind = EventClassifier.kind(
                title: title,
                library: libraryKeywords,
                home: homeKeywords,
                gym: gymKeywords
            )
            guard kind != .other else { continue }
            let key = "\(event.eventIdentifier ?? title)|\(start.timeIntervalSince1970)"
            found.append(PlannedEvent(id: key, title: title, start: start, end: end, kind: kind))
        }
        found.sort { $0.start < $1.start }
        if found != events { events = found }
    }
}
