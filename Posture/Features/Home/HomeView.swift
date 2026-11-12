import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var soonMessage: String? = nil

    var body: some View {
        let today = app.store.summary(on: Date())
        let week = app.store.lastDays(7)
        TabScroll {
            ScreenHeader(eyebrow: Fmt.headerDate(Date()), title: greeting)
            hero(today: today)
            nowCard
            actionCard
            todayCard(today)
            routinesCard
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

    private func hero(today: DaySummary) -> some View {
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

    // MARK: Right now

    /// What the calendar and the location say, and what is needed for it.
    private var nowCard: some View {
        let day = app.day
        let context = day.context
        let isDue = day.due != nil
        let advice = day.due?.advice ?? day.suggestion
        let accent = isDue ? Theme.amber : Theme.mint
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StatusDot(color: accent)
                    SectionLabel(isDue ? "Check-in due" : "Right now", color: accent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(situationTitle(context))
                        .font(.serif(27))
                        .foregroundStyle(Theme.text)
                    Text(situationDetail(context))
                        .font(.ui(14))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                planRows
                Rectangle().fill(Theme.stroke).frame(height: 1)
                if let advice {
                    adviceBlock(advice)
                } else {
                    Text("Training time. I stay quiet until you are done.")
                        .font(.serif(18, italic: true))
                        .foregroundStyle(Theme.textDim)
                }
                setupHints
            }
        }
    }

    private func situationTitle(_ context: DayContext) -> String {
        switch context.situation {
        case .home:
            return "At home"
        case .library:
            return "At \(context.placeName ?? "the library")"
        case .uni:
            return context.source == .calendar ? "In a lecture" : "At \(context.placeName ?? "university")"
        case .gym:
            return "At the gym"
        case .elsewhere:
            if let name = context.placeName { return "At \(name)" }
            return "Out and about"
        }
    }

    private func situationDetail(_ context: DayContext) -> String {
        var parts: [String] = []
        switch context.source {
        case .location:
            if context.calendarOverruled, let event = context.event {
                parts.append("Your calendar says \"\(event.title)\", but your location says you are here.")
            } else {
                parts.append("Confirmed by your location.")
            }
        case .calendar:
            if let event = context.event {
                parts.append("From your calendar: \"\(event.title)\" until \(Fmt.time(event.end)).")
            }
        case .none:
            if context.calendarOverruled, let event = context.event {
                parts.append("Your calendar says \"\(event.title)\", but you are not there.")
            } else if app.settings.value.places.isEmpty {
                parts.append("No saved place here.")
            } else {
                parts.append("Not at one of your saved places.")
            }
        }
        if let minutes = context.gymInMinutes, let start = context.gymAt {
            parts.append("Gym at \(Fmt.time(start)), in \(minutes) min.")
        } else if context.afterGym {
            parts.append("Training is done for today.")
        }
        return parts.joined(separator: " ")
    }

    /// University and gym entries still to come today, as the app reads them.
    @ViewBuilder
    private var planRows: some View {
        let now = Date()
        let upcoming = Array(
            app.calendar.events
                .filter { $0.end > now && Calendar.current.isDateInToday($0.start) }
                .prefix(3)
        )
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(upcoming) { event in
                    HStack(spacing: 10) {
                        Text(Fmt.time(event.start))
                            .font(.ui(13, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(event.start <= now ? Theme.mint : Theme.textDim)
                            .frame(width: 44, alignment: .leading)
                        Image(systemName: event.kind == .gym ? "dumbbell.fill" : "graduationcap.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textFaint)
                            .frame(width: 18)
                        Text(event.title)
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func adviceBlock(_ advice: Advice) -> some View {
        let hint = AdviceText.hint(advice, language: .en)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: advice.routine.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.mint)
                    .frame(width: 52, height: 52)
                    .background(Theme.mint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(advice.routine.name.en)
                        .font(.serif(23))
                        .foregroundStyle(Theme.text)
                    Text("\(advice.routine.durationLabel) · \(advice.routine.focus)")
                        .font(.ui(13))
                        .foregroundStyle(Theme.textDim)
                }
            }
            if !hint.isEmpty {
                Text(hint)
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PillButton(title: "Start", icon: "play.fill") { app.open(advice.routine) }
        }
    }

    /// What is still missing for the plan to work.
    @ViewBuilder
    private var setupHints: some View {
        if app.settings.value.calendarEnabled, !app.calendar.hasAccess {
            Button {
                connectCalendar()
            } label: {
                Text(app.calendar.wasDenied
                     ? "Calendar access is off. Tap to allow it in Settings, so lectures and the gym are known."
                     : "Tap to connect your calendar, so lectures and the gym are known.")
                    .font(.ui(13, .medium))
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.leading)
            }
        }
        if app.settings.value.places.isEmpty {
            Button {
                app.showProfile = true
            } label: {
                Text("Save your home and your libraries in the profile for the location check.")
                    .font(.ui(13, .medium))
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private func connectCalendar() {
        if app.calendar.wasDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            Task { await app.calendar.requestAccess() }
        }
    }

    // MARK: Action card

    private var actionCard: some View {
        let running = app.session.isRunning
        let reminders = app.day.mode == .light
        let connected = app.headphones.isConnected
        let statusColor = (running || reminders || connected) ? Theme.mint : Theme.textDim
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            StatusDot(color: statusColor)
                            SectionLabel(actionLabel(running: running, reminders: reminders, connected: connected), color: statusColor)
                        }
                        Text(running ? "Theo is with you." : (reminders ? "Check-ins are on." : "Ready when you are."))
                            .font(.serif(27))
                            .foregroundStyle(Theme.text)
                        Text(actionSubtext(running: running, reminders: reminders))
                            .font(.ui(14))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    AirPodsGlyph(connected: connected)
                }
                if running {
                    PillButton(title: "Open session", icon: "waveform") { app.startManualSession() }
                } else if reminders {
                    PillButton(title: "Stop reminders", icon: "bell.slash.fill", kind: .dark) { app.stopReminders() }
                    PillButton(title: "Track posture with AirPods", icon: "play.fill", kind: .dark) { app.startManualSession() }
                } else {
                    PillButton(title: "Start reminders", icon: "bell.fill") { app.startReminders() }
                    PillButton(title: "Track posture with AirPods", icon: "play.fill", kind: .dark) { app.startManualSession() }
                }
                if reminders, !app.notificationsOn {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "bell.slash.fill")
                        Text("Notifications are off for Posture, so check-ins cannot reach you. Allow them in the iOS Settings.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.ui(12))
                    .foregroundStyle(Theme.amber)
                }
                if running, app.power.isLowPowerMode {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.slash.fill")
                        Text("Low Power Mode is on. Tracking is paused until it is off.")
                    }
                    .font(.ui(12))
                    .foregroundStyle(Theme.amber)
                }
            }
        }
    }

    private func actionLabel(running: Bool, reminders: Bool, connected: Bool) -> String {
        if running { return "Session running" }
        if reminders { return "Reminders only" }
        return connected ? "AirPods connected" : "No AirPods needed"
    }

    private func actionSubtext(running: Bool, reminders: Bool) -> String {
        let minutes = app.settings.value.checkInMinutes
        if running {
            return "Running for \(Fmt.duration(app.session.elapsed)). Lock your phone and carry on."
        }
        if reminders {
            let next = app.day.nextCheckInAt.map { "Next check-in at \(Fmt.time($0)). " } ?? ""
            return next + "No sensors, no audio: this costs next to no battery."
        }
        return "Reminders check in every \(minutes) minutes and cost next to no battery. Tracking watches your posture through the AirPods and uses more."
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

    // MARK: Routines

    private var routinesCard: some View {
        let done = app.store.resetsCount()
        let situation = app.day.context.situation
        let hasHome = app.settings.value.places.contains { $0.kind == .home }
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel("Routines")
                    Spacer()
                    Text("\(done) done today")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(Theme.textDim)
                }
                VStack(spacing: 4) {
                    ForEach(RoutineCatalog.all) { routine in
                        routineRow(routine, available: Advisor.isAvailable(routine, in: situation))
                    }
                }
                if situation != .home {
                    Text(hasHome
                         ? "The floor routines for back and nervous system unlock when you are at home."
                         : "The floor routines for back and nervous system are for home. Save your home in the profile to unlock them.")
                        .font(.ui(12))
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func routineRow(_ routine: Routine, available: Bool) -> some View {
        Button {
            app.open(routine)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: routine.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(available ? Theme.mint : Theme.textFaint)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.05), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name.en)
                        .font(.ui(15, .semibold))
                        .foregroundStyle(available ? Theme.text : Theme.textDim)
                    Text("\(routine.durationLabel) · \(routine.focus)")
                        .font(.ui(12))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if available {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill").font(.system(size: 9, weight: .bold))
                        Text("HOME").font(.ui(9, .bold)).tracking(1.2)
                    }
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!available)
    }

    // MARK: Last seven days

    private func weekCard(_ week: [DaySummary]) -> some View {
        let scores = week.compactMap { $0.score }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel("Last 7 days")
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
                        Text("One photo, AI assessment, and the before-shot to compare against later.")
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
