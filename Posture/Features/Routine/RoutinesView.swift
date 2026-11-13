import SwiftUI

/// The routines tab: what fits right now (or the check-in that is due), and
/// below it every routine to start by hand.
struct RoutinesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let done = app.store.resetsCount()
        TabScroll {
            ScreenHeader(eyebrow: "\(done) done today", title: "Routines")
            offerCard
            listCard
        }
    }

    // MARK: What fits now

    /// The check-in that is waiting, or else what fits the place and the
    /// hour. Nothing in the gym, and nothing in a lecture, where the
    /// check-in is only an announcement.
    @ViewBuilder
    private var offerCard: some View {
        let day = app.day
        if let due = day.due {
            offer(due.advice, label: "Check-in due", accent: Theme.amber)
        } else if let advice = day.suggestion, !advice.isAnnouncement {
            let relaxed = day.context.situation == .home && day.mode == .off
            offer(advice, label: relaxed ? "Whenever you like" : "Fits right now", accent: Theme.mint)
        }
    }

    private func offer(_ advice: Advice, label: String, accent: Color) -> some View {
        let hint = AdviceText.hint(advice, language: .en)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StatusDot(color: accent)
                    SectionLabel(label, color: accent)
                }
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
    }

    // MARK: All routines

    private var listCard: some View {
        let situation = app.day.context.situation
        let hasHome = app.settings.value.places.contains { $0.kind == .home }
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("All routines")
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
}
