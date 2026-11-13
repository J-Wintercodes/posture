import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var soonMessage: String? = nil
    @State private var nameDraft = ""

    var body: some View {
        let today = app.store.summary(on: Date())
        let week = app.store.lastDays(7)
        TabScroll {
            ScreenHeader(eyebrow: Fmt.headerDate(Date()), title: greeting)
            hero(today: today)
            Group {
                if showsNameCard {
                    nameCard
                }
                if showsPainCard {
                    painCard
                }
            }
            nowCard
            actionCard
            todayCard(today)
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
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<18: base = "Good afternoon"
        default: base = "Good evening"
        }
        if let name = app.settings.value.greetingName {
            return "\(base), \(name)"
        }
        return base
    }

    // MARK: Name

    /// Asked once, for people who set the app up before it asked.
    private var showsNameCard: Bool {
        let config = app.settings.value
        return config.greetingName == nil && !config.askedForName
    }

    private var nameCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("One question", color: Theme.mint)
                Text("What should I call you?")
                    .font(.serif(25))
                    .foregroundStyle(Theme.text)
                TextField("Your first name", text: $nameDraft)
                    .font(.ui(17))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { saveName() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                PillButton(title: "Save", icon: "checkmark") { saveName() }
                Button("Not now") {
                    app.settings.update { $0.askedForName = true }
                }
                .font(.ui(14, .medium))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func saveName() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        app.settings.update { value in
            value.userName = name
            value.askedForName = true
        }
    }

    // MARK: Hero

    /// The orb in the middle is the posture of this moment. To its left, the
    /// average of the day.
    private func hero(today: DaySummary) -> some View {
        let diameter: CGFloat = 112
        return ZStack(alignment: .topLeading) {
            LivePostureOrb(diameter: diameter)
                .frame(maxWidth: .infinity)
            // As tall as the orb, so the number sits level with its centre.
            dayAverage(today)
                .frame(height: diameter * 1.14)
        }
        .padding(.top, 6)
    }

    private func dayAverage(_ today: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(today.score.map { "\($0)" } ?? "—")
                .font(.ui(40, .semibold))
                .monospacedDigit()
                .foregroundStyle(today.score == nil ? Theme.textFaint : Theme.text)
            Text("DAY AVG")
                .font(.ui(10, .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.textFaint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(today.score.map { "Average of the day \($0)" } ?? "No average yet today")
    }

    // MARK: Before bed

    /// From two hours before bedtime until the question is answered.
    private var showsPainCard: Bool {
        let config = app.settings.value
        guard config.painCheckEnabled else { return false }
        let now = Date()
        let evening = DayKey.eveningDay(for: now)
        guard app.log.painLevel(on: evening) == nil else { return false }
        let bedtime = DayKey.bedtime(on: evening, minutes: config.bedMinutes)
        return now >= bedtime.addingTimeInterval(-2 * 3600)
    }

    private var painCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.mint)
                    SectionLabel("Before bed", color: Theme.mint)
                }
                Text("Any pain today?")
                    .font(.serif(25))
                    .foregroundStyle(Theme.text)
                Text("One number from 0 to 10. It goes into your journal next to the time you sat.")
                    .font(.ui(14))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: "Answer", icon: "checkmark", kind: .dark) { app.askAboutPain() }
            }
        }
    }

    // MARK: Right now

    /// What the calendar and the location say. What to do about it lives in
    /// the Routines tab.
    private var nowCard: some View {
        let context = app.day.context
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StatusDot(color: Theme.mint)
                    SectionLabel("Right now", color: Theme.mint)
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
                if context.situation == .gym {
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
            return "At \(context.placeName ?? "university")"
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

    /// Study and gym entries still to come today, as the app reads them.
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
                        Image(systemName: planIcon(event.kind))
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

    private func planIcon(_ kind: EventKind) -> String {
        switch kind {
        case .gym: return "dumbbell.fill"
        case .home: return "house.fill"
        case .library, .other: return "building.columns.fill"
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
                     ? "Calendar access is off. Tap to allow it in Settings, so your study blocks and the gym are known."
                     : "Tap to connect your calendar, so your study blocks and the gym are known.")
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
        let copy = actionCopy(running: running, reminders: reminders, connected: connected)
        let statusColor = copy.isActive ? Theme.mint : Theme.textDim
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            StatusDot(color: statusColor)
                            SectionLabel(copy.label, color: statusColor)
                        }
                        Text(copy.title)
                            .font(.serif(27))
                            .foregroundStyle(Theme.text)
                        Group {
                            if let detail = copy.detail {
                                Text(detail)
                            } else if running {
                                RunningForText()
                            } else {
                                Text(actionSubtext(reminders: reminders))
                            }
                        }
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
                    PillButton(title: "Stop study mode", icon: "book.closed.fill", kind: .dark) { app.stopReminders() }
                    PillButton(title: "Track posture with AirPods", icon: "play.fill", kind: .dark) { app.startManualSession() }
                } else {
                    PillButton(title: "Start study mode", icon: "book.fill") { app.startReminders() }
                    PillButton(title: "Track posture with AirPods", icon: "play.fill", kind: .dark) { app.startManualSession() }
                }
                if let blocked = autoBlockText {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "pause.circle.fill")
                        Text(blocked)
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

    private struct ActionCopy {
        var label: String
        var title: String
        /// Nil where the text below the title has a view of its own.
        var detail: String?
        var isActive: Bool
    }

    private func actionCopy(running: Bool, reminders: Bool, connected: Bool) -> ActionCopy {
        let session = app.session
        if running, session.isAutoStarted {
            // Study mode at a library runs on its own. Say what it is
            // waiting for.
            switch session.phase {
            case .paused(.headphonesOut):
                return ActionCopy(
                    label: "Study mode · waiting",
                    title: "Waiting for your AirPods.",
                    detail: "Put them in and sit down. Study mode starts on its own, pauses when you get up or take them out, and carries on when you are back.",
                    isActive: false
                )
            case .paused(.lowPower):
                return ActionCopy(
                    label: "Study mode · paused",
                    title: "Paused to save battery.",
                    detail: "It picks up again when Low Power Mode is off.",
                    isActive: false
                )
            case .live, .idle:
                if session.isSitting {
                    return ActionCopy(
                        label: "Study mode",
                        title: "Theo is with you.",
                        detail: "This counts as sitting. It pauses when you get up or take your AirPods out.",
                        isActive: true
                    )
                }
                return ActionCopy(
                    label: "Study mode · waiting",
                    title: "Waiting until you sit.",
                    detail: "It counts once you have been still for half a minute.",
                    isActive: false
                )
            }
        }
        if running {
            return ActionCopy(label: "Session running", title: "Theo is with you.", detail: nil, isActive: true)
        }
        if reminders {
            return ActionCopy(label: "Study mode", title: "Study mode is on.", detail: nil, isActive: true)
        }
        return ActionCopy(
            label: connected ? "AirPods connected" : "No AirPods needed",
            title: "Ready when you are.",
            detail: nil,
            isActive: connected
        )
    }

    /// At a library, but study mode did not set itself up: say why.
    private var autoBlockText: String? {
        guard let block = app.autoStudyBlock else { return nil }
        switch block {
        case .lowPowerMode:
            return "Low Power Mode is on, so study mode does not start on its own here."
        case .lowBattery:
            return "The battery is low, so study mode does not start on its own here."
        case .snoozed:
            let until = app.snoozedUntil.map { " until \(Fmt.time($0))" } ?? ""
            return "You stopped it, so nothing starts on its own\(until). Tap \"Track posture with AirPods\" to switch it back on."
        case .disabled, .sessionActive, .notAtFocusPlace:
            return nil
        }
    }

    private func actionSubtext(reminders: Bool) -> String {
        if reminders {
            return "This time counts as sitting, less the walking your iPhone notices. No reminders without AirPods, no sensors, no audio: it costs next to no battery."
        }
        let config = app.settings.value
        let atLibraries = config.autoStudy && config.places.contains { $0.kind.startsOnArrival }
        let lead = atLibraries
            ? "At your libraries nothing has to be started: study mode runs once you sit there with your AirPods in. Anywhere else: "
            : ""
        return lead + "Study mode counts the time as sitting, quietly and at next to no battery, and Siri can start it. Tracking watches your posture through the AirPods, checks in when you need a break and uses more."
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

/// The orb with the posture of this moment: the live score inside, the zone
/// as a word below. Its own view, so the twelve readings a second redraw
/// this and nothing else on the screen.
private struct LivePostureOrb: View {
    @Environment(AppModel.self) private var app
    var diameter: CGFloat = 112

    var body: some View {
        let session = app.session
        let live = session.snapshot
        let state = currentState(session)
        VStack(spacing: 12) {
            SpineOrbView(
                pitch: state.isLive ? live.pitch : 0,
                roll: state.isLive ? live.roll : 0,
                zone: state.isLive ? live.zone : .aligned,
                score: state.isLive ? live.score : nil,
                placeholder: "–",
                diameter: diameter,
                dimmed: !state.isLive
            )
            HStack(spacing: 8) {
                StatusDot(color: state.color)
                SectionLabel(state.title, color: state.color)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if session.isRunning { app.showLive = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.isLive ? "Posture right now \(live.score), \(state.title)" : state.title)
    }

    private struct LiveState {
        var title: String
        var color: Color
        /// False while there is no reading worth showing.
        var isLive: Bool
    }

    private func currentState(_ session: SessionManager) -> LiveState {
        switch session.phase {
        case .idle:
            return LiveState(title: "No session", color: Theme.textFaint, isLive: false)
        case .paused(.lowPower):
            return LiveState(title: "Paused", color: Theme.textFaint, isLive: false)
        case .paused(.headphonesOut):
            return LiveState(title: "AirPods out", color: Theme.textFaint, isLive: false)
        case .live:
            break
        }
        let zone = session.snapshot.zone
        switch session.snapshot.context {
        case .moving, .away:
            return LiveState(title: "On the move", color: Theme.textFaint, isLive: false)
        case .settling:
            return LiveState(title: "Settling", color: Theme.zone(zone), isLive: true)
        case .lookingDown:
            return LiveState(title: "Looking down", color: Theme.zone(zone), isLive: true)
        case .phone, .focused:
            break
        }
        switch zone {
        case .aligned:
            return LiveState(title: "Aligned", color: Theme.mint, isLive: true)
        case .drifting:
            return LiveState(title: "Drifting", color: Theme.amber, isLive: true)
        case .slouching:
            return LiveState(title: "Slouching", color: Theme.ember, isLive: true)
        }
    }
}

/// "Running for 14m." Reads the session clock on its own, so the seconds
/// ticking by do not redraw the whole home screen.
private struct RunningForText: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Text("Running for \(Fmt.duration(app.session.elapsed)). Lock your phone and carry on.")
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
