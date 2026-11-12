import Foundation

/// Every threshold of the heuristic in one place. The defaults are reasoned
/// from biomechanics and need a pass with real AirPods recordings.
struct PostureTuning: Sendable {
    // MARK: Axis convention
    // CoreMotion reports the headphone frame as x = right, y = forward,
    // z = up. If a device ever reports "looking down" as negative, flip here.
    var forwardSign = 1.0
    var lateralSign = 1.0

    // MARK: Bands (degrees from baseline)
    /// Forward lean that is simply how people sit at a screen. The baseline
    /// is "tall, eyes straight ahead"; working at a monitor or laptop tips
    /// the head a few degrees towards it. This much forward pitch is free,
    /// the bands below start counting after it.
    var screenLean = 6.0
    var goodBand = 8.0
    var slouchBand = 16.0
    var severeDeviation = 26.0
    var hysteresis = 1.5

    // MARK: Transition kinematics (degrees per second, metres)
    /// A nod faster than this is a deliberate look-down.
    var glanceRate = 25.0
    /// A drift slower than this is postural creep.
    var creepRate = 8.0
    /// Head drop during a fast forward pitch that marks a slump.
    var slumpSink = 0.015
    /// A fast nod only counts as looking down at something (notes, a book)
    /// when the head ends up at least this far forward of the baseline.
    /// A quick move into a shallower angle that then stays there is someone
    /// dropping into a slouch, and counts as one.
    var lookDownPitch = 26.0
    /// Hysteresis below `lookDownPitch`, so a head that moves while reading
    /// does not flip between the two.
    var lookDownRelease = 3.0

    // MARK: Grace
    /// Seconds a full-severity slouch may last before the first nudge.
    var graceSeconds = 18.0
    /// Seconds of good posture that empty the slouch load again.
    var recoverSeconds = 10.0
    /// How long a deliberate look-down is left alone before it slowly
    /// starts to count (long neck flexion is its own problem).
    var lookDownBudget = 120.0
    var lookDownRamp = 60.0
    /// Leaning back is free for this long (drinking, stretching, thinking).
    var reclineGrace = 45.0

    // MARK: Suppression
    var movingAcceleration = 0.06
    var movingConfirm = 2.5
    var awayAfter = 20.0
    var settleSeconds = 6.0
    var phoneHoldOff = 6.0

    // MARK: Auto-zero
    var autoZeroBand = 5.0
    /// Following a more upright pose is quick, following a forward pose is
    /// very slow and capped, so the baseline can never "learn" a slouch.
    var uprightTau = 40.0
    var forwardTau = 300.0
    var maxForwardOffset = 4.0
    var maxBackOffset = 8.0
    var maxLateralOffset = 5.0

    // MARK: Nudges
    /// Seconds back in the good band before a bad spell counts as over and
    /// the positive sound plays.
    var recoveryConfirm = 2.0
    /// Wait before the first reminder while a bad spell lasts. Doubles with
    /// every further reminder.
    var nudgeCooldown = 40.0
    var neckCooldown = 300.0
}

enum PostureScore {
    /// Maps an effective deviation in degrees to 0...100.
    static func value(forDeviation d: Double) -> Double {
        let stops: [(Double, Double)] = [(0, 100), (3, 100), (8, 88), (16, 62), (26, 35), (45, 10)]
        guard d > 0 else { return 100 }
        for i in 1..<stops.count where d <= stops[i].0 {
            let (x0, y0) = stops[i - 1]
            let (x1, y1) = stops[i]
            return y0 + (y1 - y0) * (d - x0) / (x1 - x0)
        }
        return 10
    }
}
