import SwiftUI

/// The evening question: any pain today, and how much? One tap on a number
/// from 0 to 10.
struct PainCheckSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let prompt: PainPrompt

    @State private var picked: Int? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionLabel("Before bed", color: Theme.mint)
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
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Any pain today?")
                    .font(.serif(32))
                    .foregroundStyle(Theme.text)
                Text("0 is none, 10 is the worst you can imagine. Back, neck, wherever it bothered you.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0...10, id: \.self) { level in
                    levelButton(level)
                }
            }

            Text(summary)
                .font(.ui(14))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .top)

            Spacer(minLength: 0)

            PillButton(title: "Save", icon: "checkmark") {
                if let picked {
                    app.logPain(picked, dayKey: prompt.dayKey)
                }
                dismiss()
            }
            .disabled(picked == nil)
            .opacity(picked == nil ? 0.4 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear {
            picked = app.log.pain[prompt.dayKey]
        }
    }

    private var summary: String {
        guard let picked else { return "Tap a number." }
        var line = "\(picked) · \(PainScale.label(picked, language: .en))"
        if picked >= PainScale.gentleFrom {
            line += ". Tomorrow I only suggest gentle routines: mobility and breathing, no strength."
        }
        return line
    }

    private func levelButton(_ level: Int) -> some View {
        let isPicked = picked == level
        let tint = PainColor.color(level)
        return Button {
            picked = level
        } label: {
            Text("\(level)")
                .font(.ui(17, .semibold))
                .monospacedDigit()
                .foregroundStyle(isPicked ? .black : Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(isPicked ? tint : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isPicked ? Color.clear : tint.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Pain \(level) of 10")
    }
}
