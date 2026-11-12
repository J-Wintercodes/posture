import SwiftUI

/// Five seconds of "sit tall, look straight ahead" that become the zero
/// reference. Used as the last onboarding step and from Home > Calibration.
struct CalibrationView: View {
    @Environment(AppModel.self) private var app
    var embedded = false
    var onDone: () -> Void

    enum Phase: Equatable {
        case idle, running, success, unstable, noSignal
    }

    @State private var phase: Phase = .idle
    @State private var progress = 0.0
    @State private var runner: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(embedded ? "Step 5 of 5" : "Calibration", color: Theme.mint)
                Text(headline)
                    .font(.serif(34))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.ui(15))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 30)

            Spacer(minLength: 16)
            dial
            Spacer(minLength: 16)

            VStack(spacing: 12) {
                switch phase {
                case .idle:
                    PillButton(title: "I'm sitting tall — start", icon: "scope") { run() }
                case .running:
                    Text("Hold still…")
                        .font(.serif(20, italic: true))
                        .foregroundStyle(Theme.textDim)
                        .padding(.vertical, 14)
                case .success:
                    PillButton(title: embedded ? "Finish setup" : "Done", icon: "checkmark") { onDone() }
                case .unstable, .noSignal:
                    PillButton(title: "Try again", icon: "arrow.clockwise") { run() }
                }
                if phase != .running, phase != .success {
                    Button(embedded ? "Skip for now" : "Cancel") { onDone() }
                        .font(.ui(14, .medium))
                        .foregroundStyle(Theme.textDim)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(Theme.bg.ignoresSafeArea())
        .onDisappear { runner?.cancel() }
    }

    private var headline: String {
        switch phase {
        case .idle: return "Sit tall and look straight ahead"
        case .running: return "Measuring your upright"
        case .success: return "That's your zero"
        case .unstable: return "That moved a little too much"
        case .noSignal: return "No motion from your AirPods"
        }
    }

    private var detail: String {
        switch phase {
        case .idle:
            return "Feet on the floor, shoulders loose, eyes on the horizon. Put your AirPods in. The next five seconds become the reference everything is measured against."
        case .running:
            return "Breathe normally and keep your eyes on one point."
        case .success:
            return "From now on the coach measures against this position. You can reset it any time with \"Upright set\" during a session."
        case .unstable:
            return "Pick a point in front of you, hold your head still for five seconds and try again."
        case .noSignal:
            return "Check that AirPods Pro, AirPods 3 or newer, or AirPods Max are connected and in your ears, and that Motion & Fitness is allowed. If you skip, the first seconds of your first session are used instead."
        }
    }

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 3)
            Circle()
                .trim(from: 0, to: phase == .success ? 1 : progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.8), radius: 8)
                .animation(.linear(duration: 0.1), value: progress)
            ProfileAxisIllustration()
                .frame(width: 150, height: 170)
            if phase == .running {
                Text("\(max(1, Int((5 * (1 - progress)).rounded(.up))))")
                    .font(.ui(18, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .offset(y: 108)
            }
        }
        .frame(width: 250, height: 250)
    }

    private var ringColor: Color {
        switch phase {
        case .unstable, .noSignal: return Theme.amber
        default: return Theme.mint
        }
    }

    private func run() {
        runner?.cancel()
        phase = .running
        progress = 0
        runner = Task {
            var calibrator = Calibrator()
            app.headphones.acquire()
            defer { app.headphones.release() }

            // Give the stream a moment to come up before the take begins.
            try? await Task.sleep(for: .milliseconds(600))
            let steps = 50
            for step in 0..<steps {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                if let sample = app.headphones.latest { calibrator.add(sample) }
                progress = Double(step + 1) / Double(steps)
            }
            switch calibrator.finish() {
            case .ok(let baseline):
                app.settings.update { $0.baseline = baseline }
                phase = .success
            case .unstable:
                phase = .unstable
            case .noData:
                phase = .noSignal
            }
        }
    }
}
