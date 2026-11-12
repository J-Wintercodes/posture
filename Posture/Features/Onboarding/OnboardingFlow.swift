import CoreLocation
import SwiftUI

/// First-launch setup: use case, places, permissions and the first
/// calibration. There is no schedule to fill in: tracking and reminders
/// start when the user wants them.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var app
    @State private var step = 0

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 12)
                .padding(.horizontal, 24)

            Group {
                switch step {
                case 0: UseCaseStep()
                case 1: PlacesStep()
                case 2: PermissionsStep()
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
        app.settings.update { value in
            value.onboardingDone = true
            value.askedForName = true
        }
        app.power.sync(places: app.settings.value.places)
        app.settingsChanged()
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
            eyebrow: "Step 1 of 4",
            title: "Hello. What should I call you?",
            subtitle: "The app greets you by name. Everything stays on your phone."
        ) {
            TextField("Your first name", text: app.settings.binding(\.userName))
                .font(.ui(17))
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            Text("When does your posture suffer most?")
                .font(.serif(24))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Text("This sets what the coach watches first. You can change it later.")
                .font(.ui(14))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
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

// MARK: 2. Places

/// The saved places: as many as needed (two libraries are two places), each
/// captured by standing there and tapping its kind.
struct PlacesEditor: View {
    @Environment(AppModel.self) private var app
    @State private var busy: PlaceKind? = nil
    @State private var note: String? = nil

    private let addable: [PlaceKind] = [.library, .home, .gym]
    /// iOS watches at most 20 regions per app. Stay well below.
    private let maxPlaces = 12

    var body: some View {
        let places = app.settings.value.places
        VStack(alignment: .leading, spacing: 12) {
            ForEach(places) { place in
                savedRow(place)
            }
            if places.isEmpty {
                Text("Nothing saved yet.")
                    .font(.ui(14))
                    .foregroundStyle(Theme.textFaint)
            }

            SectionLabel("Add the place you are at now")
                .padding(.top, 6)
            HStack(spacing: 8) {
                ForEach(addable) { kind in
                    addButton(kind, places: places)
                }
            }
            Text("Go there, then tap what it is. Each library is saved on its own, so tap Library once in the first and once in the second.")
                .font(.ui(13))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(.ui(13))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortName(_ kind: PlaceKind) -> String {
        kind == .uni ? "Uni" : kind.defaultName
    }

    private func savedRow(_ place: FocusPlace) -> some View {
        let isHere = app.power.insidePlaceIDs.contains(place.id.uuidString)
        return HStack(spacing: 14) {
            Image(systemName: place.kind.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.mint)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.05), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                TextField(place.kind.defaultName, text: nameBinding(place))
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Theme.text)
                    .submitLabel(.done)
                Text(isHere
                     ? "\(shortName(place.kind)) · you are here"
                     : "\(shortName(place.kind)) · 120 m around the spot")
                    .font(.ui(13))
                    .foregroundStyle(isHere ? Theme.mint : Theme.textDim)
            }
            Spacer(minLength: 0)
            Button("Remove") {
                app.savePlaces(app.settings.value.places.filter { $0.id != place.id })
            }
            .font(.ui(13, .semibold))
            .foregroundStyle(Theme.textDim)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func nameBinding(_ place: FocusPlace) -> Binding<String> {
        Binding(
            get: {
                let current = app.settings.value.places.first(where: { $0.id == place.id })
                return current?.name ?? place.name
            },
            set: { app.renamePlace(id: place.id, to: $0) }
        )
    }

    private func addButton(_ kind: PlaceKind, places: [FocusPlace]) -> some View {
        let taken = !kind.allowsSeveral && places.contains(where: { $0.kind == kind })
        return Button {
            capture(kind)
        } label: {
            VStack(spacing: 6) {
                if busy == kind {
                    ProgressView()
                        .tint(Theme.mint)
                        .frame(height: 18)
                } else {
                    Image(systemName: taken ? "checkmark" : kind.icon)
                        .font(.system(size: 15, weight: .medium))
                        .frame(height: 18)
                }
                Text(shortName(kind))
                    .font(.ui(12, .semibold))
            }
            .foregroundStyle(taken ? Theme.textFaint : Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .disabled(taken || busy != nil)
    }

    private func capture(_ kind: PlaceKind) {
        note = nil
        guard app.power.hasAnyAccess else {
            app.power.requestAccess()
            note = "Allow location access in the prompt, then tap again."
            return
        }
        guard app.settings.value.places.count < maxPlaces else {
            note = "That is the most places the app can watch. Remove one first."
            return
        }
        busy = kind
        app.power.currentLocation { location in
            busy = nil
            guard let location else {
                note = "Could not get a location fix. Try again near a window."
                return
            }
            var places = app.settings.value.places
            let clash = places.first(where: { (saved: FocusPlace) -> Bool in
                let center = CLLocation(latitude: saved.latitude, longitude: saved.longitude)
                return location.distance(from: center) < max(saved.radius, 80)
            })
            if let clash {
                note = "This spot is already covered by \"\(clash.displayName)\". Remove that one first if it is wrong."
                return
            }
            let sameKind = places.filter { $0.kind == kind }.count
            let name = sameKind == 0 ? kind.defaultName : "\(kind.defaultName) \(sameKind + 1)"
            places.append(FocusPlace(
                name: name,
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
            eyebrow: "Step 2 of 4",
            title: "Where do you spend your day?",
            subtitle: "Save a place while you are there: your home and every library you use. The coach checks your location against them, so it knows what fits where. The floor exercises are only offered at home. You can add places later in your profile."
        ) {
            PlacesEditor()
        }
    }
}

// MARK: 3. Permissions

private struct PermissionsStep: View {
    @Environment(AppModel.self) private var app
    @State private var notificationsOn = false

    var body: some View {
        let motionOn = app.headphones.authorization == .authorized
        let locationOn = app.power.hasAlwaysAccess
        StepPage(
            eyebrow: "Step 3 of 4",
            title: "Four permissions, each for one reason",
            subtitle: "Nothing leaves your phone. There is no camera and no account."
        ) {
            permissionRow(
                icon: "calendar",
                title: "Calendar",
                detail: "Reads your iPhone calendar for entries titled \"lernen bib\", \"lernen zuhause\" and the gym. Everything else is ignored. Read only.",
                isOn: app.calendar.hasAccess,
                actionTitle: "Allow"
            ) {
                Task { await app.calendar.requestAccess() }
            }
            permissionRow(
                icon: "location.fill",
                title: "Location · Always",
                detail: "Checks which of your saved places you are at, because the calendar is not always right. Asked in two steps by iOS.",
                isOn: locationOn,
                actionTitle: app.power.hasAnyAccess ? "Upgrade" : "Allow"
            ) {
                app.power.requestAccess()
            }
            permissionRow(
                icon: "bell.fill",
                title: "Notifications",
                detail: "Carries the check-ins. In reminders-only mode they are all there is.",
                isOn: notificationsOn,
                actionTitle: "Allow"
            ) {
                Task { notificationsOn = await Notifier.requestAuthorization() }
            }
            permissionRow(
                icon: "airpodspro",
                title: "Motion & Fitness",
                detail: "Reads the motion sensors in your AirPods. Only needed for posture tracking.",
                isOn: motionOn,
                actionTitle: "Allow"
            ) {
                app.headphones.requestAuthorization()
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
