import SwiftUI

/// Dashed day line from 6 to 24 o'clock with a tick for every tracked minute.
struct DayTimeline: View {
    var minutes: [MinuteBucket]

    private let startMinute = 6.0 * 60
    private let endMinute = 24.0 * 60

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                let y = size.height / 2
                var base = Path()
                base.move(to: CGPoint(x: 0, y: y))
                base.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(base, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))

                let span = CGFloat(endMinute - startMinute)
                let minuteWidth: CGFloat = size.width / span
                let tickWidth: CGFloat = max(1.5, minuteWidth)
                for bucket in minutes where bucket.scored > 0 {
                    let offset = CGFloat(bucket.minute) - CGFloat(startMinute)
                    guard offset >= 0, offset <= span else { continue }
                    let good = bucket.average >= 80
                    let height: CGFloat = good ? 14 : 9
                    let rect = CGRect(x: offset * minuteWidth, y: y - height / 2, width: tickWidth, height: height)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: tickWidth / 2),
                        with: .color(good ? Theme.mint : Theme.amber)
                    )
                }
            }
            .frame(height: 22)

            HStack {
                Text("6")
                Spacer()
                Text("NOON")
                Spacer()
                Text("18")
                Spacer()
                Text("24")
            }
            .font(.ui(9.5, .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.textFaint)
        }
        .accessibilityLabel("Timeline of today's tracked minutes")
    }
}

/// Seven days as dots: height is the score, the glowing dot is today.
struct WeekDots: View {
    var days: [DaySummary]
    var height: CGFloat = 62

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(days) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 2, height: height)
                        dot(for: day, isToday: isToday)
                            .offset(y: -lift(for: day))
                    }
                    .frame(height: height + 8)
                    Text(Fmt.weekdayLetter(day.date))
                        .font(.ui(10, .semibold))
                        .foregroundStyle(isToday ? Theme.text : Theme.textFaint)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func lift(for day: DaySummary) -> CGFloat {
        guard let score = day.score else { return 0 }
        let fraction = min(max(Double(score) - 40, 0) / 60, 1)
        return height * fraction
    }

    @ViewBuilder
    private func dot(for day: DaySummary, isToday: Bool) -> some View {
        if let score = day.score {
            Circle()
                .fill(Theme.score(score))
                .frame(width: isToday ? 11 : 8, height: isToday ? 11 : 8)
                .shadow(color: Theme.score(score).opacity(isToday ? 0.9 : 0), radius: 7)
        } else {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 5, height: 5)
        }
    }
}

/// The "fever curve" of a day: when posture usually holds and when it dips.
/// Hours without enough data fall back to a typical desk day, drawn dashed.
struct ForecastCurve: View {
    var hourly: [Double?]

    var learnedHours: Int { hourly.compactMap { $0 }.count }

    static func typical(hour: Double) -> Double {
        let lunchDip = 10 * exp(-pow((hour - 14.5) / 2.2, 2))
        let eveningDip = 7 * exp(-pow((hour - 21) / 2.4, 2))
        return 88 - lunchDip - eveningDip
    }

    var body: some View {
        let isLearning = learnedHours < 3
        VStack(spacing: 6) {
            Canvas { context, size in
                var points: [CGPoint] = []
                for hour in 6...24 {
                    let known: Double? = hour < hourly.count ? hourly[hour] : nil
                    let value: Double = known ?? Self.typical(hour: Double(hour))
                    let level: Double = 1 - min(max(value - 50, 0) / 50, 1)
                    let x: CGFloat = size.width * CGFloat(hour - 6) / 18
                    let y: CGFloat = size.height * CGFloat(level)
                    points.append(CGPoint(x: x, y: y))
                }
                let line = Self.smooth(points)

                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [Theme.mint.opacity(isLearning ? 0.08 : 0.22), .clear]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
                context.stroke(
                    line,
                    with: .color(Theme.mint.opacity(isLearning ? 0.55 : 1)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: isLearning ? [5, 6] : [])
                )

                // "Now" marker
                let hourNow = CGFloat(Fmt.dateToMinutes(Date())) / 60
                if hourNow >= 6 {
                    let x: CGFloat = size.width * (hourNow - 6) / 18
                    var marker = Path()
                    marker.move(to: CGPoint(x: x, y: 0))
                    marker.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(marker, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .frame(height: 84)

            HStack {
                Text("6")
                Spacer()
                Text("NOON")
                Spacer()
                Text("18")
                Spacer()
                Text("24")
            }
            .font(.ui(9.5, .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.textFaint)
        }
    }

    private static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// 8 x 8 map of head tilt: forward at the top, backward at the bottom,
/// left and right roll on the horizontal axis. Brighter means more time.
struct PostureZonesHeatmap: View {
    var cells: [Double]

    var body: some View {
        let peak = max(cells.max() ?? 0, 0.001)
        VStack(spacing: 8) {
            axisLabel("FORWARD +30°")
            HStack(spacing: 8) {
                axisLabel("LEFT")
                    .frame(width: 34)
                grid(peak: peak)
                axisLabel("RIGHT")
                    .frame(width: 34)
            }
            axisLabel("BACKWARD −30°")
            axisLabel("ROLL")
                .opacity(0.7)
        }
        .accessibilityLabel("Posture zones heat map")
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.ui(9, .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.textFaint)
    }

    private func grid(peak: Double) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<ZoneGrid.side, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<ZoneGrid.side, id: \.self) { col in
                        let index = row * ZoneGrid.side + col
                        let value = index < cells.count ? cells[index] / peak : 0
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color(row: row, value: value))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .overlay(crosshair)
    }

    /// The top rows are the slouch zone and glow amber to brown; everything
    /// around the centre glows mint.
    private func color(row: Int, value: Double) -> Color {
        guard value > 0.004 else { return Color.white.opacity(0.04) }
        let strength = 0.14 + 0.86 * pow(value, 0.55)
        switch row {
        case 0, 1: return Color(hex: 0xC97B3A).opacity(strength)
        case 2: return Theme.amber.opacity(strength)
        default: return Theme.mint.opacity(strength)
        }
    }

    private var crosshair: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.5)).frame(width: 14, height: 1)
            Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1, height: 14)
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1).frame(width: 22, height: 22)
        }
        .allowsHitTesting(false)
    }
}
