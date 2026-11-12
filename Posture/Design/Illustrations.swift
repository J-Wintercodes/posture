import SwiftUI

// Vector stand-ins for the 3D renders of the reference design. They share
// the orb's material: dark graphite shapes with a mint light source.

/// AirPods for the "Ready when you are" card.
struct AirPodsGlyph: View {
    var connected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill((connected ? Theme.mint : Theme.amber).opacity(0.12))
                .frame(width: 92, height: 92)
                .blur(radius: 14)
            Image(systemName: "airpodspro")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(hex: 0x9AA3AE)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.6), radius: 8, y: 6)
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }
}

/// Side profile of head and neck with the vertical laser axis.
struct ProfileAxisIllustration: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let graphite = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(hex: 0x3A4048), Color(hex: 0x14171B)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: w, y: h)
            )
            // Neck and shoulders
            var torso = Path()
            torso.move(to: CGPoint(x: w * 0.40, y: h * 0.56))
            torso.addLine(to: CGPoint(x: w * 0.42, y: h * 0.74))
            torso.addQuadCurve(to: CGPoint(x: w * 0.16, y: h), control: CGPoint(x: w * 0.20, y: h * 0.80))
            torso.addLine(to: CGPoint(x: w * 0.86, y: h))
            torso.addQuadCurve(to: CGPoint(x: w * 0.60, y: h * 0.74), control: CGPoint(x: w * 0.82, y: h * 0.80))
            torso.addLine(to: CGPoint(x: w * 0.60, y: h * 0.56))
            torso.closeSubpath()
            context.fill(torso, with: graphite)
            // Head with a hint of a face pointing right
            let head = CGRect(x: w * 0.30, y: h * 0.14, width: w * 0.40, height: h * 0.46)
            context.fill(Path(ellipseIn: head), with: graphite)
            var nose = Path()
            nose.move(to: CGPoint(x: w * 0.69, y: h * 0.34))
            nose.addLine(to: CGPoint(x: w * 0.76, y: h * 0.41))
            nose.addLine(to: CGPoint(x: w * 0.69, y: h * 0.44))
            nose.closeSubpath()
            context.fill(nose, with: graphite)
            // Laser axis through ear and shoulder
            var axis = Path()
            axis.move(to: CGPoint(x: w * 0.50, y: h * 0.04))
            axis.addLine(to: CGPoint(x: w * 0.50, y: h * 0.98))
            var glow = context
            glow.addFilter(.blur(radius: 5))
            glow.stroke(axis, with: .color(Theme.mint.opacity(0.9)), lineWidth: 4)
            context.stroke(axis, with: .color(Theme.mint), lineWidth: 1.5)
            context.fill(
                Path(ellipseIn: CGRect(x: w * 0.50 - 3.5, y: h * 0.37 - 3.5, width: 7, height: 7)),
                with: .color(.white)
            )
        }
        .accessibilityHidden(true)
    }
}

/// A glowing S-curve of vertebrae for "Spine Story".
struct SpineIllustration: View {
    var body: some View {
        Canvas { context, size in
            let count = 11
            let w = Double(size.width)
            let h = Double(size.height)
            for i in 0..<count {
                let p = Double(i) / Double(count - 1)
                let x: Double = w * (0.5 + 0.13 * sin(p * 5.65 + 0.5))
                let y: Double = h * (0.07 + 0.86 * p)
                let width: Double = w * (0.20 + 0.12 * sin(p * Double.pi))
                let rect = CGRect(x: x - width / 2, y: y - 4, width: width, height: 8)
                var glow = context
                glow.addFilter(.blur(radius: 6))
                glow.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.mint.opacity(0.55 * (1 - p * 0.6))))
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 4),
                    with: .linearGradient(
                        Gradient(colors: [Color(hex: 0x8FE9DF), Theme.teal]),
                        startPoint: CGPoint(x: rect.minX, y: rect.minY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                    )
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// Walking figure with sensor waves at the head.
struct WalkingIllustration: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .trim(from: 0.60, to: 0.90)
                    .stroke(Theme.mint.opacity(0.7 - Double(ring) * 0.2), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 26 + CGFloat(ring) * 16, height: 26 + CGFloat(ring) * 16)
                    .offset(x: 4, y: -24)
            }
            Image(systemName: "figure.walk")
                .font(.system(size: 60, weight: .regular))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: 0x6B7480), Color(hex: 0x22262C)], startPoint: .top, endPoint: .bottom)
                )
        }
        .accessibilityHidden(true)
    }
}

/// Upright seated torso for the reset card.
struct UprightTorsoIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.mint.opacity(0.10))
                .blur(radius: 10)
            Capsule()
                .fill(Theme.mint)
                .frame(width: 2, height: 62)
                .shadow(color: Theme.mint, radius: 6)
                .offset(x: 16)
            Image(systemName: "figure.mind.and.body")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(hex: 0x7C8590)], startPoint: .top, endPoint: .bottom)
                )
        }
        .frame(width: 76, height: 76)
        .accessibilityHidden(true)
    }
}
