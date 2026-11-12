import AppIntents

// Study mode for Siri and the Shortcuts app.
//
// Both actions run without opening the app. The app is launched in the
// background if it is not running, study mode is switched, and Siri reads
// the answer.
//
// iOS requires the app's name in a phrase that works out of the box, so
// "Mach Lernmodus an in Posture" works right away. The phrases are German
// only, and Siri must be set to German: project.yml marks German as the
// app's base language, because Siri ignores phrases whose language does not
// match its own. For the bare sentence
// "Hey Siri, mach Lernmodus an", create a shortcut with that name in the
// Shortcuts app and give it the action "Lernmodus starten".

struct StartStudyModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Lernmodus starten"
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = AppModel.shared.startStudyMode()
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: reply)))
    }
}

struct StopStudyModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Lernmodus beenden"
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = AppModel.shared.stopStudyMode()
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: reply)))
    }
}

struct PostureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartStudyModeIntent(),
            phrases: [
                "Mach Lernmodus an in \(.applicationName)",
                "Lernmodus an in \(.applicationName)",
                "Starte Lernmodus in \(.applicationName)",
                "\(.applicationName) Lernmodus starten"
            ],
            shortTitle: "Lernmodus an",
            systemImageName: "book.fill"
        )
        AppShortcut(
            intent: StopStudyModeIntent(),
            phrases: [
                "Mach Lernmodus aus in \(.applicationName)",
                "Lernmodus aus in \(.applicationName)",
                "Beende Lernmodus in \(.applicationName)",
                "\(.applicationName) Lernmodus beenden"
            ],
            shortTitle: "Lernmodus aus",
            systemImageName: "book.closed.fill"
        )
    }
}
