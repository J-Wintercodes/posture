import SwiftUI

/// How the tracked time spreads over one angle (forward lean, or lean to
/// the side), in the bins of `ZoneGrid`.
struct AngleSpread: Equatable {
    /// Seconds per bin, from the most negative angle to the most positive.
    var bins: [Double]

    var total: Double { bins.reduce(0, +) }

    /// Width of one bin in degrees.
    var step: Double { bins.isEmpty ? 0 : ZoneGrid.span * 2 / Double(bins.count) }

    /// Too little tracked to say anything.
    var isEmpty: Bool { total < 60 }

    /// Forward lean: rows of the grid. Row 0 is the most forward one, so
    /// the rows are turned around to run from leaning back to leaning
    /// forward.
    static func pitch(_ cells: [Double]) -> AngleSpread {
        let side = ZoneGrid.side
        var bins = [Double](repeating: 0, count: side)
        guard cells.count == side * side else { return AngleSpread(bins: bins) }
        for row in 0..<side {
            var sum = 0.0
            for col in 0..<side { sum += cells[row * side + col] }
            bins[side - 1 - row] = sum
        }
        return AngleSpread(bins: bins)
    }

    /// Lean to the side: columns of the grid, left to right.
    static func roll(_ cells: [Double]) -> AngleSpread {
        let side = ZoneGrid.side
        var bins = [Double](repeating: 0, count: side)
        guard cells.count == side * side else { return AngleSpread(bins: bins) }
        for row in 0..<side {
            for col in 0..<side { bins[col] += cells[row * side + col] }
        }
        return AngleSpread(bins: bins)
    }

    /// Middle angle of a bin.
    func center(of index: Int) -> Double {
        -ZoneGrid.span + (Double(index) + 0.5) * step
    }

    /// The angle below which the share `u` (0...1) of the time lies. Inside
    /// a bin the time is taken as spread evenly.
    func angle(at u: Double) -> Double {
        let all = total
        guard all > 0 else { return 0 }
        let target = min(max(u, 0), 1) * all
        var passed = 0.0
        for (index, seconds) in bins.enumerated() where seconds > 0 {
            if passed + seconds >= target {
                let inside = (target - passed) / seconds
                return -ZoneGrid.span + (Double(index) + inside) * step
            }
            passed += seconds
        }
        return ZoneGrid.span
    }
}

/// A seated figure whose spine bends by an angle, drawn on a grid of
/// 82 x 100 units and scaled to the canvas. Pure geometry plus the drawing.
enum PostureFigure {
    enum Viewpoint {
        /// From the side, facing right: the angle is the forward lean.
        case side
        /// From behind: the angle is the lean to the left or right.
        case behind
    }

    struct Pose {
        /// From the hips up to the base of the neck, nine points.
        var spine: [CGPoint]
        var head: CGPoint
        /// How far the head is tipped, in radians.
        var tilt: Double
    }

    static let gridWidth = 82.0
    static let gridHeight = 100.0
    static let headRadius = 6.5
    /// The drawing bends more than the head really does, so that a few
    /// degrees can be seen at this size.
    static let gain = 1.5

    private static let segments = 8
    private static let segmentLength = 5.3
    private static let neckLength = 9.5

    static func hip(_ view: Viewpoint) -> CGPoint {
        switch view {
        case .side: return CGPoint(x: 32, y: 76)
        case .behind: return CGPoint(x: 41, y: 76)
        }
    }

    /// The figure at `angle` degrees, in grid units. The lower back hardly
    /// moves, the upper back and the neck carry most of the bend.
    static func pose(angle: Double, view: Viewpoint) -> Pose {
        let bend = min(max(angle, -ZoneGrid.span), ZoneGrid.span) * gain * Double.pi / 180
        var point = hip(view)
        var spine: [CGPoint] = [point]
        for index in 0..<segments {
            let weight = pow(Double(index + 1) / Double(segments), 1.6) * 0.9
            let lean = bend * weight
            point = CGPoint(
                x: Double(point.x) + sin(lean) * segmentLength,
                y: Double(point.y) - cos(lean) * segmentLength
            )
            spine.append(point)
        }
        let head = CGPoint(
            x: Double(point.x) + sin(bend) * neckLength,
            y: Double(point.y) - cos(bend) * neckLength
        )
        return Pose(spine: spine, head: head, tilt: bend)
    }

    /// Mint inside the good band, amber when drifting, ember beyond. The
    /// same bands the engine scores with.
    static func tint(_ view: Viewpoint, angle: Double) -> Color {
        let tuning = PostureTuning()
        let off: Double
        switch view {
        case .side: off = max(angle - tuning.screenLean, 0)
        case .behind: off = max(abs(angle) - 2, 0) * 0.8
        }
        if off <= tuning.goodBand { return Theme.mint }
        if off <= tuning.slouchBand { return Theme.amber }
        return Theme.ember
    }

    /// The angle the moving figure shows at `time`. It swings from one end
    /// of the spread to the other and back, and because it follows the
    /// share of time, it lingers where the user sat longest.
    static func liveAngle(_ spread: AngleSpread, time: Double) -> Double {
        if spread.isEmpty {
            // Nothing tracked yet: a quiet sway around upright.
            let phase = time.truncatingRemainder(dividingBy: 6) / 6
            return sin(phase * 2 * Double.pi) * 2
        }
        let phase = time.truncatingRemainder(dividingBy: 8) / 8
        let wave = 0.5 - 0.5 * cos(phase * 2 * Double.pi)
        // The outermost few percent are stray moments, not posture.
        return spread.angle(at: 0.04 + 0.92 * wave)
    }

    // MARK: Drawing

    static func draw(in context: GraphicsContext, size: CGSize, view: Viewpoint, spread: AngleSpread, time: Double) {
        let unit = min(Double(size.width) / gridWidth, Double(size.height) / gridHeight)
        let left = (Double(size.width) - gridWidth * unit) / 2
        let top = (Double(size.height) - gridHeight * unit) / 2
        let place: (CGPoint) -> CGPoint = { point in
            CGPoint(x: left + Double(point.x) * unit, y: top + Double(point.y) * unit)
        }

        drawSeat(in: context, view: view, unit: unit, place: place)

        // The positions that were held: one faint outline per bin, the more
        // time in it the clearer.
        if !spread.isEmpty {
            let peak = max(spread.bins.max() ?? 0, 0.001)
            for (index, seconds) in spread.bins.enumerated() {
                let share = seconds / spread.total
                guard share > 0.02 else { continue }
                let angle = spread.center(of: index)
                let color = tint(view, angle: angle).opacity(0.07 + 0.30 * seconds / peak)
                let ghost = pose(angle: angle, view: view)
                drawBody(in: context, pose: ghost, view: view, color: color, unit: unit, place: place, solid: false)
            }
        }

        // The moving figure.
        let angle = liveAngle(spread, time: time)
        let color = spread.isEmpty ? Theme.textFaint : tint(view, angle: angle)
        let live = pose(angle: angle, view: view)
        drawBody(in: context, pose: live, view: view, color: color, unit: unit, place: place, solid: true)
    }

    /// Stool and legs. They never move.
    private static func drawSeat(in context: GraphicsContext, view: Viewpoint, unit: Double, place: (CGPoint) -> CGPoint) {
        let faint = Color.white.opacity(0.16)
        let limb = Color.white.opacity(0.26)
        let thin = StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round, lineJoin: .round)
        let thick = StrokeStyle(lineWidth: 3.0 * unit, lineCap: .round, lineJoin: .round)
        let center = Double(hip(view).x)

        var stool = Path()
        switch view {
        case .side:
            stool.move(to: place(CGPoint(x: center - 16, y: 82)))
            stool.addLine(to: place(CGPoint(x: center + 20, y: 82)))
        case .behind:
            stool.move(to: place(CGPoint(x: center - 18, y: 82)))
            stool.addLine(to: place(CGPoint(x: center + 18, y: 82)))
        }
        stool.move(to: place(CGPoint(x: center, y: 82)))
        stool.addLine(to: place(CGPoint(x: center, y: 97)))
        stool.move(to: place(CGPoint(x: center - 9, y: 97)))
        stool.addLine(to: place(CGPoint(x: center + 9, y: 97)))
        context.stroke(stool, with: .color(faint), style: thin)

        var legs = Path()
        switch view {
        case .side:
            // Thigh, shin and foot, facing right.
            legs.move(to: place(CGPoint(x: center, y: 76)))
            legs.addLine(to: place(CGPoint(x: center + 24, y: 77)))
            legs.addLine(to: place(CGPoint(x: center + 26, y: 97)))
            legs.addLine(to: place(CGPoint(x: center + 33, y: 97)))
        case .behind:
            // The hips, seen from the back.
            legs.move(to: place(CGPoint(x: center - 10, y: 76)))
            legs.addLine(to: place(CGPoint(x: center + 10, y: 76)))
        }
        context.stroke(legs, with: .color(limb), style: thick)
    }

    /// Spine, shoulders or arm, and the head. `solid` is the moving figure,
    /// otherwise a faint outline.
    private static func drawBody(in context: GraphicsContext, pose: Pose, view: Viewpoint, color: Color,
                                 unit: Double, place: (CGPoint) -> CGPoint, solid: Bool) {
        guard pose.spine.count > 2 else { return }
        let width = (solid ? 3.2 : 2.2) * unit
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)

        var line = Path()
        line.move(to: place(pose.spine[0]))
        for point in pose.spine.dropFirst() {
            line.addLine(to: place(point))
        }
        // The neck, up to the edge of the head.
        let top = pose.spine[pose.spine.count - 1]
        let neckEnd = CGPoint(
            x: Double(pose.head.x) - sin(pose.tilt) * headRadius,
            y: Double(pose.head.y) + cos(pose.tilt) * headRadius
        )
        line.move(to: place(top))
        line.addLine(to: place(neckEnd))
        context.stroke(line, with: .color(color), style: style)

        // Shoulders and arms hang from the second point from the top.
        let shoulder = pose.spine[pose.spine.count - 2]
        var arms = Path()
        switch view {
        case .side:
            let elbow = CGPoint(x: Double(shoulder.x) + 3, y: Double(shoulder.y) + 15)
            let hand = CGPoint(x: Double(elbow.x) + 14, y: Double(elbow.y) - 2)
            arms.move(to: place(shoulder))
            arms.addLine(to: place(elbow))
            arms.addLine(to: place(hand))
        case .behind:
            // The shoulder line tips with the upper back.
            let lean = pose.tilt * 0.75
            let dx = cos(lean) * 12
            let dy = sin(lean) * 12
            let leftShoulder = CGPoint(x: Double(shoulder.x) - dx, y: Double(shoulder.y) - dy)
            let rightShoulder = CGPoint(x: Double(shoulder.x) + dx, y: Double(shoulder.y) + dy)
            arms.move(to: place(CGPoint(x: Double(leftShoulder.x) - 1, y: Double(leftShoulder.y) + 17)))
            arms.addLine(to: place(leftShoulder))
            arms.addLine(to: place(rightShoulder))
            arms.addLine(to: place(CGPoint(x: Double(rightShoulder.x) + 1, y: Double(rightShoulder.y) + 17)))
        }
        let armColor = solid ? Color.white.opacity(0.34) : color.opacity(0.6)
        let armStyle = StrokeStyle(lineWidth: (solid ? 2.6 : 1.8) * unit, lineCap: .round, lineJoin: .round)
        context.stroke(arms, with: .color(armColor), style: armStyle)

        // Head
        let radius = headRadius * unit
        let headCenter = place(pose.head)
        let headRect = CGRect(
            x: Double(headCenter.x) - radius,
            y: Double(headCenter.y) - radius,
            width: radius * 2,
            height: radius * 2
        )
        let headPath = Path(ellipseIn: headRect)
        if solid {
            context.fill(headPath, with: .color(Color(hex: 0x1B1F25)))
        }
        context.stroke(headPath, with: .color(color), style: StrokeStyle(lineWidth: (solid ? 2.4 : 1.6) * unit))

        if solid {
            // The vertebrae, as small dots along the spine.
            for point in pose.spine.dropFirst().dropLast() {
                let dot = place(point)
                let r = 1.5 * unit
                let rect = CGRect(x: Double(dot.x) - r, y: Double(dot.y) - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.85)))
            }
            if view == .side {
                // A short line for the nose: which way the figure looks.
                let from = CGPoint(
                    x: Double(pose.head.x) + cos(pose.tilt) * headRadius,
                    y: Double(pose.head.y) + sin(pose.tilt) * headRadius
                )
                let to = CGPoint(
                    x: Double(pose.head.x) + cos(pose.tilt) * (headRadius + 3),
                    y: Double(pose.head.y) + sin(pose.tilt) * (headRadius + 3)
                )
                var nose = Path()
                nose.move(to: place(from))
                nose.addLine(to: place(to))
                context.stroke(nose, with: .color(color), style: StrokeStyle(lineWidth: 2.0 * unit, lineCap: .round))
            }
        }
    }
}

/// Posture zones as a body instead of a grid: one seated figure seen from
/// the side (forward and back) and one from behind (left and right).
///
/// The faint outlines are the positions that were held, the clearer the
/// longer. The bright figure moves through them and lingers where the user
/// sat longest.
struct PostureZonesFigure: View {
    var cells: [Double]

    var body: some View {
        let pitch = AngleSpread.pitch(cells)
        let roll = AngleSpread.roll(cells)
        HStack(alignment: .top, spacing: 12) {
            panel(.side, spread: pitch, caption: "From the side")
            panel(.behind, spread: roll, caption: "From behind")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Posture zones. \(summary(.side, spread: pitch)), \(summary(.behind, spread: roll)).")
    }

    private func panel(_ view: PostureFigure.Viewpoint, spread: AngleSpread, caption: String) -> some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    PostureFigure.draw(in: context, size: size, view: view, spread: spread, time: time)
                }
            }
            .aspectRatio(0.82, contentMode: .fit)
            Text(caption.uppercased())
                .font(.ui(9, .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textFaint)
            Text(summary(view, spread: spread))
                .font(.ui(13, .semibold))
                .foregroundStyle(spread.isEmpty ? Theme.textFaint : Theme.text)
        }
        .frame(maxWidth: .infinity)
    }

    /// "mostly 9° forward": the angle half of the time lies below.
    private func summary(_ view: PostureFigure.Viewpoint, spread: AngleSpread) -> String {
        guard !spread.isEmpty else { return "no data yet" }
        let middle = spread.angle(at: 0.5)
        let degrees = Int(abs(middle).rounded())
        switch view {
        case .side:
            if middle >= 2 { return "mostly \(degrees)° forward" }
            if middle <= -2 { return "mostly \(degrees)° back" }
            return "mostly upright"
        case .behind:
            if middle >= 2 { return "mostly \(degrees)° right" }
            if middle <= -2 { return "mostly \(degrees)° left" }
            return "mostly level"
        }
    }
}
