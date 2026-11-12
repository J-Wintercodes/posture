import Foundation

/// The auto-start rule as a pure function, so it can be tested without
/// CoreLocation or a battery.
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
        var workStartMinutes = 510
        var workEndMinutes = 1080
        var workDays: Set<Int> = [2, 3, 4, 5, 6]
        var placeName: String?
        var headphonesConnected = false
        var snoozedUntil: Date?
        var calendar = Calendar.current
    }

    enum Block: Equatable {
        case lowPowerMode, lowBattery, disabled, sessionActive, snoozed
        case notAtFocusPlace, outsideWorkHours, noHeadphones
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
        guard isWorkTime(input) else { return .blocked(.outsideWorkHours) }
        guard input.headphonesConnected else { return .blocked(.noHeadphones) }
        return .start(placeName: place)
    }

    static func isWorkTime(_ input: Input) -> Bool {
        let parts = input.calendar.dateComponents([.weekday, .hour, .minute], from: input.now)
        guard let weekday = parts.weekday, input.workDays.contains(weekday) else { return false }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minute >= input.workStartMinutes && minute < input.workEndMinutes
    }
}
