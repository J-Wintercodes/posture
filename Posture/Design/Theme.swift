import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x050608)
    static let card = Color(hex: 0x121418)
    static let cardRaised = Color(hex: 0x1A1D22)
    static let stroke = Color.white.opacity(0.07)

    static let mint = Color(hex: 0x4FD1C5)
    static let teal = Color(hex: 0x38B2AC)
    static let amber = Color(hex: 0xF6AD55)
    static let ember = Color(hex: 0xED8936)
    static let red = Color(hex: 0xE53E3E)

    static let text = Color.white.opacity(0.94)
    static let textDim = Color.white.opacity(0.58)
    static let textFaint = Color.white.opacity(0.32)

    static func zone(_ zone: PostureZone) -> Color {
        switch zone {
        case .aligned: return mint
        case .drifting: return amber
        case .slouching: return ember
        }
    }

    static func score(_ score: Int) -> Color {
        if score >= 80 { return mint }
        if score >= 62 { return amber }
        return ember
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    /// New York: headlines, greetings and everything the coach says.
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        let font = Font.system(size: size, weight: .regular, design: .serif)
        return italic ? font.italic() : font
    }

    /// SF Pro: labels, metrics, numbers.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

enum Fmt {
    /// "14m", "1h 45m"
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 60 { return "\(minutes)m" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
    }

    /// "00:06", "1:02:45"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "09:02"
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "THURSDAY, 12. NOV"
    static func headerDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, d. MMM"
        return f.string(from: date).uppercased()
    }

    static func weekdayLetter(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEEE"
        return f.string(from: date)
    }

    static func weekdayShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    static func dateToMinutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
