import ActivityKit
import SwiftUI
import WidgetKit

/// The card that stays on the Lock Screen while a session runs, plus the
/// Dynamic Island on phones that have one.
struct PostureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PostureActivityAttributes.self) { context in
            LockScreenCard(look: Look(context), startedAt: context.attributes.startedAt, placeName: context.attributes.placeName)
                .activityBackgroundTint(Color(red: 0.02, green: 0.024, blue: 0.03).opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ScoreRing(look: Look(context), size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 64, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(Look(context).title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Look(context).color)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(Look(context).line)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                }
            } compactLeading: {
                Circle()
                    .fill(Look(context).color)
                    .frame(width: 10, height: 10)
                    .padding(.leading, 4)
            } compactTrailing: {
                Text(Look(context).scoreText)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Look(context).color)
            } minimal: {
                Circle()
                    .fill(Look(context).color)
                    .frame(width: 10, height: 10)
            }
        }
    }
}

/// Words and colour for one state of the session.
private struct Look {
    var title: String
    var line: String
    var color: Color
    var scoreText: String
    var progress: Double

    private static let mint = Color(red: 0.31, green: 0.82, blue: 0.77)
    private static let amber = Color(red: 0.96, green: 0.68, blue: 0.33)
    private static let ember = Color(red: 0.93, green: 0.54, blue: 0.21)
    private static let faint = Color.white.opacity(0.45)

    init(_ context: ActivityViewContext<PostureActivityAttributes>) {
        let state = context.state
        scoreText = "\(state.score)"
        progress = Double(min(max(state.score, 0), 100)) / 100

        // The app refreshes the card at least once a minute. If iOS marks
        // it stale, the app is no longer running in the background.
        if context.isStale {
            title = "Not tracking"
            line = "Open Posture to carry on."
            color = Look.faint
            scoreText = "–"
            progress = 0
            return
        }
        switch state.status {
        case .aligned:
            title = "Aligned"
            line = "Tall and easy."
            color = Look.mint
        case .drifting:
            title = "Drifting"
            line = "A little forward. Float the crown of your head up."
            color = Look.amber
        case .slouching:
            title = "Slouching"
            line = "Sinking in. Grow tall through your spine."
            color = Look.ember
        case .lookingDown:
            title = "Looking down"
            line = "Reading or writing. You have room."
            color = Look.mint
        case .away:
            title = "On the move"
            line = "Paused until you settle back in."
            color = Look.faint
            scoreText = "–"
        case .pausedLowPower:
            title = "Paused"
            line = "Low Power Mode is on."
            color = Look.faint
            scoreText = "–"
        case .headphonesOut:
            title = "Waiting"
            line = "Put your AirPods back in."
            color = Look.faint
            scoreText = "–"
        }
    }
}

private struct ScoreRing: View {
    var look: Look
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: look.progress)
                .stroke(look.color, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(look.scoreText)
                .font(.system(size: size * 0.36, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

private struct LockScreenCard: View {
    var look: Look
    var startedAt: Date
    var placeName: String?

    var body: some View {
        HStack(spacing: 14) {
            ScoreRing(look: look, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(header.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Text(look.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(look.color)
                Text(look.line)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(startedAt, style: .timer)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var header: String {
        if let placeName, !placeName.isEmpty { return "Posture · \(placeName)" }
        return "Posture session"
    }
}
