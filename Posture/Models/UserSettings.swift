import Foundation

enum UseCase: String, Codable, CaseIterable, Identifiable {
    case desk, walking, everyday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desk: return "Sitting at my desk / studying"
        case .walking: return "While walking"
        case .everyday: return "General back pain, all day"
        }
    }

    var detail: String {
        switch self {
        case .desk: return "Long focus blocks at the library or at home."
        case .walking: return "Head forward on the move."
        case .everyday: return "A bit of everything."
        }
    }

    var icon: String {
        switch self {
        case .desk: return "books.vertical.fill"
        case .walking: return "figure.walk"
        case .everyday: return "sun.max.fill"
        }
    }
}

enum FeedbackMode: String, Codable, CaseIterable, Identifiable {
    case voice, chime, silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: return "Voice"
        case .chime: return "Chime"
        case .silent: return "Silent"
        }
    }

    var detail: String {
        switch self {
        case .voice: return "Theo speaks softly in your AirPods."
        case .chime: return "A quiet two-note tone, no words."
        case .silent: return "A notification only. Taps your wrist if you wear a Watch."
        }
    }
}

enum CoachLanguage: String, Codable, CaseIterable, Identifiable {
    case en, de

    var id: String { rawValue }
    var title: String { self == .en ? "English" : "Deutsch" }
    var voiceCode: String { self == .en ? "en-US" : "de-DE" }

    static var systemDefault: CoachLanguage {
        Locale.current.language.languageCode?.identifier == "de" ? .de : .en
    }
}

enum ReadingTolerance: String, Codable, CaseIterable, Identifiable {
    case strict, balanced, relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict: return "Strict"
        case .balanced: return "Balanced"
        case .relaxed: return "Relaxed"
        }
    }

    /// Seconds a deliberate look-down is left completely alone.
    var budget: Double {
        switch self {
        case .strict: return 45
        case .balanced: return 120
        case .relaxed: return 300
        }
    }
}

enum PlaceKind: String, Codable, CaseIterable, Identifiable {
    case library, home, uni, gym, other

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .library: return "building.columns.fill"
        case .home: return "house.fill"
        case .uni: return "graduationcap.fill"
        case .gym: return "dumbbell.fill"
        case .other: return "mappin.circle.fill"
        }
    }

    var defaultName: String {
        switch self {
        case .library: return "Library"
        case .home: return "Home"
        case .uni: return "University"
        case .gym: return "Gym"
        case .other: return "Focus place"
        }
    }

    /// Places where arriving may start something on its own. Home never
    /// does: being home says nothing about sitting down to work.
    var startsOnArrival: Bool { self == .library || self == .other }

    /// Only one home; every other kind can be saved several times (two
    /// libraries, for example).
    var allowsSeveral: Bool { self != .home }
}

struct FocusPlace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: PlaceKind
    var latitude: Double
    var longitude: Double
    var radius: Double = 120

    /// The name, or the kind if the name was cleared.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.defaultName : trimmed
    }
}

/// What happens when the phone arrives at a library.
enum ArrivalAction: String, Codable, CaseIterable, Identifiable {
    case nothing, reminders, tracking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nothing: return "Nothing"
        case .reminders: return "Reminders"
        case .tracking: return "Tracking"
        }
    }

    var detail: String {
        switch self {
        case .nothing: return "Nothing starts on its own. You start reminders or tracking when you want."
        case .reminders: return "Timed check-ins start when you arrive and stop when you leave. No sensors, next to no battery."
        case .tracking: return "Posture tracking starts when you arrive with AirPods in. This is the mode that costs battery."
        }
    }
}

struct UserSettings: Codable {
    var onboardingDone = false
    var useCase: UseCase = .desk
    var places: [FocusPlace] = []
    var arrivalAction: ArrivalAction = .reminders
    var minBatteryForAutoStart = 0.2
    var feedback: FeedbackMode = .voice
    var coachLanguage: CoachLanguage = .systemDefault
    /// `AVSpeechSynthesisVoice.identifier` of the voice picked in the
    /// profile. Nil means "best installed voice".
    var coachVoiceID: String?
    var readingTolerance: ReadingTolerance = .balanced
    var dailyGoalMinutes = 120
    var baseline: Baseline?
    var seenLockHint = false
    /// Minutes of sitting between two check-ins.
    var checkInMinutes = 30
    /// Read the iPhone calendar to know about lectures and the gym.
    var calendarEnabled = true
    /// Comma separated words that mark a calendar entry as university.
    var uniKeywords = EventClassifier.defaultUniKeywords
    /// Comma separated words that mark a calendar entry as gym.
    var gymKeywords = EventClassifier.defaultGymKeywords

    var tuning: PostureTuning {
        var t = PostureTuning()
        t.lookDownBudget = readingTolerance.budget
        return t
    }

    enum CodingKeys: String, CodingKey {
        case onboardingDone, useCase, places, arrivalAction, minBatteryForAutoStart
        case feedback, coachLanguage, coachVoiceID, readingTolerance, dailyGoalMinutes
        case baseline, seenLockHint, checkInMinutes, calendarEnabled, uniKeywords, gymKeywords
    }
}

extension UserSettings {
    /// Every field is optional on disk. Settings saved by an older build
    /// (which lack the newer fields, and still carry the removed weekly
    /// schedule) load without being reset, and one unreadable field does
    /// not take the rest down with it.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .onboardingDone) { onboardingDone = v }
        if let v = try? c.decodeIfPresent(UseCase.self, forKey: .useCase) { useCase = v }
        if let v = try? c.decodeIfPresent([FocusPlace].self, forKey: .places) { places = v }
        if let v = try? c.decodeIfPresent(ArrivalAction.self, forKey: .arrivalAction) { arrivalAction = v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: .minBatteryForAutoStart) { minBatteryForAutoStart = v }
        if let v = try? c.decodeIfPresent(FeedbackMode.self, forKey: .feedback) { feedback = v }
        if let v = try? c.decodeIfPresent(CoachLanguage.self, forKey: .coachLanguage) { coachLanguage = v }
        if let v = try? c.decodeIfPresent(String.self, forKey: .coachVoiceID) { coachVoiceID = v }
        if let v = try? c.decodeIfPresent(ReadingTolerance.self, forKey: .readingTolerance) { readingTolerance = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) { dailyGoalMinutes = v }
        if let v = try? c.decodeIfPresent(Baseline.self, forKey: .baseline) { baseline = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .seenLockHint) { seenLockHint = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .checkInMinutes) { checkInMinutes = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .calendarEnabled) { calendarEnabled = v }
        if let v = try? c.decodeIfPresent(String.self, forKey: .uniKeywords) { uniKeywords = v }
        if let v = try? c.decodeIfPresent(String.self, forKey: .gymKeywords) { gymKeywords = v }

        // Builds before the arrival picker had a plain on/off switch. Keep
        // an "off" as "nothing starts on its own".
        if !c.contains(.arrivalAction),
           let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
           let wasOn = try? legacy.decodeIfPresent(Bool.self, forKey: .autoStartEnabled),
           !wasOn {
            arrivalAction = .nothing
        }
    }

    private enum LegacyKeys: String, CodingKey {
        case autoStartEnabled
    }
}
