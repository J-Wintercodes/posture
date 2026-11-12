import ActivityKit
import Foundation

/// The session card on the Lock Screen and in the Dynamic Island.
/// Compiled into both the app (which starts and updates it) and the widget
/// extension (which draws it).
struct PostureActivityAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable {
        case aligned
        case drifting
        case slouching
        case lookingDown
        case away
        case pausedLowPower
        case headphonesOut
    }

    struct ContentState: Codable, Hashable {
        var status: Status
        /// 0...100
        var score: Int
    }

    var startedAt: Date
    var placeName: String?
}
