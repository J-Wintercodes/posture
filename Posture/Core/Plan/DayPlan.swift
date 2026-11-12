import Foundation

// The day plan: what the calendar says, what the location says, and which of
// the two wins. Pure Swift, no EventKit and no CoreLocation, so the rules can
// be unit-tested.

enum EventKind: String, Codable, Sendable {
    case uni, gym, other
}

/// One calendar entry, already stripped of EventKit types.
struct PlannedEvent: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var kind: EventKind
}

/// Decides from the words in a calendar entry whether it is university, gym
/// or neither. The word lists are editable in the profile.
enum EventClassifier {
    static let defaultUniKeywords = "uni, universität, university, vorlesung, vl, übung, seminar, tutorium, praktikum, lecture, klausur, hörsaal, campus"
    static let defaultGymKeywords = "gym, fitness, training, workout, sport, krafttraining, unisport, hochschulsport, mcfit, fitx"

    /// Splits "gym, fitness , Training" into ["gym", "fitness", "training"].
    static func keywords(_ list: String) -> [String] {
        list.split(separator: ",")
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func kind(title: String, location: String?, calendarName: String?, uni: [String], gym: [String]) -> EventKind {
        let text = normalize([title, location ?? "", calendarName ?? ""].joined(separator: " "))
        let words = tokens(text)
        // Gym first: "Unisport" is training, not a lecture.
        if gym.contains(where: { matches($0, text: text, words: words) }) { return .gym }
        if uni.contains(where: { matches($0, text: text, words: words) }) { return .uni }
        return .other
    }

    /// Short keywords ("vl", "uni", "gym") must be a whole word, otherwise
    /// "uni" would hit "Community". Longer ones match the start of a word,
    /// so "vorlesung" hits "Vorlesungsreihe" but "sport" does not hit
    /// "Transport". A keyword with a space or a hyphen is searched as is.
    static func matches(_ keyword: String, text: String, words: [String]) -> Bool {
        guard !keyword.isEmpty else { return false }
        if keyword.contains(where: { !isWordCharacter($0) }) {
            return text.contains(keyword)
        }
        if keyword.count <= 3 {
            return words.contains(keyword)
        }
        return words.contains { $0.hasPrefix(keyword) }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { !isWordCharacter($0) }).map { String($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

/// Where the user is, as far as the coach is concerned.
enum Situation: String, Sendable {
    case home, library, uni, gym, elsewhere
}

/// The answer to "what is going on right now?".
struct DayContext: Equatable, Sendable {
    enum Source: Sendable {
        case location, calendar, none
    }

    var situation: Situation = .elsewhere
    var source: Source = .none
    /// Name of the saved place the phone is at, if any.
    var placeName: String?
    /// The university or gym entry that is running right now.
    var event: PlannedEvent?
    /// The calendar claims something the location does not back up.
    var calendarOverruled = false
    /// Set while a gym entry starts within the next 90 minutes.
    var gymInMinutes: Int?
    var gymAt: Date?
    /// A gym entry ended within the last two hours.
    var afterGym = false
}

enum DayPlanner {
    struct Input {
        var now = Date()
        var events: [PlannedEvent] = []
        /// Kind and name of the saved place the phone is inside. Nil when it
        /// is at none of them, or when the location is not known.
        var placeKind: PlaceKind?
        var placeName: String?
        /// Kinds of place the user has saved at least once.
        var savedKinds: Set<PlaceKind> = []
        /// True when "at none of the saved places" can be trusted.
        var locationKnown = false
    }

    static let gymLead: TimeInterval = 90 * 60
    static let gymAfterglow: TimeInterval = 120 * 60

    /// The calendar is the plan, the location is the check.
    ///
    /// - Inside a saved place the place wins, whatever the calendar says.
    /// - Outside all of them the calendar is believed, unless the user has
    ///   saved a place for exactly that (a university, a gym) and the phone
    ///   is known not to be there. Then the entry is taken as skipped.
    static func resolve(_ input: Input) -> DayContext {
        let now = input.now
        var context = DayContext()
        let relevant = input.events.filter { $0.kind != .other }
        let running = relevant.filter { $0.start <= now && now < $0.end }
        let current = running.first { $0.kind == .gym } ?? running.first
        context.event = current

        if let kind = input.placeKind {
            context.source = .location
            context.placeName = input.placeName
            context.situation = situation(for: kind)
            if let current, situation(for: current.kind) != context.situation {
                context.calendarOverruled = true
            }
        } else if let current {
            let needed: PlaceKind = current.kind == .gym ? .gym : .uni
            if input.locationKnown, input.savedKinds.contains(needed) {
                context.calendarOverruled = true
            } else {
                context.situation = situation(for: current.kind)
                context.source = .calendar
            }
        }

        if context.situation != .gym {
            let upcoming = relevant
                .filter { $0.kind == .gym && $0.start > now && $0.start.timeIntervalSince(now) <= gymLead }
                .min { $0.start < $1.start }
            if let upcoming {
                context.gymAt = upcoming.start
                context.gymInMinutes = max(1, Int((upcoming.start.timeIntervalSince(now) / 60).rounded()))
            }
            context.afterGym = relevant.contains {
                $0.kind == .gym && $0.end <= now && now.timeIntervalSince($0.end) <= gymAfterglow
            }
        }
        return context
    }

    static func situation(for kind: PlaceKind) -> Situation {
        switch kind {
        case .home: return .home
        case .library: return .library
        case .uni: return .uni
        case .gym: return .gym
        case .other: return .elsewhere
        }
    }

    static func situation(for kind: EventKind) -> Situation {
        switch kind {
        case .uni: return .uni
        case .gym: return .gym
        case .other: return .elsewhere
        }
    }
}
