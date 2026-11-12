import AppIntents

// Study mode for Siri and the Shortcuts app.
//
// Both actions run without opening the app. The app is launched in the
// background if it is not running, study mode is switched, and Siri reads
// the answer.
//
// iOS requires the app's name in a phrase that works out of the box, so
// "Mach Lernmodus an in Posture" works right away. For the bare sentence
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
                "Start study mode in \(.applicationName)"
            ],
            shortTitle: "Lernmodus an",
            systemImageName: "book.fill"
        )
        AppShortcut(
            intent: StopStudyModeIntent(),
            phrases: [
                "Mach Lernmodus aus in \(.applicationName)",
                "Lernmodus aus in \(.applicationName)",
                "Stop study mode in \(.applicationName)"
            ],
            shortTitle: "Lernmodus aus",
            systemImageName: "book.closed.fill"
        )
    }
}
