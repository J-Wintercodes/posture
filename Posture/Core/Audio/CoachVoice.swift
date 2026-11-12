import AVFoundation

/// Picks the voice Theo speaks with.
///
/// `AVSpeechSynthesisVoice(language:)` always hands back the small "compact"
/// voice, which is the robotic one. iOS also has Enhanced and Premium voices
/// that sound far more natural, but they have to be downloaded once in the
/// Settings app. This takes the best voice that is actually installed and
/// leaves out the novelty and Eloquence voices, which are worse than compact.
enum CoachVoice {
    struct Option: Identifiable, Hashable {
        /// `AVSpeechSynthesisVoice.identifier`
        let id: String
        let label: String
    }

    /// Usable voices for the language, best first.
    static func installed(for language: CoachLanguage) -> [AVSpeechSynthesisVoice] {
        let systemDefault = AVSpeechSynthesisVoice(language: language.voiceCode)?.identifier
        func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
            var value = voice.quality.rawValue * 100
            if voice.language == language.voiceCode { value += 10 }
            if voice.identifier == systemDefault { value += 1 }
            return value
        }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.rawValue) && isSuitable($0) }
            .sorted { a, b in
                let ra = rank(a)
                let rb = rank(b)
                return ra != rb ? ra > rb : a.name < b.name
            }
    }

    static func options(for language: CoachLanguage) -> [Option] {
        installed(for: language).map { Option(id: $0.identifier, label: label($0)) }
    }

    /// The chosen voice if it is still installed and fits the language,
    /// otherwise the best one there is.
    static func resolve(id: String?, language: CoachLanguage) -> AVSpeechSynthesisVoice? {
        if let id, let voice = AVSpeechSynthesisVoice(identifier: id), voice.language.hasPrefix(language.rawValue) {
            return voice
        }
        return installed(for: language).first ?? AVSpeechSynthesisVoice(language: language.voiceCode)
    }

    /// False while only the compact voices are on the device.
    static func hasNaturalVoice(for language: CoachLanguage) -> Bool {
        guard let best = installed(for: language).first else { return false }
        return best.quality != .default
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        // Some iOS versions already put the quality into the name.
        if voice.name.contains("(") { return voice.name }
        switch voice.quality {
        case .premium: return "\(voice.name) (Premium)"
        case .enhanced: return "\(voice.name) (Enhanced)"
        default: return voice.name
        }
    }

    private static func isSuitable(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let id = voice.identifier.lowercased()
        if id.contains("eloquence") || id.contains("speech.synthesis.voice") { return false }
        if voice.voiceTraits.contains(.isNoveltyVoice) { return false }
        return true
    }
}
