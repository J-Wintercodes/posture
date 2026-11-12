import SwiftUI

@main
struct PostureApp: App {
    @State private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // One model for the screens and for Siri (App Intents), which can
        // launch the app in the background without any window.
        _app = State(initialValue: AppModel.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { app.appBecameActive() }
                }
        }
    }
}
