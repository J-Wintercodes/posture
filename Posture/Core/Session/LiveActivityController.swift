import ActivityKit
import UIKit

/// Keeps the session card on the Lock Screen (a Live Activity) in step with
/// the running session.
///
/// The card doubles as a health check: every update carries a stale date a
/// couple of minutes ahead and the session refreshes it once a minute. If
/// iOS ever suspends the app, the refreshes stop and the card switches to
/// "Not tracking" instead of showing a frozen score.
@MainActor
final class LiveActivityController {
    typealias CardState = PostureActivityAttributes.ContentState

    private var activity: Activity<PostureActivityAttributes>?
    private var attributes: PostureActivityAttributes?
    private var sent: CardState?
    private var sentAt = Date.distantPast
    private var lastRequestAt = Date.distantPast

    /// Shortest gap between two updates.
    private let minGap: TimeInterval = 3
    /// A change of the score alone is not worth more than this.
    private let scoreGap: TimeInterval = 30
    /// Refresh even when nothing changed, to push the stale date along.
    private let heartbeat: TimeInterval = 60
    private let staleAfter: TimeInterval = 150

    init() {
        // Cards left behind by a session that did not end cleanly.
        endLeftovers()
    }

    func begin(startedAt: Date, placeName: String?, state: CardState) {
        endLeftovers()
        attributes = PostureActivityAttributes(startedAt: startedAt, placeName: placeName)
        activity = nil
        sent = nil
        lastRequestAt = .distantPast
        sync(state)
    }

    /// Called once a second by the session.
    func sync(_ state: CardState) {
        guard let attributes else { return }
        let now = Date()

        guard let activity else {
            // iOS only lets an app put up a Live Activity while it is in the
            // foreground. A session that auto-started in the background gets
            // its card the next time the app is opened.
            guard now.timeIntervalSince(lastRequestAt) >= 5,
                  UIApplication.shared.applicationState == .active,
                  ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            lastRequestAt = now
            let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(staleAfter))
            if let started = try? Activity<PostureActivityAttributes>.request(attributes: attributes, content: content, pushType: nil) {
                self.activity = started
                sent = state
                sentAt = now
            }
            return
        }

        // Swiped away by the user, or ended by iOS after its eight hours.
        guard activity.activityState == .active || activity.activityState == .stale else { return }

        let gap = now.timeIntervalSince(sentAt)
        let due: Bool
        if gap >= heartbeat {
            due = true
        } else if state.status != sent?.status {
            due = gap >= minGap
        } else if abs(state.score - (sent?.score ?? state.score)) >= 2 {
            due = gap >= scoreGap
        } else {
            due = false
        }
        guard due else { return }
        sent = state
        sentAt = now
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(staleAfter))
        Task { await activity.update(content) }
    }

    func end() {
        attributes = nil
        sent = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func endLeftovers() {
        for leftover in Activity<PostureActivityAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
