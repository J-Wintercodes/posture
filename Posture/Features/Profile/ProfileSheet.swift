import SwiftUI

/// Settings behind the profile button.
struct ProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let settings = app.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Profile")
                        Text("Your setup")
                            .font(.serif(34))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                            .frame(width: 36, height: 36)
                            .background(Theme.card, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.top, 22)

                coachSection(settings)
                toleranceSection(settings)
                autoStartSection(settings)

                SectionLabel("Focus places")
                PlacesEditor()

                #if DEBUG
                developerSection
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
    }

    // MARK: Coach

    private func coachSection(_ settings: SettingsStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("How Theo reaches you")
                Picker("Feedback", selection: settings.binding(\.feedback)) {
                    ForEach(FeedbackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.value.feedback.detail)
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                HStack {
                    Text("Coach language")
                        .font(.ui(15, .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Picker("Coach language", selection: settings.binding(\.coachLanguage)) {
                        ForEach(CoachLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .tint(Theme.mint)
                }
            }
        }
    }

    // MARK: Reading tolerance

    private func toleranceSection(_ settings: SettingsStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Reading & notes tolerance")
                Picker("Tolerance", selection: settings.binding(\.readingTolerance)) {
                    ForEach(ReadingTolerance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text("A quick, deliberate look down at paper or a tablet is left alone for \(budgetLabel(settings.value.readingTolerance.budget)) before it slowly starts to count. A slow sink into the chair always counts.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func budgetLabel(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) minutes"
    }

    // MARK: Auto-start

    private func autoStartSection(_ settings: SettingsStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Auto-start")
                Toggle(isOn: settings.binding(\.autoStartEnabled)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start at my focus places")
                            .font(.ui(15, .medium))
                            .foregroundStyle(Theme.text)
                        Text("\(Fmt.hoursLabel(settings.value.workStartMinutes)) – \(Fmt.hoursLabel(settings.value.workEndMinutes)), with AirPods in")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .tint(Theme.teal)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: app.power.isLowPowerMode ? "bolt.slash.fill" : "bolt.fill")
                        .foregroundStyle(app.power.isLowPowerMode ? Theme.amber : Theme.mint)
                    Text(app.power.isLowPowerMode
                         ? "Low Power Mode is on: nothing starts on its own and a running session pauses its sensors."
                         : "Battery guard is armed: in Low Power Mode, or below 20% without a charger, nothing starts on its own.")
                        .font(.ui(13))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !app.power.hasAlwaysAccess {
                    Button {
                        app.power.requestAccess()
                    } label: {
                        Text("Arrival detection needs location set to \"Always\". Tap to allow.")
                            .font(.ui(13, .medium))
                            .foregroundStyle(Theme.amber)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
    }

    // MARK: Developer

    #if DEBUG
    private var developerSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Developer")
                Button("Load a sample week") { app.store.loadSampleWeek() }
                    .font(.ui(15, .medium))
                    .foregroundStyle(Theme.mint)
                Button("Erase journal") { app.store.eraseAll() }
                    .font(.ui(15, .medium))
                    .foregroundStyle(Theme.red)
                Button("Run onboarding again") {
                    app.settings.update { $0.onboardingDone = false }
                    dismiss()
                }
                .font(.ui(15, .medium))
                .foregroundStyle(Theme.textDim)
            }
        }
    }
    #endif
}
