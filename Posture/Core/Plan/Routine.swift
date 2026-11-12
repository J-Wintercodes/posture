import Foundation

/// A text in both coach languages. The screens show the English one, Theo
/// and the notifications use the coach language.
struct Localized: Equatable, Sendable {
    let en: String
    let de: String

    init(_ en: String, _ de: String) {
        self.en = en
        self.de = de
    }

    func text(_ language: CoachLanguage) -> String {
        language == .de ? de : en
    }
}

struct RoutineStep: Equatable, Sendable {
    let title: Localized
    let cue: Localized
    let seconds: Int
    let icon: String
}

/// A guided set of movements with a countdown.
struct Routine: Identifiable, Equatable, Sendable {
    let id: String
    let name: Localized
    /// How Theo says it after "Time for ...".
    let spokenName: Localized
    /// Short line under the name: "Neck & upper back".
    let focus: String
    let icon: String
    /// Needs a floor and some privacy. Only offered at home.
    let homeOnly: Bool
    /// Strength and nerve work is suggested once a day at most.
    let oncePerDay: Bool
    let steps: [RoutineStep]

    var seconds: Int { steps.reduce(0) { $0 + $1.seconds } }

    /// "30s", "2 min"
    var durationLabel: String {
        seconds < 60 ? "\(seconds)s" : "\(Int((Double(seconds) / 60).rounded())) min"
    }

    func durationWords(_ language: CoachLanguage) -> String {
        if seconds < 60 {
            return language == .de ? "\(seconds) Sekunden" : "\(seconds) seconds"
        }
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes == 1 {
            return language == .de ? "eine Minute" : "one minute"
        }
        return language == .de ? "\(minutes) Minuten" : "\(minutes) minutes"
    }
}

enum RoutineCatalog {
    static let all: [Routine] = [eyeReset, lectureReset, standUp, deskMobility, spineFlow, backStrength, nerveGlide, downshift]

    static func routine(id: String) -> Routine? {
        all.first { $0.id == id }
    }

    // MARK: Anywhere

    static let eyeReset = Routine(
        id: "eye-reset",
        name: Localized("Eye + Posture Reset", "Augen + Haltung"),
        spokenName: Localized("an eye and posture reset", "Augen und Haltung"),
        focus: "Neck & upper back",
        icon: "eye",
        homeOnly: false,
        oncePerDay: false,
        steps: [
            RoutineStep(
                title: Localized("Look far away", "In die Ferne schauen"),
                cue: Localized(
                    "Find the most distant point you can see and rest your eyes on it.",
                    "Such den am weitesten entfernten Punkt und lass die Augen dort ruhen."
                ),
                seconds: 10,
                icon: "eye"
            ),
            RoutineStep(
                title: Localized("Chin tuck", "Kinn zurück"),
                cue: Localized(
                    "Slide your head straight back, as if making a double chin. Hold, release, repeat.",
                    "Schieb den Kopf gerade nach hinten, wie für ein Doppelkinn. Halten, lösen, wiederholen."
                ),
                seconds: 10,
                icon: "arrow.left.and.right"
            ),
            RoutineStep(
                title: Localized("Open the chest", "Brust öffnen"),
                cue: Localized(
                    "Roll your shoulders back and down, squeeze the shoulder blades together.",
                    "Schultern nach hinten unten rollen, Schulterblätter zusammenziehen."
                ),
                seconds: 10,
                icon: "figure.mind.and.body"
            )
        ]
    )

    /// For a lecture hall: nothing a neighbour would notice.
    static let lectureReset = Routine(
        id: "lecture-reset",
        name: Localized("Lecture reset", "Vorlesungs-Reset"),
        spokenName: Localized("a quiet seated reset", "einen leisen Reset im Sitzen"),
        focus: "Invisible, in your seat",
        icon: "graduationcap.fill",
        homeOnly: false,
        oncePerDay: false,
        steps: [
            RoutineStep(
                title: Localized("Find your sit bones", "Auf die Sitzhöcker"),
                cue: Localized(
                    "Both feet flat. Rock your pelvis forward and back, then stop in the middle.",
                    "Beide Füße auf den Boden. Becken vor und zurück kippen, dann in der Mitte bleiben."
                ),
                seconds: 15,
                icon: "arrow.up.and.down"
            ),
            RoutineStep(
                title: Localized("Shoulder blades down", "Schulterblätter runter"),
                cue: Localized(
                    "Draw the shoulder blades gently back and down. Hold five seconds, let go, repeat.",
                    "Schulterblätter sanft nach hinten unten ziehen. Fünf Sekunden halten, lösen, wiederholen."
                ),
                seconds: 15,
                icon: "figure.mind.and.body"
            ),
            RoutineStep(
                title: Localized("Eyes to the far wall", "Blick zur hinteren Wand"),
                cue: Localized(
                    "Look at the farthest thing in the room and blink slowly a few times.",
                    "Schau auf das Entfernteste im Raum und blinzle ein paar Mal langsam."
                ),
                seconds: 15,
                icon: "eye"
            )
        ]
    )

    static let standUp = Routine(
        id: "stand-up",
        name: Localized("Stand & move", "Aufstehen & bewegen"),
        spokenName: Localized("standing up and moving", "Aufstehen und Bewegen"),
        focus: "Hips & circulation",
        icon: "figure.walk",
        homeOnly: false,
        oncePerDay: false,
        steps: [
            RoutineStep(
                title: Localized("Stand up and walk", "Aufstehen und gehen"),
                cue: Localized(
                    "Leave the chair. Walk a little, get some water.",
                    "Weg vom Stuhl. Ein paar Schritte gehen, Wasser holen."
                ),
                seconds: 60,
                icon: "figure.walk"
            ),
            RoutineStep(
                title: Localized("Standing back bend", "Rückbeuge im Stehen"),
                cue: Localized(
                    "Hands on your hips, lean back gently five times.",
                    "Hände an die Hüften, fünfmal sanft nach hinten lehnen."
                ),
                seconds: 20,
                icon: "figure.stand"
            ),
            RoutineStep(
                title: Localized("Hip flexor, left", "Hüftbeuger links"),
                cue: Localized(
                    "Step the left leg back, tuck your tailbone under and push the hip forward.",
                    "Linkes Bein nach hinten, Steißbein einrollen und die Hüfte nach vorn schieben."
                ),
                seconds: 20,
                icon: "figure.flexibility"
            ),
            RoutineStep(
                title: Localized("Hip flexor, right", "Hüftbeuger rechts"),
                cue: Localized(
                    "Now the right leg back. Tailbone under, hip forward.",
                    "Jetzt das rechte Bein nach hinten. Steißbein einrollen, Hüfte nach vorn."
                ),
                seconds: 20,
                icon: "figure.flexibility"
            )
        ]
    )

    static let deskMobility = Routine(
        id: "desk-mobility",
        name: Localized("Upper back opener", "Oberer Rücken"),
        spokenName: Localized("an upper back opener", "den oberen Rücken"),
        focus: "Thoracic spine, seated",
        icon: "figure.flexibility",
        homeOnly: false,
        oncePerDay: false,
        steps: [
            RoutineStep(
                title: Localized("Lean back over the chair", "Über die Lehne strecken"),
                cue: Localized(
                    "Hands behind your head, lean back over the backrest, elbows wide. Breathe out as you go back.",
                    "Hände hinter den Kopf, über die Lehne nach hinten strecken, Ellbogen weit. Beim Zurücklehnen ausatmen."
                ),
                seconds: 30,
                icon: "figure.flexibility"
            ),
            RoutineStep(
                title: Localized("Seated twist", "Drehung im Sitzen"),
                cue: Localized(
                    "Turn your chest to the left and hold the backrest for three breaths. Then the right side.",
                    "Brustkorb nach links drehen und drei Atemzüge an der Lehne festhalten. Dann nach rechts."
                ),
                seconds: 30,
                icon: "arrow.triangle.2.circlepath"
            ),
            RoutineStep(
                title: Localized("Neck, side to side", "Nacken seitlich"),
                cue: Localized(
                    "Let the right ear sink toward the shoulder and breathe. Change sides halfway.",
                    "Rechtes Ohr zur Schulter sinken lassen und atmen. Nach der Hälfte die Seite wechseln."
                ),
                seconds: 30,
                icon: "arrow.left.and.right"
            )
        ]
    )

    // MARK: At home only

    static let spineFlow = Routine(
        id: "spine-flow",
        name: Localized("Spine mobility flow", "Wirbelsäulen-Flow"),
        spokenName: Localized("a spine mobility flow on the floor", "einen Wirbelsäulen-Flow auf dem Boden"),
        focus: "Whole spine, on the floor",
        icon: "figure.yoga",
        homeOnly: true,
        oncePerDay: false,
        steps: [
            RoutineStep(
                title: Localized("Cat and cow", "Katze und Kuh"),
                cue: Localized(
                    "On hands and knees. Round the back as you breathe out, let it sink as you breathe in. Slowly.",
                    "Vierfüßlerstand. Beim Ausatmen den Rücken rund machen, beim Einatmen sinken lassen. Langsam."
                ),
                seconds: 45,
                icon: "figure.yoga"
            ),
            RoutineStep(
                title: Localized("Thread the needle, left", "Nadelöhr links"),
                cue: Localized(
                    "Slide the left arm under the right one, shoulder to the floor, and breathe into the upper back.",
                    "Linken Arm unter dem rechten durchschieben, Schulter zum Boden, in den oberen Rücken atmen."
                ),
                seconds: 30,
                icon: "arrow.triangle.2.circlepath"
            ),
            RoutineStep(
                title: Localized("Thread the needle, right", "Nadelöhr rechts"),
                cue: Localized(
                    "Now the right arm under the left one. Shoulder down, breathe.",
                    "Jetzt den rechten Arm unter dem linken durch. Schulter ablegen, atmen."
                ),
                seconds: 30,
                icon: "arrow.triangle.2.circlepath"
            ),
            RoutineStep(
                title: Localized("Child's pose", "Kindhaltung"),
                cue: Localized(
                    "Sit back on your heels, arms long, forehead down. Breathe into the lower back.",
                    "Auf die Fersen setzen, Arme lang, Stirn ablegen. In den unteren Rücken atmen."
                ),
                seconds: 30,
                icon: "figure.cooldown"
            ),
            RoutineStep(
                title: Localized("Sphinx", "Sphinx"),
                cue: Localized(
                    "Lie on your front and prop yourself on the forearms. Hips stay down. Easy, no pinching in the lower back.",
                    "Auf den Bauch legen und auf die Unterarme stützen. Hüfte bleibt unten. Locker, kein Druck im unteren Rücken."
                ),
                seconds: 45,
                icon: "figure.pilates"
            )
        ]
    )

    static let backStrength = Routine(
        id: "back-strength",
        name: Localized("Back stability", "Rücken-Stabilität"),
        spokenName: Localized("back stability work", "Rücken-Stabilität"),
        focus: "Core & back, on the floor",
        icon: "figure.core.training",
        homeOnly: true,
        oncePerDay: true,
        steps: [
            RoutineStep(
                title: Localized("Curl-up", "Curl-up"),
                cue: Localized(
                    "On your back, one knee bent, hands under the lower back. Lift head and shoulders a little, hold eight seconds, lower.",
                    "Rückenlage, ein Knie angewinkelt, Hände unter den unteren Rücken. Kopf und Schultern leicht anheben, acht Sekunden halten, ablegen."
                ),
                seconds: 40,
                icon: "figure.core.training"
            ),
            RoutineStep(
                title: Localized("Side plank, left", "Seitstütz links"),
                cue: Localized(
                    "On the left forearm, knees or feet on the floor, body in one line.",
                    "Auf den linken Unterarm, Knie oder Füße am Boden, Körper in einer Linie."
                ),
                seconds: 30,
                icon: "figure.core.training"
            ),
            RoutineStep(
                title: Localized("Side plank, right", "Seitstütz rechts"),
                cue: Localized(
                    "Now the right forearm. One line from head to knees.",
                    "Jetzt auf den rechten Unterarm. Eine Linie vom Kopf bis zu den Knien."
                ),
                seconds: 30,
                icon: "figure.core.training"
            ),
            RoutineStep(
                title: Localized("Bird dog", "Bird Dog"),
                cue: Localized(
                    "On hands and knees. Reach one arm and the opposite leg long, hold eight seconds, switch. The back stays still.",
                    "Vierfüßlerstand. Einen Arm und das gegenüberliegende Bein lang strecken, acht Sekunden halten, wechseln. Der Rücken bleibt ruhig."
                ),
                seconds: 60,
                icon: "figure.pilates"
            ),
            RoutineStep(
                title: Localized("Glute bridge", "Beckenheben"),
                cue: Localized(
                    "On your back, feet flat. Lift the hips, squeeze, lower slowly.",
                    "Rückenlage, Füße aufgestellt. Hüfte heben, anspannen, langsam senken."
                ),
                seconds: 40,
                icon: "figure.cooldown"
            )
        ]
    )

    static let nerveGlide = Routine(
        id: "nerve-glide",
        name: Localized("Nerve glides", "Nervengleiten"),
        spokenName: Localized("gentle nerve glides", "sanftes Nervengleiten"),
        focus: "Sciatic & arm nerves, gentle",
        icon: "waveform.path.ecg",
        homeOnly: true,
        oncePerDay: true,
        steps: [
            RoutineStep(
                title: Localized("Sciatic glide, left", "Ischias-Gleiten links"),
                cue: Localized(
                    "Sit tall on a chair. Straighten the left knee while you look up, bend it while you look down. Smooth, never into pain.",
                    "Aufrecht auf einen Stuhl. Linkes Knie strecken und dabei nach oben schauen, beugen und nach unten schauen. Fließend, nie in den Schmerz."
                ),
                seconds: 30,
                icon: "waveform.path.ecg"
            ),
            RoutineStep(
                title: Localized("Sciatic glide, right", "Ischias-Gleiten rechts"),
                cue: Localized(
                    "Now the right knee. Straighten and look up, bend and look down.",
                    "Jetzt das rechte Knie. Strecken und nach oben schauen, beugen und nach unten schauen."
                ),
                seconds: 30,
                icon: "waveform.path.ecg"
            ),
            RoutineStep(
                title: Localized("Arm nerve glide, left", "Armnerv-Gleiten links"),
                cue: Localized(
                    "Left arm out to the side, palm up. Bend the wrist back as you tilt your head toward the arm, release as you tilt away.",
                    "Linken Arm zur Seite, Handfläche nach oben. Handgelenk nach hinten beugen und den Kopf zum Arm neigen, lösen und den Kopf wegneigen."
                ),
                seconds: 30,
                icon: "hand.raised.fill"
            ),
            RoutineStep(
                title: Localized("Arm nerve glide, right", "Armnerv-Gleiten rechts"),
                cue: Localized(
                    "Now the right arm. Slow and small, stop if it tingles more.",
                    "Jetzt der rechte Arm. Langsam und klein, aufhören, wenn es stärker kribbelt."
                ),
                seconds: 30,
                icon: "hand.raised.fill"
            )
        ]
    )

    static let downshift = Routine(
        id: "downshift",
        name: Localized("Nervous system downshift", "Nervensystem runterfahren"),
        spokenName: Localized("slow breathing, lying down", "ruhiges Atmen im Liegen"),
        focus: "Breathing, lying down",
        icon: "lungs.fill",
        homeOnly: true,
        oncePerDay: false,
        steps: [
            RoutineStep(
                title: Localized("Lie down, legs up", "Hinlegen, Beine hoch"),
                cue: Localized(
                    "On your back, lower legs on a chair or the sofa. Let the lower back get heavy.",
                    "Auf den Rücken, Unterschenkel auf einen Stuhl oder das Sofa. Den unteren Rücken schwer werden lassen."
                ),
                seconds: 30,
                icon: "figure.cooldown"
            ),
            RoutineStep(
                title: Localized("Long exhale", "Lang ausatmen"),
                cue: Localized(
                    "In through the nose for four, out for eight. One hand on the belly.",
                    "Vier Sekunden durch die Nase ein, acht Sekunden aus. Eine Hand auf den Bauch."
                ),
                seconds: 90,
                icon: "lungs.fill"
            ),
            RoutineStep(
                title: Localized("Let go", "Loslassen"),
                cue: Localized(
                    "Unclench the jaw, drop the shoulders, soften the hands.",
                    "Kiefer lösen, Schultern fallen lassen, Hände weich."
                ),
                seconds: 30,
                icon: "wind"
            ),
            RoutineStep(
                title: Localized("Quiet breathing", "Ruhig atmen"),
                cue: Localized(
                    "Breathe normally and stay a moment before you get up.",
                    "Normal weiteratmen und kurz liegen bleiben, bevor du aufstehst."
                ),
                seconds: 30,
                icon: "moon.fill"
            )
        ]
    )
}
