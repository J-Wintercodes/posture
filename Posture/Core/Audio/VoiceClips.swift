import Foundation

/// Theo's recorded voice: one small audio file per sentence in
/// Posture/Sounds/Voice, made offline with Piper by
/// tools/voice/make_voice.py. Sounds far more natural than the iOS voice.
///
/// A text is cut into sentences, and each sentence is found by a hash of its
/// words. Only when every sentence of a text has a file is the recording
/// used; otherwise the whole text goes to the iOS voice, so Theo never
/// switches voice in the middle of a check-in.
enum VoiceClips {
    /// The files to play one after the other, or nil when one is missing.
    static func files(for text: String, language: CoachLanguage) -> [URL]? {
        let sentences = sentences(of: text)
        guard !sentences.isEmpty else { return nil }
        var urls: [URL] = []
        for sentence in sentences {
            guard let url = Bundle.main.url(forResource: clipName(sentence, language: language), withExtension: "m4a") else {
                return nil
            }
            urls.append(url)
        }
        return urls
    }

    /// Cut after ".", "!" or "?" when a space follows. Must match
    /// `chunks` in make_voice.py.
    static func sentences(of text: String) -> [String] {
        let words = normalized(text)
        var result: [String] = []
        var current = ""
        var previous: Character?
        for character in words {
            if character == " ", let previous, ".!?".contains(previous) {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// "v_de_<FNV-1a 64 of "de|<sentence>">". Must match `clip_name` in
    /// make_voice.py.
    static func clipName(_ sentence: String, language: CoachLanguage) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(language.rawValue)|\(normalized(sentence))".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return "v_\(language.rawValue)_" + String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// Single spaces, composed umlauts.
    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping
    }
}
