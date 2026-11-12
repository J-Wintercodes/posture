import SwiftUI

/// The 30 second "Eye + Posture Reset": three ten-second movements with a
/// countdown ring. Counts towards the five resets of the day.
struct ResetExerciseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private struct Stage {
        let title: String
        let cue: String
        let icon: String
    }

    private let stages = [
        Stage(title: "Look far away", cue: "Find the most distant point you can see and rest your eyes on it.", icon: "eye"),
        Stage(title: "Chin tuck", cue: "Slide your head straight back, as if making a double chin. Hold, release, repeat.", icon: "arrow.left.and.right"),
        Stage(title: "Open the chest", cue: "Roll your shoulders back and down, squeeze the shoulder blades together.", icon: "figure.mind.and.body")
    ]

    private let total = 30
    @State private var remaining = 30
    @State private var started = false
    @State private var finished = false

    var body: some View {
        let stage = stages[min((total - remaining) / 10, stages.count - 1)]
        VStack(spacing: 0) {
            HStack {
                SectionLabel("Eye + Posture Reset")
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 36, height: 36)
                        .background(Theme.card, in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.top, 20)

            Spacer()
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: Double(total - remaining) / Double(total))
                    .stroke(Theme.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.mint.opacity(0.8), radius: 8)
                    .animation(.linear(duration: 1), value: remaining)
                VStack(spacing: 6) {
                    Image(systemName: finished ? "checkmark" : stage.icon)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.mint)
                    Text(finished ? "Done" : "\(remaining)")
                        .font(.ui(54, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 230, height: 230)
            Spacer()

            VStack(spacing: 10) {
                Text(finished ? "Reset complete" : (started ? stage.title : "Thirty seconds for neck and upper back"))
                    .font(.serif(28))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text(finished
                     ? "That's \(app.store.resetsCount()) of 5 today."
                     : (started ? stage.cue : "Three small movements, ten seconds each. No need to stand up."))
                    .font(.ui(15))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 110, alignment: .top)
            .animation(.easeInOut(duration: 0.3), value: stage.title)

            if finished {
                PillButton(title: "Back to work", icon: "checkmark") { dismiss() }
            } else if !started {
                PillButton(title: "Start", icon: "play.fill") { started = true }
            } else {
                PillButton(title: "Stop", kind: .dark) { dismiss() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(Theme.bg.ignoresSafeArea())
        .task(id: started) {
            guard started else { return }
            app.session.holdForExercise(seconds: Double(total) + 6)
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
            }
            app.store.addReset()
            finished = true
        }
    }
}
