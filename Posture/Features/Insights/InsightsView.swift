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
            zonesCard(store.zoneGrid(days: 7))
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

    // MARK: Last seven days

    /// A look back, nothing to complete: there is no weekly target.
    private func weekCard(_ week: [DaySummary]) -> some View {
        let scores = week.compactMap { $0.score }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
        let good = week.reduce(0) { $0 + $1.good }
        let tracked = week.reduce(0) { $0 + $1.scored }
        let sessions = week.reduce(0) { $0 + $1.sessions.count }
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionLabel("Last 7 days")
                    Spacer()
                    Text(average.map { "avg \($0)" } ?? "no data yet")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(Theme.textDim)
                }
                WeekDots(days: week, height: 74)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                MetricRow(items: [
                    (Fmt.duration(good), "Good time"),
                    (Fmt.duration(tracked), "Tracked"),
                    ("\(sessions)", "Sessions")
                ])
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
