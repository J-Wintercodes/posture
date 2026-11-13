import SwiftUI
import UIKit

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

                nameSection(settings)
                coachSection(settings)
                sensitivitySection(settings)
                toleranceSection(settings)
                dayPlanSection(settings)
                eveningSection(settings)
                siriSection
                arrivalSection(settings)

                SectionLabel("Places")
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
        // The plan follows the calendar switch and the word lists as they
        // are edited.
        .onChange(of: app.settings.value.calendarEnabled) { _, _ in app.settingsChanged() }
        .onChange(of: app.settings.value.libraryKeywords) { _, _ in app.settingsChanged() }
        .onChange(of: app.settings.value.homeKeywords) { _, _ in app.settingsChanged() }
        .onChange(of: app.settings.value.gymKeywords) { _, _ in app.settingsChanged() }
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

    // MARK: Name

    private func nameSection(_ settings: SettingsStore) -> some View {
        Card {
            HStack(spacing: 12) {
                Text("Your name")
                    .font(.ui(15, .medium))
                    .foregroundStyle(Theme.text)
                TextField("For the greeting", text: settings.binding(\.userName))
                    .font(.ui(15))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
        }
    }

    // MARK: Sensitivity

    private func sensitivitySection(_ settings: SettingsStore) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("How quickly it beeps")
                Picker("Sensitivity", selection: settings.binding(\.sensitivity)) {
                    ForEach(Sensitivity.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.value.sensitivity.detail + " A low beep when you slouch, a brighter one when you sit well again. Applies to a running session right away.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text("A quick, deep look down at paper or a tablet is left alone for \(budgetLabel(settings.value.readingTolerance.budget)) before it slowly starts to count. Sinking into the chair always counts, fast or slow.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func budgetLabel(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) minutes"
    }

    // MARK: Day plan

    private func dayPlanSection(_ settings: SettingsStore) -> some View {
        let found = app.calendar.events
        let libraryCount = found.filter { $0.kind == .library }.count
        let homeCount = found.filter { $0.kind == .home }.count
        let gymCount = found.filter { $0.kind == .gym }.count
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Check-ins")
                HStack {
                    Text("Check in after")
                        .font(.ui(15, .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Picker("Check in after", selection: settings.binding(\.checkInMinutes)) {
                        ForEach([20, 30, 45, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .tint(Theme.mint)
                }
                Text("After that long without a break the coach says what is needed: quiet and seated in the library, light before the gym, and the floor routines for back and nervous system only at home.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                Toggle(isOn: settings.binding(\.calendarEnabled)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Use my calendar")
                            .font(.ui(15, .medium))
                            .foregroundStyle(Theme.text)
                        Text("Reads the iPhone calendar, including subscribed iCal feeds. Read only, nothing leaves the phone.")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.teal)
                if settings.value.calendarEnabled {
                    if app.calendar.hasAccess {
                        Text("Next 24 hours: \(libraryCount) library study, \(homeCount) home study, \(gymCount) gym. Everything else in your calendar is ignored. The location check has the last word.")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button {
                            connectCalendar()
                        } label: {
                            Text(app.calendar.wasDenied
                                 ? "Calendar access is off. Tap to allow it in the iOS Settings."
                                 : "Tap to allow calendar access.")
                                .font(.ui(13, .medium))
                                .foregroundStyle(Theme.amber)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    keywordField("Title for studying at the library", text: settings.binding(\.libraryKeywords))
                    keywordField("Title for studying at home", text: settings.binding(\.homeKeywords))
                    keywordField("Titles that mean gym", text: settings.binding(\.gymKeywords))
                    Text("Only the title of an entry is read. Lectures, rooms and everything else are ignored. Separate several with commas.")
                        .font(.ui(12))
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func keywordField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.ui(13, .medium))
                .foregroundStyle(Theme.textDim)
            TextField(label, text: text, axis: .vertical)
                .font(.ui(14))
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func connectCalendar() {
        if app.calendar.wasDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            Task { await app.calendar.requestAccess() }
        }
    }

    // MARK: Evening and home

    private func eveningSection(_ settings: SettingsStore) -> some View {
        let bedtime = Binding<Date>(
            get: { Fmt.minutesToDate(settings.value.bedMinutes) },
            set: { newValue in settings.update { $0.bedMinutes = Fmt.dateToMinutes(newValue) } }
        )
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Evening & home")
                Toggle(isOn: settings.binding(\.painCheckEnabled)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ask about pain before bed")
                            .font(.ui(15, .medium))
                            .foregroundStyle(Theme.text)
                        Text("A notification at bedtime. Press and hold it for a quick answer, or tap it for the scale from 0 to 10.")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.teal)
                HStack {
                    Text("Bedtime")
                        .font(.ui(15, .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    DatePicker("Bedtime", selection: bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Theme.mint)
                }
                Rectangle().fill(Theme.stroke).frame(height: 1)
                Toggle(isOn: settings.binding(\.homeSuggestionsEnabled)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Calm suggestions at home")
                            .font(.ui(15, .medium))
                            .foregroundStyle(Theme.text)
                        Text("At most two a day while you are home and not in study mode: one in the afternoon, one an hour before bed. A routine for back or nervous system, without sound. Nothing you have to do.")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.teal)
            }
        }
    }

    // MARK: Siri

    private var siriSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Study mode with Siri")
                Text("At home, only the time in study mode counts as sitting. In a library study mode runs on its own, so Siri is for everywhere else.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                siriStep("1", "Works right away: \"Hey Siri, mach Lernmodus an in Posture\".")
                siriStep("2", "For the short sentence, open the Shortcuts app, tap +, add the action \"Lernmodus starten\" from Posture and name the shortcut \"Mach Lernmodus an\".")
                siriStep("3", "Do the same with \"Lernmodus beenden\" to switch it off by voice.")
            }
        }
    }

    private func siriStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.ui(12, .bold))
                .foregroundStyle(Theme.mint)
                .frame(width: 22, height: 22)
                .background(Theme.mint.opacity(0.12), in: Circle())
            Text(text)
                .font(.ui(13))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Arrival

    private func arrivalSection(_ settings: SettingsStore) -> some View {
        let isOn = settings.value.autoStudy
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("At a library")
                Toggle(isOn: settings.binding(\.autoStudy)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Study mode on its own")
                            .font(.ui(15, .medium))
                            .foregroundStyle(Theme.text)
                        Text("Nothing to start by hand. Study mode begins once you sit in one of your libraries with your AirPods in. It pauses when you get up or take them out, carries on when they are back in, and ends when you leave.")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.teal)
                if isOn {
                    Text("The AirPods have to be connected to this iPhone. While you are there the app stays awake to notice them, which costs some battery. After two hours without AirPods it stops waiting until you open the app.")
                        .font(.ui(13))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: app.power.isLowPowerMode ? "bolt.slash.fill" : "bolt.fill")
                            .foregroundStyle(app.power.isLowPowerMode ? Theme.amber : Theme.mint)
                        Text(app.power.isLowPowerMode
                             ? "Low Power Mode is on: study mode does not start on its own and a running session pauses its sensors."
                             : "Battery guard is armed: in Low Power Mode, or below 20% without a charger, study mode does not start on its own.")
                            .font(.ui(13))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Off: nothing starts on its own. The whole stay in a library counts as sitting, and you start study mode or tracking when you want.")
                        .font(.ui(13))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !app.power.hasAlwaysAccess {
                    Button {
                        app.power.requestAccess()
                    } label: {
                        Text("Noticing that you arrived or left needs location set to \"Always\". Tap to allow.")
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
                Button("Erase journal") {
                    app.store.eraseAll()
                    app.log.eraseAll()
                }
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
