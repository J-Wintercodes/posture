import SwiftUI

struct InsightsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let store = app.store
        let week = store.lastDays(7)
        let today = store.summary(on: Date())
        TabScroll {
            ScreenHeader(eyebrow: "The bigger picture", title: "Insights")
            forecastCard(hourly: store.hourlyProfile())
            weekCard(week)
            rhythmCard(store.calendarWeek())
            zonesCard(store.zoneGrid(days: 7))
            coachCard(week)
            todayInsight(today)
        }
    }

    // MARK: Forecast

    private func forecastCard(hourly: [Double?]) -> some View {
        let learned = hourly.compactMap { $0 }.count
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Today's forecast")
                Text(learned < 3 ? "Learning your day" : forecastHeadline(hourly))
                    .font(.serif(24))
                    .foregroundStyle(Theme.text)
                ForecastCurve(hourly: hourly)
                Text(learned < 3
                     ? "The dashed line is a typical desk day. After a few sessions it becomes yours and shows when your posture usually gives in."
                     : "Based on \(learned) hours of your own data. Dips are where a reset pays off most.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func forecastHeadline(_ hourly: [Double?]) -> String {
        var lowestHour = 0
        var lowest = Double.infinity
        for (hour, value) in hourly.enumerated() {
            if let value, value < lowest {
                lowest = value
                lowestHour = hour
            }
        }
        return "You tend to dip around \(lowestHour):00"
    }

    // MARK: Week

    private func weekCard(_ week: [DaySummary]) -> some View {
        let scores = week.compactMap { $0.score }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
        let good = week.reduce(0) { $0 + $1.good }
        let activeDays = week.filter { $0.isActive }.count
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionLabel("The week")
                    Spacer()
                    Text(average.map { "avg \($0)" } ?? "no data yet")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(Theme.textDim)
                }
                WeekDots(days: week, height: 74)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                MetricRow(items: [
                    (Fmt.duration(good), "Good time"),
                    ("\(activeDays)/7", "Active days"),
                    ("\(app.store.streak)d", "Streak")
                ])
            }
        }
    }

    // MARK: Rhythm

    private func rhythmCard(_ days: [DaySummary]) -> some View {
        let active = days.filter { $0.isActive }.count
        let target = 5
        let remaining = max(0, target - active)
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel("Rhythm")
                HStack(spacing: 0) {
                    ForEach(days) { day in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(day.isActive ? Theme.amber : Color.clear)
                                Circle()
                                    .strokeBorder(day.isActive ? Theme.amber : Color.white.opacity(0.14), lineWidth: 1.5)
                                if day.isActive {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .frame(width: 32, height: 32)
                            Text(Fmt.weekdayShort(day.date))
                                .font(.ui(10, .semibold))
                                .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.text : Theme.textFaint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(remaining == 0
                     ? "Week complete. Everything from here is a bonus."
                     : "\(remaining) more \(remaining == 1 ? "day" : "days") to complete this week")
                    .font(.serif(18, italic: true))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    // MARK: Posture zones

    private func zonesCard(_ grid: [Double]) -> some View {
        let total = grid.reduce(0, +)
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionLabel("Posture zones")
                    Spacer()
                    Text("last 7 days")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(Theme.textFaint)
                }
                PostureZonesHeatmap(cells: grid)
                    .frame(maxWidth: 330)
                    .frame(maxWidth: .infinity)
                Text(zonesLine(grid, total: total))
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zonesLine(_ grid: [Double], total: Double) -> String {
        guard total > 60 else {
            return "Where your head spends its time. The centre is your calibrated upright; tiles light up as you track."
        }
        // Rows 0...2 are more than 7.5° forward of the baseline.
        let forward = grid.prefix(ZoneGrid.side * 3).reduce(0, +)
        let share = Int((forward / total * 100).rounded())
        // Columns 0...2 lean left, columns 5...7 lean right.
        var left = 0.0
        var right = 0.0
        for (index, seconds) in grid.enumerated() {
            let column = index % ZoneGrid.side
            if column < 3 {
                left += seconds
            } else if column > 4 {
                right += seconds
            }
        }
        var line = "\(share)% of your tracked time was spent tilted forward."
        if left > total * 0.25, left > right * 1.6 {
            line += " You also lean to the left a lot — check where your screen and notes sit."
        } else if right > total * 0.25, right > left * 1.6 {
            line += " You also lean to the right a lot — check where your screen and notes sit."
        }
        return line
    }

    // MARK: Coach

    private func coachCard(_ week: [DaySummary]) -> some View {
        let activeDays = week.filter { $0.isActive }.count
        let ready = activeDays >= 3
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Coach")
                Text(ready ? "Your weekly review" : "Weekly review")
                    .font(.serif(24))
                    .foregroundStyle(Theme.text)
                Text(ready ? weeklyReview(week) : "Unlocks after 3 active days. \(max(0, 3 - activeDays)) to go.")
                    .font(.ui(14))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                if !ready {
                    ThinBar(value: Double(activeDays) / 3, color: Theme.amber)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func weeklyReview(_ week: [DaySummary]) -> String {
        let active = week.filter { $0.score != nil }
        guard let best = active.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }),
              let worst = active.min(by: { ($0.score ?? 0) < ($1.score ?? 0) }) else { return "" }
        let nudges = week.reduce(0) { $0 + $1.nudges }
        let bestDay = Fmt.weekdayShort(best.date)
        let worstDay = Fmt.weekdayShort(worst.date)
        return "Best day: \(bestDay) at \(best.score ?? 0). Toughest: \(worstDay) at \(worst.score ?? 0). Theo spoke up \(nudges) times this week."
    }

    // MARK: Today

    private func todayInsight(_ today: DaySummary) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Today's insight")
                    Text(today.score == nil ? "Nothing tracked yet" : "Today's avg")
                        .font(.serif(22))
                        .foregroundStyle(Theme.text)
                    Text(today.score == nil
                         ? "Start a session and this fills in."
                         : "\(Int((today.goodFraction * 100).rounded()))% of \(Fmt.duration(today.scored)) in good posture, \(today.nudges) \(today.nudges == 1 ? "nudge" : "nudges").")
                        .font(.ui(13))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let score = today.score {
                    Text("\(score)")
                        .font(.ui(46, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.score(score))
                }
            }
        }
    }
}
