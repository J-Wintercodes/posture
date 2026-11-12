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

enum PlaceKind: String, Codable, CaseIterable {
    case library, home, other

    var icon: String {
        switch self {
        case .library: return "building.columns.fill"
        case .home: return "house.fill"
        case .other: return "mappin.circle.fill"
        }
    }

    var defaultName: String {
        switch self {
        case .library: return "University / Library"
        case .home: return "Desk at home"
        case .other: return "Focus place"
        }
    }
}

struct FocusPlace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: PlaceKind
    var latitude: Double
    var longitude: Double
    var radius: Double = 120
}

struct UserSettings: Codable {
    var onboardingDone = false
    var useCase: UseCase = .desk
    /// Minutes since midnight.
    var workStartMinutes = 8 * 60 + 30
    var workEndMinutes = 18 * 60
    /// Calendar weekdays, 1 = Sunday.
    var workDays: Set<Int> = [2, 3, 4, 5, 6]
    var places: [FocusPlace] = []
    var autoStartEnabled = true
    var minBatteryForAutoStart = 0.2
    var feedback: FeedbackMode = .voice
    var coachLanguage: CoachLanguage = .systemDefault
    /// `AVSpeechSynthesisVoice.identifier` of the voice picked in the
    /// profile. Nil means "best installed voice". Optional on purpose: a new
    /// non-optional field would fail to decode settings saved before it
    /// existed and reset them.
    var coachVoiceID: String?
    var readingTolerance: ReadingTolerance = .balanced
    var dailyGoalMinutes = 120
    var baseline: Baseline?
    var seenLockHint = false

    var tuning: PostureTuning {
        var t = PostureTuning()
        t.lookDownBudget = readingTolerance.budget
        return t
    }
}
