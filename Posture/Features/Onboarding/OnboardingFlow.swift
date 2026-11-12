import SwiftUI

/// First-launch setup: use case, focus hours, focus places, permissions and
/// the first calibration.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var app
    @State private var step = 0

    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 12)
                .padding(.horizontal, 24)

            Group {
                switch step {
                case 0: UseCaseStep()
                case 1: HoursStep()
                case 2: PlacesStep()
                case 3: PermissionsStep()
                default: CalibrationView(embedded: true, onDone: finish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)

            if step < stepCount - 1 {
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.mint : Color.white.opacity(0.10))
                    .frame(height: 3)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 52, height: 52)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                }
                .accessibilityLabel("Back")
            }
            PillButton(title: "Continue") {
                withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
            }
        }
    }

    private func finish() {
        app.settings.update { $0.onboardingDone = true }
        app.power.sync(places: app.settings.value.places)
    }
}

/// Shared layout of an onboarding page.
private struct StepPage<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(eyebrow, color: Theme.mint)
                Text(title)
                    .font(.serif(34))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.ui(15))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: 1. Use case

private struct UseCaseStep: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let current = app.settings.value.useCase
        StepPage(
            eyebrow: "Step 1 of 5",
            title: "When does your posture suffer most?",
            subtitle: "This sets what the coach watches first. You can change it later."
        ) {
            ForEach(UseCase.allCases) { option in
                let isSelected = option == current
                Button {
                    app.settings.update { $0.useCase = option }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: option.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.mint : Theme.textDim)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.05), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .font(.ui(16, .semibold))
                                .foregroundStyle(Theme.text)
                            Text(option == .desk ? option.detail : option.detail + " Tracking for this arrives later; Desk Mode works today.")
                                .font(.ui(13))
                                .foregroundStyle(Theme.textDim)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Theme.mint : Theme.textFaint)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(isSelected ? Theme.mint.opacity(0.7) : Theme.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

// MARK: 2. Focus hours

private struct HoursStep: View {
    @Environment(AppModel.self) private var app

    /// Monday first, as Calendar weekday numbers.
    private let weekdays: [(Int, String)] = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]

    var body: some View {
        let settings = app.settings
        StepPage(
            eyebrow: "Step 2 of 5",
            title: "When do you usually focus?",
            subtitle: "Sessions only start on their own inside this window. Outside it the app stays asleep."
        ) {
            Card {
                VStack(spacing: 14) {
                    timeRow("From", minutes: settings.binding(\.workStartMinutes))
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    timeRow("Until", minutes: settings.binding(\.workEndMinutes))
                }
            }
            SectionLabel("On these days")
                .padding(.top, 10)
            HStack(spacing: 8) {
                ForEach(weekdays.indices, id: \.self) { index in
                    let weekday = weekdays[index].0
                    let letter = weekdays[index].1
                    let isOn = settings.value.workDays.contains(weekday)
                    Button {
                        settings.update { value in
                            if isOn {
                                value.workDays.remove(weekday)
                            } else {
                                value.workDays.insert(weekday)
                            }
                        }
                    } label: {
                        Text(letter)
                            .font(.ui(14, .semibold))
                            .foregroundStyle(isOn ? .black : Theme.textDim)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(isOn ? Theme.mint : Theme.card, in: Circle())
                            .overlay(Circle().strokeBorder(isOn ? Color.clear : Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func timeRow(_ label: String, minutes: Binding<Int>) -> some View {
        let date = Binding<Date>(
            get: { Fmt.minutesToDate(minutes.wrappedValue) },
            set: { minutes.wrappedValue = Fmt.dateToMinutes($0) }
        )
        return HStack {
            Text(label)
                .font(.ui(16, .medium))
                .foregroundStyle(Theme.text)
            Spacer()
            DatePicker("", selection: date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(Theme.mint)
        }
    }
}

// MARK: 3. Focus places

struct PlacesEditor: View {
    @Environment(AppModel.self) private var app
    @State private var busy: PlaceKind? = nil
    @State private var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([PlaceKind.library, PlaceKind.home], id: \.self) { kind in
                row(kind)
            }
            if let note {
                Text(note)
                    .font(.ui(13))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ kind: PlaceKind) -> some View {
        let saved = app.settings.value.places.first { $0.kind == kind }
        return HStack(spacing: 14) {
            Image(systemName: kind.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(saved == nil ? Theme.textDim : Theme.mint)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.05), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.defaultName)
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Theme.text)
                Text(saved == nil ? "Not set" : "Saved · 120 m around this spot")
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
            if busy == kind {
                ProgressView().tint(Theme.mint)
            } else if let saved {
                Button("Remove") {
                    app.savePlaces(app.settings.value.places.filter { $0.id != saved.id })
                }
                .font(.ui(13, .semibold))
                .foregroundStyle(Theme.textDim)
            } else {
                Button("I'm here now") { capture(kind) }
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func capture(_ kind: PlaceKind) {
        note = nil
        guard app.power.hasAnyAccess else {
            app.power.requestAccess()
            note = "Allow location access in the prompt, then tap again."
            return
        }
        busy = kind
        app.power.currentLocation { location in
            busy = nil
            guard let location else {
                note = "Could not get a location fix. Try again near a window."
                return
            }
            var places = app.settings.value.places.filter { $0.kind != kind }
            places.append(FocusPlace(
                name: kind.defaultName,
                kind: kind,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ))
            app.savePlaces(places)
        }
    }
}

private struct PlacesStep: View {
    var body: some View {
        StepPage(
            eyebrow: "Step 3 of 5",
            title: "Where do you focus?",
            subtitle: "Save a place while you are there. When you arrive with AirPods in, during your focus hours, a session starts by itself. You can also add places later in your profile."
        ) {
            PlacesEditor()
        }
    }
}

// MARK: 4. Permissions

private struct PermissionsStep: View {
    @Environment(AppModel.self) private var app
    @State private var notificationsOn = false

    var body: some View {
        let motionOn = app.headphones.authorization == .authorized
        let locationOn = app.power.hasAlwaysAccess
        StepPage(
            eyebrow: "Step 4 of 5",
            title: "Three permissions, each for one reason",
            subtitle: "Nothing leaves your phone. There is no camera and no account."
        ) {
            permissionRow(
                icon: "airpodspro",
                title: "Motion & Fitness",
                detail: "Reads the motion sensors in your AirPods. This is how posture is measured.",
                isOn: motionOn,
                actionTitle: "Allow"
            ) {
                app.headphones.requestAuthorization()
            }
            permissionRow(
                icon: "location.fill",
                title: "Location · Always",
                detail: "Only to notice that you arrived at a focus place. Asked in two steps by iOS.",
                isOn: locationOn,
                actionTitle: app.power.hasAnyAccess ? "Upgrade" : "Allow"
            ) {
                app.power.requestAccess()
            }
            permissionRow(
                icon: "bell.fill",
                title: "Notifications",
                detail: "Tells you when a session started on its own, and carries silent nudges to your Watch.",
                isOn: notificationsOn,
                actionTitle: "Allow"
            ) {
                Task { notificationsOn = await Notifier.requestAuthorization() }
            }
        }
        .task { notificationsOn = await Notifier.isAuthorized() }
    }

    private func permissionRow(icon: String, title: String, detail: String, isOn: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? Theme.mint : Theme.textDim)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.05), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.ui(13))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.mint)
            } else {
                Button(actionTitle, action: action)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}
