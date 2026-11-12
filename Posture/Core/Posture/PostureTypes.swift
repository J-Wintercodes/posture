import Foundation

// Pure value types shared by the posture engine, the services and the UI.
// Nothing in Core/Posture imports CoreMotion or SwiftUI, so the whole
// heuristic can be unit-tested with synthetic signals.

struct Vec3: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vec3(x: 0, y: 0, z: 0)

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    var normalized: Vec3 {
        let l = length
        return l > 1e-9 ? Vec3(x: x / l, y: y / l, z: z / l) : self
    }

    func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
}

/// One AirPods motion frame, already stripped of CoreMotion types.
struct HeadSample: Sendable {
    /// Sensor timestamp in seconds (monotonic).
    var t: TimeInterval
    /// Gravity in the headphone frame, in g. Upright is roughly (0, 0, -1).
    var gravity: Vec3
    /// Gyro rate in rad/s.
    var rotationRate: Vec3
    /// Acceleration without gravity, in g.
    var userAcceleration: Vec3
}

/// What the iPhone itself is doing. Feeds phone-usage suppression.
struct PhoneContext: Equatable, Sendable {
    var isUnlocked = false
    var isAppActive = false
    var isHandheld = false

    var isInUse: Bool { isUnlocked || isAppActive || isHandheld }
}

/// The calibrated "upright" reference: where gravity sits in the headphone
/// frame when the user sits tall and looks straight ahead.
struct Baseline: Codable, Equatable, Sendable {
    var forward: Double
    var lateral: Double
    var capturedAt: Date
    var isProvisional: Bool
}

enum PostureZone: String, Codable, Sendable {
    case aligned, drifting, slouching
}

enum PostureContext: String, Codable, Sendable {
    /// Seated and working. Fully scored.
    case focused
    /// Deliberate look-down (notes, book, tablet). Scored with a long leash.
    case lookingDown
    /// The iPhone is unlocked or in the hand. Not scored, coach is quiet.
    case phone
    /// Short hold-off after phone use or after sitting back down.
    case settling
    /// Body is moving (standing up, stretching).
    case moving
    /// Walked away from the desk.
    case away
}

/// How the head left the good band. This is the main discriminator between
/// "I looked at my notes" and "I am sinking into the chair".
enum EntryKind: String, Sendable {
    case none
    /// Slow drift, a few degrees per second or less: postural creep.
    case creep
    /// Neither clearly slow nor clearly fast.
    case ambiguous
    /// Fast, deliberate nod with the head staying at the same height.
    case glance
    /// Fast forward pitch together with the head dropping: flopping down.
    case slump
}

enum NudgeKind: String, Sendable {
    case slouch, neck, tilt, recline
}

enum BreakReason: String, Sendable {
    case fatigueTrend, repeatedSlouch, longSit
}

enum PostureEvent: Equatable, Sendable {
    /// Level 0: posture has just turned bad. Level 1 and up: reminders while
    /// it stays bad.
    case nudge(NudgeKind, level: Int)
    /// Posture is good again. Always follows a level 0 nudge.
    case recovered
    case away
    case returned
    case rebaselined
}

struct PostureReading: Sendable {
    var t: TimeInterval
    var dt: TimeInterval
    /// Forward deviation from the baseline in degrees. Positive = chin down.
    var pitch: Double
    /// Lateral deviation in degrees. Positive = right ear towards shoulder.
    var roll: Double
    /// 0...100, smoothed.
    var score: Double
    var zone: PostureZone
    var context: PostureContext
    var entry: EntryKind
    /// Slouch pressure, 0...1. A nudge fires when it fills up.
    var load: Double
    /// False while the reading must not count for or against the user.
    var isScored: Bool
    var events: [PostureEvent]

    var isGood: Bool { isScored && score >= 80 }
}

/// 8 x 8 map of where the head spends its time. Row 0 is +30° forward,
/// row 7 is -30° backward; column 0 is 30° left, column 7 is 30° right.
enum ZoneGrid {
    static let side = 8
    static let span = 30.0

    static func index(pitch: Double, roll: Double) -> Int {
        let step = span * 2 / Double(side)
        let row = min(max(Int((span - pitch) / step), 0), side - 1)
        let col = min(max(Int((roll + span) / step), 0), side - 1)
        return row * side + col
    }
}
