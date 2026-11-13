import SwiftUI

/// The central motif: a dark glossy sphere inside a glowing orbit ring, with
/// six vertebrae floating below it.
///
/// The ring is the head. Pitch opens or flattens it, roll tips it sideways,
/// and its colour follows the posture zone. The vertebrae bow forward as the
/// spine rounds. A level head draws a level ring and a straight stack.
struct SpineOrbView: View {
    var pitch: Double = 0
    var roll: Double = 0
    var zone: PostureZone = .aligned
    var score: Int?
    /// Shown in the sphere when there is no score, for example a dash.
    var placeholder: String?
    var diameter: CGFloat = 132
    var showsSpine = true
    var dimmed = false

    private var tint: Color { dimmed ? Theme.textFaint : Theme.zone(zone) }

    /// The sideways lean that is drawn. An AirPod never sits perfectly
    /// level in the ear, and the engine ignores the first degrees as well,
    /// so a small roll is drawn as none.
    static func visibleRoll(_ roll: Double) -> Double {
        let free = 3.0
        if roll > free { return roll - free }
        if roll < -free { return roll + free }
        return 0
    }

    var body: some View {
        VStack(spacing: diameter * 0.10) {
            // The satellite takes nine seconds per lap: 20 frames a second
            // look the same as 30 and keep the GPU idle more. In Low Power
            // Mode it stands still.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: ProcessInfo.processInfo.isLowPowerModeEnabled)) { timeline in
                orb(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: diameter * 1.56, height: diameter * 1.14)

            if showsSpine {
                SpineStack(pitch: pitch, roll: Self.visibleRoll(roll), tint: tint, unit: diameter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Posture score \($0)" } ?? "Posture orb")
    }

    private func orb(phase: Double) -> some View {
        let a = Double(diameter) * 0.74
        let squash = 0.24 + min(max(pitch, -20), 35) / 35 * 0.20
        let b = a * squash
        // No tilt of its own: the ring is only as crooked as the head is.
        let tilt = min(max(Self.visibleRoll(roll), -30), 30) * 0.9
        let theta = phase.truncatingRemainder(dividingBy: 9) / 9 * 2 * Double.pi
        let lx = a * cos(theta)
        let ly = b * sin(theta)
        let tr = tilt * Double.pi / 180
        let dx = lx * cos(tr) - ly * sin(tr)
        let dy = lx * sin(tr) + ly * cos(tr)
        let inFront = sin(theta) > 0

        return ZStack {
            ringHalf(a: a, b: b, tilt: tilt, back: true)
            satellite.offset(x: dx, y: dy).opacity(inFront ? 0 : 0.4)
            sphere
            ringHalf(a: a, b: b, tilt: tilt, back: false)
            satellite.offset(x: dx, y: dy).opacity(inFront ? 1 : 0)
            if let text = score.map({ "\($0)" }) ?? placeholder {
                Text(text)
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(score == nil ? 0.45 : 1))
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
        }
    }

    /// SwiftUI ellipses start at three o'clock and run clockwise on screen,
    /// so 0...0.5 is the lower half (in front of the sphere) and 0.5...1 the
    /// upper half (behind it).
    private func ringHalf(a: Double, b: Double, tilt: Double, back: Bool) -> some View {
        Ellipse()
            .trim(from: back ? 0.5 : 0, to: back ? 1 : 0.5)
            .stroke(tint.opacity(back ? 0.30 : 1), style: StrokeStyle(lineWidth: back ? 1.4 : 2.2, lineCap: .round))
            .frame(width: a * 2, height: b * 2)
            .rotationEffect(.degrees(tilt))
            .shadow(color: tint.opacity(back ? 0 : 0.85), radius: 7)
            .animation(.easeOut(duration: 0.25), value: tilt)
    }

    private var satellite: some View {
        Circle()
            .fill(Color.white)
            .frame(width: diameter * 0.06, height: diameter * 0.06)
            .shadow(color: tint, radius: 6)
            .shadow(color: tint.opacity(0.8), radius: 12)
    }

    private var sphere: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x4A515C), Color(hex: 0x1B1F25), Color(hex: 0x07080A)],
                        center: UnitPoint(x: 0.34, y: 0.26),
                        startRadius: 2,
                        endRadius: diameter * 0.78
                    )
                )
            // Soft specular highlight
            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: diameter * 0.34, height: diameter * 0.18)
                .blur(radius: diameter * 0.06)
                .offset(x: -diameter * 0.17, y: -diameter * 0.26)
            // Rim light picked up from the ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.55), tint.opacity(0.05), .clear],
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    ),
                    lineWidth: 1.5
                )
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: tint.opacity(0.22), radius: diameter * 0.22, y: diameter * 0.08)
    }
}

/// Six stylised vertebrae. `bend` rounds the stack forward, `lean` tips it.
private struct SpineStack: View {
    var pitch: Double
    var roll: Double
    var tint: Color
    var unit: CGFloat

    private let widths: [Double] = [0.20, 0.23, 0.26, 0.28, 0.27, 0.24]

    var body: some View {
        let bend = min(max(pitch / 26, -0.35), 1)
        let lean = min(max(roll / 30, -1), 1)
        VStack(spacing: unit * 0.032) {
            ForEach(0..<6, id: \.self) { index in
                let weight = pow(Double(5 - index) / 5, 1.5)
                vertebra(width: unit * widths[index], glow: weight)
                    .rotationEffect(.degrees((bend * 16 + lean * 7) * weight))
                    .offset(x: Double(unit) * (bend * 0.20 + lean * 0.09) * weight)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: bend)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: lean)
    }

    private func vertebra(width: CGFloat, glow: Double) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0x30353D), Color(hex: 0x15181C)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .frame(width: width, height: unit * 0.058)
            .shadow(color: tint.opacity(0.30 * glow), radius: 6, y: 1)
    }
}

#Preview("Spine orb") {
    HStack(spacing: 24) {
        SpineOrbView(score: 96)
        SpineOrbView(pitch: 19, roll: 6, zone: .slouching, score: 58)
    }
    .padding(40)
    .background(Theme.bg)
}
