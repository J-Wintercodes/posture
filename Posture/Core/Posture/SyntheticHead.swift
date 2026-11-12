import Foundation

/// Generates plausible AirPods frames from a described head pose. Used by the
/// unit tests and by the Simulator, where no headphone motion exists.
struct SyntheticHead {
    var sampleRate = 25.0
    /// How the bud happens to sit in the ear. The engine must not care.
    var restForward = 11.0
    var restLateral = -2.5

    private(set) var time: TimeInterval = 0
    private var lastForward: Double?
    private var lastLateral: Double?
    private var state: UInt64 = 0x9E37_79B9_7F4A_7C15

    mutating func next(forward: Double, lateral: Double = 0, lively: Bool = false, walking: Bool = false) -> HeadSample {
        let dt = 1 / sampleRate
        var f = forward + noise() * 0.05
        var l = lateral + noise() * 0.05
        if lively {
            f += 1.4 * sin(2 * .pi * 0.7 * time)
            l += 0.8 * sin(2 * .pi * 0.45 * time)
        }
        if walking {
            f += 2.5 * sin(2 * .pi * 1.9 * time)
            l += 2.0 * sin(2 * .pi * 0.95 * time)
        }
        let fr = (restForward + f) * .pi / 180
        let lr = (restLateral + l) * .pi / 180
        let gravity = Vec3(x: tan(lr), y: tan(fr), z: -1).normalized

        let df = lastForward.map { (f - $0) / dt } ?? 0
        let dl = lastLateral.map { (l - $0) / dt } ?? 0
        lastForward = f
        lastLateral = l
        let rotation = Vec3(x: -df * .pi / 180, y: dl * .pi / 180, z: noise() * 0.01)

        var acceleration = Vec3(x: noise() * 0.004, y: noise() * 0.004, z: noise() * 0.004)
        if walking {
            acceleration.z += 0.22 * sin(2 * .pi * 1.9 * time)
            acceleration.x += 0.08 * sin(2 * .pi * 0.95 * time)
        }

        let sample = HeadSample(t: time, gravity: gravity, rotationRate: rotation, userAcceleration: acceleration)
        time += dt
        return sample
    }

    private mutating func noise() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 20_001) / 10_000 - 1
    }
}

/// A looping desk scene for the Simulator: upright, a look at the notes,
/// upright again, then a slow slouch and a recovery.
enum DemoScenario {
    struct Pose {
        var forward: Double
        var lateral: Double
        var lively: Bool
    }

    static let period = 150.0

    static func pose(at time: Double) -> Pose {
        let t = time.truncatingRemainder(dividingBy: period)
        switch t {
        case ..<25:
            return Pose(forward: 0, lateral: 0, lively: false)
        case ..<25.6:
            return Pose(forward: 28 * ease((t - 25) / 0.6), lateral: 0, lively: false)
        case ..<40:
            return Pose(forward: 28, lateral: 0, lively: true)
        case ..<40.6:
            return Pose(forward: 28 * (1 - ease((t - 40) / 0.6)), lateral: 0, lively: false)
        case ..<60:
            return Pose(forward: 0, lateral: 0, lively: false)
        case ..<90:
            return Pose(forward: 23 * (t - 60) / 30, lateral: 3 * (t - 60) / 30, lively: false)
        case ..<118:
            return Pose(forward: 23, lateral: 3, lively: false)
        case ..<120:
            return Pose(forward: 23 * (1 - ease((t - 118) / 2)), lateral: 3 * (1 - ease((t - 118) / 2)), lively: false)
        default:
            return Pose(forward: 0, lateral: 0, lively: false)
        }
    }

    private static func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
