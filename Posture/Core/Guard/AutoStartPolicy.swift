import Foundation

/// The rule for study mode starting on its own, as a pure function so it can
/// be tested without CoreLocation or a battery.
///
/// It only says whether the session may be set up at a library. AirPods are
/// not part of it: the session is set up on arrival and then waits for them,
/// because nothing wakes the app when they go in later.
enum AutoStartPolicy {
    struct Input {
        var enabled = true
        /// A session is running, or study mode was started by hand.
        var sessionActive = false
        var isLowPowerMode = false
        /// 0...1, nil when unknown.
        var batteryLevel: Double?
        var isCharging = false
        var minBattery = 0.2
        var now = Date()
        /// Name of the library the phone is at, nil when it is at none.
        var placeName: String?
        var snoozedUntil: Date?
    }

    enum Block: Equatable {
        case lowPowerMode, lowBattery, disabled, sessionActive, snoozed
        case notAtFocusPlace
    }

    enum Decision: Equatable {
        case start(placeName: String)
        case blocked(Block)
    }

    static func decide(_ input: Input) -> Decision {
        // Battery guard first, and without exceptions: in Low Power Mode a
        // session never starts on its own.
        if input.isLowPowerMode { return .blocked(.lowPowerMode) }
        if let level = input.batteryLevel, level < input.minBattery, !input.isCharging {
            return .blocked(.lowBattery)
        }
        guard input.enabled else { return .blocked(.disabled) }
        guard !input.sessionActive else { return .blocked(.sessionActive) }
        if let until = input.snoozedUntil, input.now < until { return .blocked(.snoozed) }
        guard let place = input.placeName else { return .blocked(.notAtFocusPlace) }
        return .start(placeName: place)
    }
}
