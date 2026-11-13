import SwiftUI

/// Full-screen overlay while a session is live. Built to be glanced at once
/// and then locked away: the session keeps running without it.
///
/// The parts that follow every reading (the orb, the slouch meter) are small
/// views of their own. The rest of the screen only reads what changes now
/// and then, so it is not redrawn twelve times a second.
struct LiveSessionView: View {
    @Environment(AppModel.self) private var app
    @State private var glow = false

    var body: some View {
        @Bindable var app = app
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                pills
                    .padding(.top, 14)
                middle
                buttons
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .overlay(borderGlow)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
        }
        .onChange(of: app.session.isRunning) { _, running in
            // A session can end on its own (AirPods out for too long, or
            // paused for too long). Do not leave a dead screen behind.
            if !running { app.showLive = false }
        }
        .sheet(item: $app.activeRoutine) { routine in
            RoutinePlayerView(routine: routine)
                .environment(app)
                .preferredColorScheme(.dark)
        }
    }

    private var accent: Color {
        app.session.isResting ? Theme.textFaint : Theme.zone(app.session.zone)
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
        HStack(spacing: 0) {
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
            // Same width as the clock, so the title sits in the middle.
            .frame(width: 76, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                StatusDot(color: accent)
                SectionLabel(phaseTitle, color: accent)
            }
            Spacer(minLength: 0)
            clock
        }
        .padding(.top, 8)
    }

    /// Counts up from the start of the session. The system draws it, so it
    /// neither skips nor repeats a second the way a once-a-second timer does.
    private var clock: some View {
        Group {
            if let startedAt = app.session.startedAt {
                Text(startedAt, style: .timer)
            } else {
                Text("0:00")
            }
        }
        .font(.ui(16, .semibold))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(Theme.text)
        .frame(width: 76, alignment: .trailing)
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
        let sitting = app.session.isSitting
        return HStack(spacing: 8) {
            pill(sitting ? "checkmark.circle.fill" : "figure.walk", sitting ? "Sitting" : "Not sitting yet")
            pill(mode == .silent ? "bell.slash.fill" : "bell.fill", mode.title)
            switch app.session.sensorSide {
            case .left: pill("airpodspro", "Left AirPod")
            case .right: pill("airpodspro", "Right AirPod")
            case .unknown: pill("hourglass", "\(Fmt.duration(remainingToday)) left today")
            }
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

    // MARK: Middle

    /// Orb, status and banner. They scroll when they do not fit (a small
    /// phone, a tall banner), so the bar on top and the buttons at the
    /// bottom can never be pushed off the screen.
    private var middle: some View {
        let hasBanner = app.day.due != nil || !app.settings.value.seenLockHint
        return GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    LiveOrb(diameter: hasBanner ? 132 : 176)
                    status
                        .padding(.top, 20)
                    Spacer(minLength: 12)
                    banner
                        .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
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
            LoadMeter()
            smallButton("Play both beeps", filled: false) { app.session.playTestTones() }
                .padding(.top, 6)
        }
        .animation(.easeInOut(duration: 0.3), value: copy.title)
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
        switch session.context {
        case .phone:
            // The screen is in the user's hand, so show the live reading and
            // say that it does not count right now.
            let title = session.zone == .aligned ? "Aligned" : "Live preview"
            return (title, recentlySet
                ? "Upright set — the coach measures from here."
                : "I stay quiet while the phone is in your hand. Put it down and the beeps are back.")
        case .moving, .away:
            return ("On the move", "Paused until you settle back in.")
        case .settling:
            return ("Settling", "Finding your line again.")
        case .lookingDown:
            return ("Looking down", "Reading or writing — you have room.")
        case .focused:
            break
        }
        switch session.zone {
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
        if let due = app.day.due {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Time for: \(due.advice.routine.name.en)", color: Theme.amber)
                    Text(AdviceText.body(due.advice, trigger: due.trigger, language: .en))
                        .font(.ui(14))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        smallButton("Start · \(due.advice.routine.durationLabel)", filled: true) {
                            app.open(due.advice.routine)
                        }
                        smallButton("Not now", filled: false) { app.day.dismissDue() }
                    }
                }
            }
        } else if !app.settings.value.seenLockHint {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.mint)
                        SectionLabel("Now lock your phone", color: Theme.mint)
                    }
                    Text("The session keeps running. A low beep means you are slouching, a brighter one means you fixed it. It stays quiet while the phone is in your hand.")
                        .font(.ui(13))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    smallButton("Got it", filled: false) {
                        app.settings.update { $0.seenLockHint = true }
                    }
                }
            }
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

private extension SessionManager {
    /// Nothing is being scored: the session is paused, or the user is on
    /// their feet.
    var isResting: Bool {
        if case .paused = phase { return true }
        return context == .moving || context == .away
    }
}

/// The orb of the live screen. Redrawn with every reading.
private struct LiveOrb: View {
    @Environment(AppModel.self) private var app
    var diameter: CGFloat

    var body: some View {
        let session = app.session
        let live = session.snapshot
        SpineOrbView(
            pitch: live.pitch,
            roll: live.roll,
            zone: live.zone,
            score: live.score,
            diameter: diameter,
            dimmed: session.isResting
        )
    }
}

/// How close the coach is to speaking up. Redrawn with every reading.
private struct LoadMeter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let load = app.session.snapshot.load
        ThinBar(value: load, color: load > 0.75 ? Theme.ember : Theme.amber)
            .frame(width: 96)
            .opacity(load > 0.05 ? 1 : 0)
            .padding(.top, 4)
            .accessibilityLabel("Slouch pressure")
    }
}
