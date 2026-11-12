import Foundation

/// Everything Theo can be asked to convey.
enum CoachCue: Equatable {
    case sessionStarted(auto: Bool)
    case sessionEnded
    case nudge(NudgeKind, level: Int)
    case recovered
    case breakSuggested(BreakReason)
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
        guard let body = line(for: cue, language: language, variant: 0) else { return nil }
        switch cue {
        case .nudge:
            return (language == .de ? "Haltung" : "Posture", body)
        case .breakSuggested:
            return (language == .de ? "Kurze Pause?" : "Time for a reset?", body)
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
        case .breakSuggested(let reason):
            switch reason {
            case .fatigueTrend:
                return [de
                    ? "Deine Haltung lässt seit ein paar Minuten nach. Dreißig Sekunden Reset?"
                    : "Your posture has been fading for a few minutes. Thirty second reset?"]
            case .repeatedSlouch:
                return [de
                    ? "Du sackst immer wieder ein. Zeit für eine kurze Pause."
                    : "You keep sinking. Time for a short break."]
            case .longSit:
                return [de
                    ? "Du sitzt schon lange. Steh kurz auf und streck dich."
                    : "You've been sitting a long while. Stand up and stretch for a moment."]
            }
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
