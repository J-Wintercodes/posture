import Foundation

/// Everything Theo can be asked to convey.
enum CoachCue: Equatable {
    case sessionStarted(auto: Bool)
    case sessionEnded
    case nudge(NudgeKind, level: Int)
    case recovered
    /// A check-in from the day coach: what is needed now. The texts are
    /// already in the coach language. Without a routine it is only an
    /// announcement (in a lecture).
    case checkIn(spoken: String, title: String, body: String, routineID: String?)
    case pausedLowPower
    case resumed
    case uprightSet
}

/// Theo's lines. Short, calm, and never the same sentence twice in a row.
enum CoachScript {
    static func line(for cue: CoachCue, language: CoachLanguage, variant: Int) -> String? {
        let options = lines(for: cue, language: language)
        guard !options.isEmpty else { return nil }
        return options[abs(variant) % options.count]
    }

    /// What Theo says when a voice is tried out in the profile.
    static func preview(language: CoachLanguage) -> String {
        language == .de
            ? "Hallo, ich bin Theo. Schultern locker, Rücken lang."
            : "Hi, I'm Theo. Soft shoulders, long spine."
    }

    /// Title and body for the silent channel. Nil when a cue is not worth a
    /// notification.
    static func notification(for cue: CoachCue, language: CoachLanguage) -> (title: String, body: String)? {
        if case .checkIn(_, let title, let body, _) = cue {
            return (title, body)
        }
        guard let body = line(for: cue, language: language, variant: 0) else { return nil }
        switch cue {
        case .nudge:
            return (language == .de ? "Haltung" : "Posture", body)
        case .pausedLowPower:
            return (language == .de ? "Session pausiert" : "Session paused", body)
        default:
            return nil
        }
    }

    private static func lines(for cue: CoachCue, language: CoachLanguage) -> [String] {
        let de = language == .de
        switch cue {
        case .sessionStarted(let auto):
            if auto {
                return [de ? "Posture Session gestartet." : "Posture session started."]
            }
            return [de ? "Ich bin da. Sperr ruhig dein Handy." : "I'm here. Go ahead and lock your phone."]
        case .sessionEnded:
            return [de ? "Session beendet. Gut gemacht." : "Session ended. Nicely done."]
        case .nudge(let kind, let level):
            return nudgeLines(kind, firm: level > 1, de: de)
        case .recovered:
            return []
        case .checkIn(let spoken, _, _, _):
            return [spoken]
        case .pausedLowPower:
            return [de ? "Stromsparmodus aktiv. Ich pausiere." : "Low Power Mode is on. I'll pause."]
        case .resumed:
            return [de ? "Weiter geht's." : "Back on."]
        case .uprightSet:
            return [de ? "Aufrecht gespeichert." : "Upright set."]
        }
    }

    private static func nudgeLines(_ kind: NudgeKind, firm: Bool, de: Bool) -> [String] {
        switch kind {
        case .slouch:
            if firm {
                return de
                    ? ["Noch einmal: lang machen.", "Du sinkst wieder ein. Brustbein heben."]
                    : ["Once more: grow tall.", "You're sinking again. Lift your chest."]
            }
            return de
                ? ["Aufrichten.", "Scheitel nach oben.", "Schultern locker, Rücken lang."]
                : ["Sit tall.", "Float the crown of your head up.", "Soft shoulders, long spine."]
        case .neck:
            return de
                ? ["Lange nach unten geschaut. Blick kurz heben.", "Nacken entlasten: einmal geradeaus schauen."]
                : ["Long look down. Lift your eyes for a moment.", "Give your neck a break. Look straight ahead once."]
        case .tilt:
            return de
                ? ["Kopf gerade.", "Du stützt den Kopf ab. Einmal aufrichten."]
                : ["Level your head.", "You're propping your head up. Sit tall once."]
        case .recline:
            return de
                ? ["Du hängst zurück. Becken aufrichten."]
                : ["You're slumping back. Bring your hips under you."]
        }
    }
}
