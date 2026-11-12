import SwiftUI

/// Uppercase, widely tracked section header: YOUR DAY, THIS WEEK, ...
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.textDim

    init(_ text: String, color: Color = Theme.textDim) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.ui(11, .semibold))
            .tracking(1.8)
            .foregroundStyle(color)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var fill: Color = Theme.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

struct PillButton: View {
    enum Kind {
        case white, dark, danger
    }

    let title: String
    var icon: String?
    var kind: Kind = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .bold))
                }
                Text(title).font(.ui(16, .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private var foreground: Color {
        switch kind {
        case .white: return .black
        case .dark: return Theme.text
        case .danger: return Color(hex: 0xFC8181)
        }
    }

    private var background: Color {
        switch kind {
        case .white: return .white
        case .dark: return Theme.cardRaised
        case .danger: return Theme.red.opacity(0.10)
        }
    }

    private var border: Color {
        switch kind {
        case .white: return .clear
        case .dark: return Theme.stroke
        case .danger: return Theme.red.opacity(0.55)
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ThinBar: View {
    var value: Double
    var color: Color = Theme.mint

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 3)
    }
}

struct StatusDot: View {
    var color: Color = Theme.mint
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: 5)
    }
}

/// Big number above a small uppercase caption: "11m / GOOD TIME".
struct MetricTile: View {
    let value: String
    let label: String
    var tint: Color = Theme.text

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.ui(22, .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.ui(9.5, .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MetricRow: View {
    /// Pairs of (value, label).
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 30)
                }
                MetricTile(value: items[index].0, label: items[index].1)
            }
        }
    }
}

struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.ui(14, .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.score(score))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.score(score).opacity(0.12), in: Capsule())
    }
}

/// Round profile button with the amber streak flame.
struct ProfileButton: View {
    let streak: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                    )
                    .frame(width: 42, height: 42)
                HStack(spacing: 1) {
                    Image(systemName: "flame.fill").font(.system(size: 8, weight: .bold))
                    if streak > 0 {
                        Text("\(streak)").font(.ui(9, .bold))
                    }
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(Theme.amber, in: Capsule())
                .offset(x: 5, y: 4)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Profile and settings")
    }
}

/// Small date or eyebrow line, a large serif title and the profile button.
struct ScreenHeader: View {
    @Environment(AppModel.self) private var app
    let eyebrow: String
    let title: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(eyebrow)
                Text(title)
                    .font(.serif(38))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            ProfileButton(streak: app.store.streak) { app.showProfile = true }
        }
        .padding(.top, 8)
    }
}

struct SoonBadge: View {
    var body: some View {
        Text("SOON")
            .font(.ui(9, .bold))
            .tracking(1.2)
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}

/// Scroll container shared by the four tabs: dark background and room for
/// the floating tab bar at the bottom.
struct TabScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
    }
}
