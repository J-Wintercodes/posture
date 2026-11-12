import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var soonMessage: String? = nil

    var body: some View {
        let today = app.store.summary(on: Date())
        let week = app.store.lastDays(7)
        TabScroll {
            ScreenHeader(eyebrow: Fmt.headerDate(Date()), title: greeting)
            hero(today: today, week: week)
            actionCard
            todayCard(today)
            resetCard
            weekCard(week)
            baselineCard
            discover
        }
        .alert("Coming soon", isPresented: soonBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(soonMessage ?? "")
        }
    }

    private var soonBinding: Binding<Bool> {
        Binding(get: { soonMessage != nil }, set: { if !$0 { soonMessage = nil } })
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: Hero

    private func hero(today: DaySummary, week: [DaySummary]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel("Your day")
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(today.score.map { "\($0)" } ?? "—")
                            .font(.ui(68, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                        Text("/100")
                            .font(.ui(16, .medium))
                            .foregroundStyle(Theme.textFaint)
                    }
                    Text(subline(for: today.score))
                        .font(.serif(21))
                        .foregroundStyle(Theme.textDim)
                    weekPips(week)
                    Text("Day \(max(app.store.streak, 1)) · today counts")
                        .font(.ui(12, .medium))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer(minLength: 0)
                heroOrb(today: today)
            }
            statsStrip(today)
        }
        .padding(.top, 6)
    }

    private func heroOrb(today: DaySummary) -> some View {
        let live = app.session.snapshot
        let running = app.session.isRunning
        return SpineOrbView(
            pitch: running ? live.pitch : 0,
            roll: running ? live.roll : 0,
            zone: running ? live.zone : .aligned,
            diameter: 104
        )
    }

    private func subline(for score: Int?) -> String {
        guard let score else { return "A fresh page." }
        if score >= 85 { return "In a good rhythm." }
        if score >= 70 { return "Holding steady." }
        return "Room to rise."
    }

    private func weekPips(_ week: [DaySummary]) -> some View {
        HStack(spacing: 7) {
            ForEach(week) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                Circle()
                    .fill(day.isActive ? Theme.mint : Color.white.opacity(0.12))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.mint.opacity(isToday ? 0.9 : 0), lineWidth: 1)
                            .frame(width: 13, height: 13)
                    )
            }
        }
        .padding(.vertical, 3)
    }

    private func statsStrip(_ today: DaySummary) -> some View {
        let resets = app.store.resetsCount()
        return HStack(spacing: 14) {
            statColumn("Sitting", value: today.score.map { "\($0)" } ?? "—", progress: Double(today.score ?? 0) / 100, color: Theme.mint)
            statColumn("Walking", value: "—", progress: 0, color: Theme.mint)
            statColumn("Resets", value: "\(resets)/5", progress: Double(resets) / 5, color: Theme.amber)
        }
    }

    private func statColumn(_ label: String, value: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.ui(12, .medium))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text(value)
                    .font(.ui(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            ThinBar(value: progress, color: color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Action card

    private var actionCard: some View {
        let running = app.session.isRunning
        let connected = app.headphones.isConnected
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            StatusDot(color: connected ? Theme.mint : Theme.amber)
                            SectionLabel(
                                running ? "Session running" : (connected ? "AirPods connected" : "No AirPods detected"),
                                color: connected ? Theme.mint : Theme.amber
                            )
                        }
                        Text(running ? "Theo is with you." : "Ready when you are.")
                            .font(.serif(27))
                            .foregroundStyle(Theme.text)
                        Text(actionSubtext(running: running, connected: connected))
                            .font(.ui(14))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    AirPodsGlyph(connected: connected)
                }
                PillButton(
                    title: running ? "Open session" : "Start session",
                    icon: running ? "waveform" : "play.fill"
                ) {
                    app.startManualSession()
                }
                if app.power.isLowPowerMode {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.slash.fill")
                        Text("Low Power Mode is on. Sessions will not start on their own.")
                    }
                    .font(.ui(12))
                    .foregroundStyle(Theme.amber)
                }
            }
        }
    }

    private func actionSubtext(running: Bool, connected: Bool) -> String {
        if running { return "Running for \(Fmt.duration(app.session.elapsed)). Lock your phone and carry on." }
        if connected { return "Today counts. The rest is a bonus." }
        return "Put in AirPods Pro, AirPods 3 or newer, or AirPods Max."
    }

    // MARK: Today

    private func todayCard(_ today: DaySummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel("Today")
                    Spacer()
                    Text("\(Fmt.duration(today.good)) good")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(Theme.mint)
                }
                DayTimeline(minutes: today.minutes)
            }
        }
    }

    // MARK: Reset

    private var resetCard: some View {
        let done = app.store.resetsCount()
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(done == 0 ? "Your first one today" : "Reset \(min(done + 1, 5)) of 5")
                HStack(spacing: 14) {
                    UprightTorsoIllustration()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Eye + Posture Reset")
                            .font(.serif(23))
                            .foregroundStyle(Theme.text)
                        Text("30s · Neck & upper back")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                PillButton(title: "Start", icon: "play.fill") { app.showReset = true }
            }
        }
    }

    // MARK: Week

    private func weekCard(_ week: [DaySummary]) -> some View {
        let scores = week.compactMap { $0.score }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel("This week")
                    Spacer()
                    Text(average.map { "avg \($0)" } ?? "no data yet")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(Theme.textDim)
                }
                WeekDots(days: week)
            }
        }
    }

    // MARK: Baseline photo

    private var baselineCard: some View {
        Button {
            soonMessage = "The side-profile assessment is not part of this build yet."
        } label: {
            Card {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.cardRaised)
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Theme.mint)
                    }
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            SectionLabel("Progress")
                            SoonBadge()
                        }
                        Text("Take your baseline")
                            .font(.serif(21))
                            .foregroundStyle(Theme.text)
                        Text("One photo, AI assessment, and the before-shot for your weekly review.")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Discover

    private var discover: some View {
        let calibrated = app.settings.value.baseline != nil
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Discover")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    DiscoverTile(
                        title: "Calibration",
                        subtitle: calibrated ? "Done — tap to redo" : "Set your upright",
                        isSoon: false
                    ) {
                        ProfileAxisIllustration()
                    } action: {
                        app.showCalibration = true
                    }
                    DiscoverTile(
                        title: "Spine Story",
                        subtitle: "See your spine — take the first assessment",
                        isSoon: true
                    ) {
                        SpineIllustration()
                    } action: {
                        soonMessage = "Spine Story unlocks with the photo assessment."
                    }
                    DiscoverTile(
                        title: "Walking Mode",
                        subtitle: "Start tracking to enable",
                        isSoon: true
                    ) {
                        WalkingIllustration()
                    } action: {
                        soonMessage = "Walking Mode is next on the list. Desk Mode comes first."
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

private struct DiscoverTile<Art: View>: View {
    let title: String
    let subtitle: String
    let isSoon: Bool
    @ViewBuilder var art: () -> Art
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    art()
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                    if isSoon { SoonBadge() }
                }
                Text(title)
                    .font(.serif(19))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.ui(11.5))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(14)
            .frame(width: 164, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }
}
