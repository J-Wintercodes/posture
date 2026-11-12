import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if app.settings.value.onboardingDone {
                MainShell()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: app.settings.value.onboardingDone)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home, insights, tracker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .insights: return "Insights"
        case .tracker: return "Journal"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .insights: return "chart.xyaxis.line"
        case .tracker: return "calendar"
        }
    }
}

struct MainShell: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AppTab = .home

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home: HomeView()
                case .insights: InsightsView()
                case .tracker: TrackerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(selection: $tab)
                .padding(.bottom, 4)
        }
        .fullScreenCover(isPresented: $app.showLive) {
            LiveSessionView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
        .sheet(item: shellRoutine) { routine in
            RoutinePlayerView(routine: routine)
                .environment(app)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $app.showProfile, onDismiss: { app.settingsChanged() }) {
            ProfileSheet()
                .environment(app)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $app.showCalibration) {
            CalibrationView(onDone: { app.showCalibration = false })
                .environment(app)
                .preferredColorScheme(.dark)
        }
    }
}

extension MainShell {
    /// The live screen covers this one and shows routines itself, so while
    /// it is up the sheet here stays closed.
    fileprivate var shellRoutine: Binding<Routine?> {
        Binding(
            get: { app.showLive ? nil : app.activeRoutine },
            set: { app.activeRoutine = $0 }
        )
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(.ui(10, .medium))
                    }
                    .foregroundStyle(isSelected ? Theme.text : Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.white.opacity(0.08))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .padding(.horizontal, 48)
    }
}
