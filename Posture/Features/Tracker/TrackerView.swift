import SwiftUI

struct TrackerView: View {
    @Environment(AppModel.self) private var app
    @State private var selected = Calendar.current.startOfDay(for: Date())

    var body: some View {
        let days = app.store.lastDays(7)
        let day = app.store.summary(on: selected)
        TabScroll {
            ScreenHeader(eyebrow: "One day at a time", title: "Your journal")
            SittingCalendarCard()
            SectionLabel("Tracked posture")
                .padding(.top, 4)
            calendarStrip(days)
            summaryCard(day)
            chapters(day)
        }
    }

    // MARK: Calendar strip

    private func calendarStrip(_ days: [DaySummary]) -> some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selected)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selected = day.date }
                } label: {
                    VStack(spacing: 8) {
                        Text(Fmt.weekdayLetter(day.date))
                            .font(.ui(10, .semibold))
                            .foregroundStyle(Theme.textFaint)
                        ZStack {
                            Circle()
                                .fill(isSelected ? Theme.mint.opacity(0.14) : Theme.card)
                            Circle()
                                .strokeBorder(isSelected ? Theme.mint : Theme.stroke, lineWidth: isSelected ? 1.5 : 1)
                            if isSelected {
                                Circle()
                                    .strokeBorder(Theme.mint.opacity(0.35), lineWidth: 1)
                                    .padding(-4)
                            }
                            Text("\(Calendar.current.component(.day, from: day.date))")
                                .font(.ui(15, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Theme.text : Theme.textDim)
                        }
                        .frame(width: 38, height: 38)
                        Circle()
                            .fill(day.isActive ? Theme.amber : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Day summary

    private func summaryCard(_ day: DaySummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text(title(for: day))
                        .font(.serif(26))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    if let score = day.score {
                        Text("\(score)")
                            .font(.ui(46, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.score(score))
                    }
                }
                DayTimeline(minutes: day.minutes)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                MetricRow(items: [
                    ("\(Int((day.goodFraction * 100).rounded()))%", "Good"),
                    ("\(day.sessions.count)", "Sessions"),
                    (Fmt.duration(day.scored), "Tracked")
                ])
            }
        }
    }

    private func title(for day: DaySummary) -> String {
        guard let score = day.score else {
            return Calendar.current.isDateInToday(day.date) ? "The page is still blank" : "A day off"
        }
        if score >= 85 { return "A steady, strong day" }
        if score >= 70 { return "A solid day with a few dips" }
        return "A heavy day. Tomorrow is lighter."
    }

    // MARK: Chapters

    @ViewBuilder
    private func chapters(_ day: DaySummary) -> some View {
        SectionLabel("Chapters")
            .padding(.top, 4)
        if day.sessions.isEmpty {
            Text("Sessions you track on this day show up here, one chapter each.")
                .font(.ui(14))
                .foregroundStyle(Theme.textFaint)
        } else {
            VStack(spacing: 10) {
                ForEach(day.sessions) { session in
                    chapterRow(session)
                }
            }
        }
    }

    private func chapterRow(_ session: SessionRecord) -> some View {
        Card(padding: 16) {
            HStack(spacing: 12) {
                StatusDot(color: Theme.score(session.averageScore))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Fmt.time(session.start)) – \(Fmt.time(session.end)) (\(Fmt.duration(session.duration)))")
                        .font(.ui(15, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text(detail(for: session))
                        .font(.ui(12))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                ScoreBadge(score: session.averageScore)
            }
        }
    }

    private func detail(for session: SessionRecord) -> String {
        var parts: [String] = []
        if let place = session.placeName { parts.append(place) }
        if session.autoStarted { parts.append("auto-started") }
        parts.append("\(session.nudges) \(session.nudges == 1 ? "nudge" : "nudges")")
        return parts.joined(separator: " · ")
    }
}
