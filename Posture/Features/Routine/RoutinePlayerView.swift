import SwiftUI
import UIKit

/// Plays a routine: one step after the other with a countdown ring. In voice
/// mode Theo reads each step, so the floor exercises work without looking at
/// the phone. Finishing counts as a reset and restarts the check-in timer.
struct RoutinePlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let routine: Routine

    @State private var elapsed = 0
    @State private var started = false
    @State private var finished = false

    private var total: Int { max(routine.seconds, 1) }
    private var remaining: Int { max(0, total - elapsed) }

    /// Index of the step that `elapsed` falls into.
    private var stepIndex: Int {
        var end = 0
        for (index, step) in routine.steps.enumerated() {
            end += step.seconds
            if elapsed < end { return index }
        }
        return max(0, routine.steps.count - 1)
    }

    /// Seconds left in the current step.
    private var stepRemaining: Int {
        var end = 0
        for step in routine.steps {
            end += step.seconds
            if elapsed < end { return end - elapsed }
        }
        return 0
    }

    var body: some View {
        let index = stepIndex
        let step = routine.steps[index]
        VStack(spacing: 0) {
            HStack {
                SectionLabel(routine.name.en)
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
                    .trim(from: 0, to: Double(elapsed) / Double(total))
                    .stroke(Theme.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.mint.opacity(0.8), radius: 8)
                    .animation(.linear(duration: 1), value: elapsed)
                VStack(spacing: 6) {
                    Image(systemName: finished ? "checkmark" : step.icon)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.mint)
                    Text(finished ? "Done" : "\(started ? stepRemaining : total)")
                        .font(.ui(54, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    if started, !finished, routine.steps.count > 1 {
                        Text("Step \(index + 1) of \(routine.steps.count) · \(Fmt.clock(Double(remaining))) left")
                            .font(.ui(12, .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
            .frame(width: 230, height: 230)
            Spacer()

            VStack(spacing: 10) {
                Text(headline(step))
                    .font(.serif(28))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text(detail(step))
                    .font(.ui(15))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 130, alignment: .top)
            .animation(.easeInOut(duration: 0.3), value: index)

            if finished {
                PillButton(title: "Done", icon: "checkmark") { dismiss() }
            } else if !started {
                PillButton(title: "Start", icon: "play.fill") { started = true }
            } else {
                PillButton(title: "Stop", kind: .dark) { dismiss() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(Theme.bg.ignoresSafeArea())
        .sensoryFeedback(.impact, trigger: index)
        .task(id: started) {
            guard started else { return }
            await run()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            app.coach.stopSpeaking()
        }
    }

    private func headline(_ step: RoutineStep) -> String {
        if finished { return "Routine complete" }
        return started ? step.title.en : routine.name.en
    }

    private func detail(_ step: RoutineStep) -> String {
        if finished {
            let count = app.store.resetsCount()
            return "That's \(count) \(count == 1 ? "reset" : "resets") today. The check-in timer starts over."
        }
        if started { return step.cue.en }
        let steps = routine.steps.count
        var line = "\(routine.focus). \(steps) \(steps == 1 ? "step" : "steps"), \(routine.durationLabel)."
        if routine.homeOnly { line += " You need a bit of floor." }
        if app.settings.value.feedback == .voice { line += " Theo reads each step to you." }
        return line
    }

    @MainActor
    private func run() async {
        // A routine can take a few minutes; the screen must not lock under it.
        UIApplication.shared.isIdleTimerDisabled = true
        app.syncCoach()
        app.session.holdForExercise(seconds: Double(total) + 6)
        let language = app.settings.value.coachLanguage
        var announced = -1
        while elapsed < total {
            let index = stepIndex
            if index != announced {
                announced = index
                let step = routine.steps[index]
                app.coach.speak("\(step.title.text(language)). \(step.cue.text(language))")
            }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            elapsed += 1
        }
        app.finished(routine)
        finished = true
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
