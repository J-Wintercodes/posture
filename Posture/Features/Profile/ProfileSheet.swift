import SwiftUI

/// Settings behind the profile button.
struct ProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var voices: [CoachVoice.Option] = []
    @State private var hasNaturalVoice = true

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
        .onAppear { reloadVoices() }
        .onChange(of: app.settings.value.coachLanguage) { _, _ in reloadVoices() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the Settings app, where a better voice may
            // just have been downloaded.
            if phase == .active { reloadVoices() }
        }
    }

    // MARK: Voice

    private func reloadVoices() {
        let language = app.settings.value.coachLanguage
        voices = CoachVoice.options(for: language)
        hasNaturalVoice = CoachVoice.hasNaturalVoice(for: language)
        // A voice of the other language, or one that was deleted, falls back
        // to "Automatic".
        if let id = app.settings.value.coachVoiceID, !voices.contains(where: { $0.id == id }) {
            app.settings.update { $0.coachVoiceID = nil }
        }
    }

    private func playVoiceSample() {
        let config = app.settings.value
        app.coach.language = config.coachLanguage
        app.coach.voiceID = config.coachVoiceID
        app.coach.preview()
    }

    @ViewBuilder
    private func voiceRows(_ settings: SettingsStore) -> some View {
        HStack {
            Text("Voice")
                .font(.ui(15, .medium))
                .foregroundStyle(Theme.text)
            Spacer()
            Picker("Voice", selection: settings.binding(\.coachVoiceID)) {
                Text("Automatic").tag(String?.none)
                ForEach(voices) { option in
                    Text(option.label).tag(String?.some(option.id))
                }
            }
            .tint(Theme.mint)
        }
        Button {
            playVoiceSample()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                Text("Play a sample")
                    .font(.ui(14, .medium))
            }
            .foregroundStyle(Theme.mint)
        }
        if !hasNaturalVoice {
            let language = settings.value.coachLanguage == .de ? "German" : "English"
            Text("Theo is using the basic iOS voice. For a natural-sounding one, download an Enhanced or Premium voice once in the Settings app: Accessibility › Spoken Content › Voices › \(language). Theo then uses it automatically.")
                .font(.ui(13))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                voiceRows(settings)
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
