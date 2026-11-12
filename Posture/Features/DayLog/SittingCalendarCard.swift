import SwiftUI

/// A small calendar of the last three weeks: how long the user sat each day
/// (just the number) and the pain answer of that evening.
struct SittingCalendarCard: View {
    @Environment(AppModel.self) private var app

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = gridDays(today: today, calendar: calendar)
        let satToday = app.log.sittingSeconds(on: now, now: now)
        let tonight = app.log.pain[app.tonightKey]
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel("Sitting & pain")
                    Spacer()
                    Text("last 3 weeks")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(Theme.textFaint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.duration(satToday))
                        .font(.ui(40, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text("sat today")
                        .font(.ui(14, .medium))
                        .foregroundStyle(Theme.textDim)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(weekdayLetters.indices, id: \.self) { index in
                            Text(weekdayLetters[index])
                                .font(.ui(10, .semibold))
                                .foregroundStyle(Theme.textFaint)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(days, id: \.self) { day in
                            cell(day, today: today, now: now, calendar: calendar)
                        }
                    }
                }

                Text("Big number: time sat (h:mm), from library stays and study mode. Small number: pain that evening, 0 to 10.")
                    .font(.ui(12))
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if !app.power.hasAlwaysAccess {
                    Text("Library time is only counted on its own with location set to \"Always\". Until then, use study mode there as well.")
                        .font(.ui(12))
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    app.askAboutPain()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill").font(.system(size: 12, weight: .bold))
                        Text(tonight.map { "Tonight's pain: \($0) · change" } ?? "Log tonight's pain")
                            .font(.ui(14, .semibold))
                    }
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.cardRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    /// Three full weeks, Monday first, ending with the current week.
    private func gridDays(today: Date, calendar: Calendar) -> [Date] {
        // Calendar weekdays run 1 = Sunday ... 7 = Saturday.
        let weekday = calendar.component(.weekday, from: today)
        let sinceMonday = (weekday + 5) % 7
        guard let first = calendar.date(byAdding: .day, value: -sinceMonday - 14, to: today) else { return [] }
        return (0..<21).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private func cell(_ day: Date, today: Date, now: Date, calendar: Calendar) -> some View {
        let isToday = day == today
        let isFuture = day > today
        let seconds = isFuture ? 0 : app.log.sittingSeconds(on: day, now: now)
        let pain = isFuture ? nil : app.log.painLevel(on: day)
        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day))")
                .font(.ui(10, .semibold))
                .foregroundStyle(isToday ? Theme.mint : Theme.textFaint)
            Text(seconds >= 60 ? Fmt.hoursMinutes(seconds) : "–")
                .font(.ui(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(seconds >= 60 ? Theme.text : Theme.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(pain.map { "\($0)" } ?? " ")
                .font(.ui(10, .bold))
                .monospacedDigit()
                .foregroundStyle(pain.map { PainColor.color($0) } ?? Color.clear)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isToday ? Theme.mint.opacity(0.10) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isToday ? Theme.mint.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .opacity(isFuture ? 0.35 : 1)
    }
}

enum PainColor {
    static func color(_ level: Int) -> Color {
        if level <= 0 { return Theme.mint }
        if level <= 3 { return Theme.teal }
        if level <= 6 { return Theme.amber }
        return Theme.ember
    }
}
