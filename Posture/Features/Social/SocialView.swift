import SwiftUI

/// Social is a placeholder in this build: it shows what the tab is for and
/// lets the user share their own week, but there is no backend behind it.
struct SocialView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let week = app.store.lastDays(7)
        let scores = week.compactMap { $0.score }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
        TabScroll {
            ScreenHeader(eyebrow: "Better together", title: "Your circle")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        SectionLabel("Study circles")
                        SoonBadge()
                    }
                    Text("Sit tall with the people you study with.")
                        .font(.serif(24))
                        .foregroundStyle(Theme.text)
                    Text("Shared streaks for your library group and a quiet weekly ranking. No feeds, no likes.")
                        .font(.ui(14))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Your week to share")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(average.map { "\($0)" } ?? "—")
                            .font(.ui(46, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                        Text("avg · \(app.store.streak)d streak")
                            .font(.ui(13, .medium))
                            .foregroundStyle(Theme.textDim)
                    }
                    WeekDots(days: week, height: 48)
                    ShareLink(item: shareText(average: average)) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .bold))
                            Text("Share my week").font(.ui(16, .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.cardRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    .disabled(average == nil)
                    .opacity(average == nil ? 0.5 : 1)
                }
            }
        }
    }

    private func shareText(average: Int?) -> String {
        guard let average else { return "I'm working on my posture." }
        return "My posture week: average \(average)/100, \(app.store.streak) day streak."
    }
}
