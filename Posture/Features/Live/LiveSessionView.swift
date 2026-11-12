import SwiftUI

/// Full-screen overlay while a session is live. Built to be glanced at once
/// and then locked away: the session keeps running without it.
struct LiveSessionView: View {
    @Environment(AppModel.self) private var app
    @State private var glow = false
    @State private var showReset = false

    var body: some View {
        let session = app.session
        let live = session.snapshot
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                pills
                    .padding(.top, 14)
                Spacer(minLength: 12)
                SpineOrbView(
                    pitch: live.pitch,
                    roll: live.roll,
                    zone: live.zone,
                    score: live.score,
                    diameter: 176,
                    dimmed: isDimmed
                )
                status
                    .padding(.top, 22)
                Spacer(minLength: 12)
                banner
                    .padding(.bottom, 14)
                buttons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .overlay(borderGlow)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
        }
        .sheet(isPresented: $showReset) {
            ResetExerciseView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
    }

    private var isDimmed: Bool {
        if case .paused = app.session.phase { return true }
        let context = app.session.snapshot.context
        return context == .moving || context == .away
    }

    private var accent: Color {
        isDimmed ? Theme.textFaint : Theme.zone(app.session.snapshot.zone)
    }

    // MARK: Chrome

    private var borderGlow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .strokeBorder(accent.opacity(glow ? 0.75 : 0.35), lineWidth: 5)
                .blur(radius: 9)
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .strokeBorder(accent.opacity(0.45), lineWidth: 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            Button {
                app.showLive = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .accessibilityLabel("Minimise session")
            Spacer()
            HStack(spacing: 8) {
                StatusDot(color: accent)
                SectionLabel(phaseTitle, color: accent)
            }
            Spacer()
            Text(Fmt.clock(app.session.elapsed))
                .font(.ui(16, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.top, 8)
    }

    private var phaseTitle: String {
        switch app.session.phase {
        case .paused(.lowPower): return "Paused · Low Power"
        case .paused(.headphonesOut): return "Paused · AirPods out"
        default: return "Live session"
        }
    }

    private var pills: some View {
        let mode = app.settings.value.feedback
        return HStack(spacing: 8) {
            pill("moon.fill", "Lock safe")
            pill(mode == .silent ? "bell.slash.fill" : "bell.fill", mode.title)
            pill("hourglass", "\(Fmt.duration(remainingToday)) left today")
        }
    }

    private var remainingToday: TimeInterval {
        let goal = Double(app.settings.value.dailyGoalMinutes) * 60
        return max(0, goal - app.store.summary(on: Date()).scored)
    }

    private func pill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text.uppercased())
                .font(.ui(10, .semibold))
                .tracking(1)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.textDim)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    // MARK: Status

    private var status: some View {
        let copy = statusCopy
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                StatusDot(color: accent)
                SectionLabel(copy.title, color: accent)
            }
            Text(copy.line)
                .font(.serif(18, italic: true))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
            loadMeter
        }
        .animation(.easeInOut(duration: 0.3), value: copy.title)
    }

    /// How close the coach is to speaking up.
    private var loadMeter: some View {
        let load = app.session.snapshot.load
        return ThinBar(value: load, color: load > 0.75 ? Theme.ember : Theme.amber)
            .frame(width: 96)
            .opacity(load > 0.05 ? 1 : 0)
            .padding(.top, 4)
            .accessibilityLabel("Slouch pressure")
    }

    private var statusCopy: (title: String, line: String) {
        let session = app.session
        switch session.phase {
        case .paused(.lowPower):
            return ("Paused", "Low Power Mode is on. I'll pick up again when it's off.")
        case .paused(.headphonesOut):
            return ("Waiting", "Put your AirPods back in and I'll carry on.")
        default:
            break
        }
        let recentlySet = session.uprightSetAt.map { Date().timeIntervalSince($0) < 20 } ?? false
        switch session.snapshot.context {
        case .phone:
            // The screen is in the user's hand, so show the live reading and
            // say that it does not count right now.
            let title = session.snapshot.zone == .aligned ? "Aligned" : "Live preview"
            return (title, recentlySet
                ? "Upright set — the coach measures from here."
                : "I stay quiet while you're on the phone.")
        case .moving, .away:
            return ("On the move", "Paused until you settle back in.")
        case .settling:
            return ("Settling", "Finding your line again.")
        case .lookingDown:
            return ("Looking down", "Reading or writing — you have room.")
        case .focused:
            break
        }
        switch session.snapshot.zone {
        case .aligned:
            if recentlySet {
                return ("Aligned", "Upright set — the coach measures from here.")
            }
            return ("Aligned", "Tall and easy. Keep breathing.")
        case .drifting:
            return ("Drifting", "A little forward. Float the crown of your head up.")
        case .slouching:
            return ("Slouching", "Sinking in. Grow tall through your spine.")
        }
    }

    // MARK: Banner

    @ViewBuilder
    private var banner: some View {
        if let reason = app.session.breakSuggestion {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Theo suggests a reset", color: Theme.amber)
                    Text(breakLine(reason))
                        .font(.ui(14))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        smallButton("Start 30s reset", filled: true) {
                            app.session.holdForExercise(seconds: 40)
                            showReset = true
                        }
                        smallButton("Not now", filled: false) { app.session.dismissBreakSuggestion() }
                    }
                }
            }
        } else if !app.settings.value.seenLockHint {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Your coach is on")
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.mint)
                            .frame(width: 36, height: 36)
                            .background(Theme.mint.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Now lock your phone.")
                                .font(.ui(16, .semibold))
                                .foregroundStyle(Theme.text)
                            Text("The session keeps running. Theo speaks up only when you slouch, and stays quiet while you're using the phone.")
                                .font(.ui(13))
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    smallButton("Got it", filled: false) {
                        app.settings.update { $0.seenLockHint = true }
                    }
                }
            }
        }
    }

    private func breakLine(_ reason: BreakReason) -> String {
        switch reason {
        case .fatigueTrend: return "Your posture has been fading for a few minutes. Thirty seconds now saves the next hour."
        case .repeatedSlouch: return "You keep sinking back in. A short reset works better than another reminder."
        case .longSit: return "You've been sitting for a long stretch. Stand up, or take the 30 second reset."
        }
    }

    private func smallButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ui(13, .semibold))
                .foregroundStyle(filled ? .black : Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(filled ? Color.white : Theme.cardRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? Color.clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 12) {
            PillButton(title: "Upright set", icon: "checkmark", kind: .dark) {
                app.session.setUpright()
            }
            PillButton(title: "End session", icon: "stop.fill", kind: .danger) {
                app.endSession()
            }
        }
    }
}
