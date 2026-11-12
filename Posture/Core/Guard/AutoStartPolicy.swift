import Foundation

/// The rule for starting posture tracking on arrival, as a pure function so
/// it can be tested without CoreLocation or a battery.
///
/// There is no weekly schedule any more: tracking starts on its own only at
/// a library, and only if the user chose that in the profile.
enum AutoStartPolicy {
    struct Input {
        var enabled = true
        var sessionActive = false
        var isLowPowerMode = false
        /// 0...1, nil when unknown.
        var batteryLevel: Double?
        var isCharging = false
        var minBattery = 0.2
        var now = Date()
        /// Name of the library the phone is at, nil when it is at none.
        var placeName: String?
        var headphonesConnected = false
        var snoozedUntil: Date?
    }

    enum Block: Equatable {
        case lowPowerMode, lowBattery, disabled, sessionActive, snoozed
        case notAtFocusPlace, noHeadphones
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
        guard input.headphonesConnected else { return .blocked(.noHeadphones) }
        return .start(placeName: place)
    }
}
