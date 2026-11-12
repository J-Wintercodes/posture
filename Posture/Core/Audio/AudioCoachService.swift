import AVFoundation
import Observation

/// Theo: the audio side of the coach, and the thing that keeps the session
/// alive while the iPhone is locked.
///
/// A running `AVAudioEngine` with a looping silent buffer holds the app in
/// the background (UIBackgroundModes: audio). The session mixes with other
/// audio, so the user's music keeps playing and the cues land on top of it.
/// Chimes are synthesised at runtime, so there are no audio assets to ship.
@MainActor
@Observable
final class AudioCoachService: NSObject {
    private(set) var isActive = false

    @ObservationIgnored var mode: FeedbackMode = .voice
    @ObservationIgnored var language: CoachLanguage = .en
    /// Voice picked in the profile. Nil means "best installed voice".
    @ObservationIgnored var voiceID: String?

    @ObservationIgnored private var voice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var voiceKey: String?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let tones = AVAudioPlayerNode()
    @ObservationIgnored private let keepAlive = AVAudioPlayerNode()
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
    @ObservationIgnored private var isWired = false
    @ObservationIgnored private var variant = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // MARK: Lifecycle

    func beginSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        // The silent keep-alive needs no low latency. A long buffer means the
        // audio thread wakes about ten times a second instead of a hundred,
        // which is most of what this engine costs while the phone is locked.
        // iOS treats it as a wish and may pick a shorter one.
        try? session.setPreferredIOBufferDuration(0.1)
        try session.setActive(true)
        wireIfNeeded()
        try startEngine()
        isActive = true

        if observers.isEmpty {
            let center = NotificationCenter.default
            let names: [Notification.Name] = [AVAudioSession.interruptionNotification, .AVAudioEngineConfigurationChange]
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.recover() }
                }
                observers.append(token)
            }
        }
    }

    func endSession() {
        guard isActive else { return }
        isActive = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        // Let the closing chime ring out before the engine goes down.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !self.isActive else { return }
            self.speech.stopSpeaking(at: .word)
            self.keepAlive.stop()
            self.tones.stop()
            self.engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func wireIfNeeded() {
        guard !isWired, let format else { return }
        engine.attach(tones)
        engine.attach(keepAlive)
        engine.connect(tones, to: engine.mainMixerNode, format: format)
        engine.connect(keepAlive, to: engine.mainMixerNode, format: format)
        isWired = true
    }

    private func startEngine() throws {
        guard isWired, let format else { return }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) {
            silence.frameLength = 44_100
            if let channels = silence.floatChannelData {
                for c in 0..<Int(format.channelCount) {
                    for i in 0..<Int(silence.frameLength) { channels[c][i] = 0 }
                }
            }
            keepAlive.stop()
            keepAlive.scheduleBuffer(silence, at: nil, options: .loops)
            keepAlive.play()
        }
        tones.play()
    }

    /// After a phone call or a route change (AirPods out, AirPods in) the
    /// engine stops. Bring it back so the session survives.
    private func recover() {
        guard isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? startEngine()
    }

    /// Called once a second while a session runs. The silent engine is the
    /// only thing that keeps the app awake behind the lock screen, so if it
    /// ever is not running (the audio session could not be opened at the
    /// start, or an interruption ended without a notification) it is brought
    /// back here instead of the session quietly dying.
    func ensureRunning() {
        if !isActive {
            try? beginSession()
        } else if !engine.isRunning {
            recover()
        }
    }

    // MARK: Delivery

    func deliver(_ cue: CoachCue) {
        variant += 1
        // A check-in always leaves a notification as well, whatever the
        // feedback mode: it says what is needed (a chime cannot) and tapping
        // it on the Lock Screen opens the routine.
        if case .checkIn(_, let title, let body, let routineID) = cue {
            Notifier.post(title: title, body: body, id: Notifier.liveCheckInID, sound: false, routineID: routineID)
            if mode == .silent { return }
        }
        switch mode {
        case .silent:
            if let note = CoachScript.notification(for: cue, language: language) {
                Notifier.post(title: note.title, body: note.body, sound: false)
            }
        case .chime:
            playChime(for: cue)
        case .voice:
            playChime(for: cue)
            if speaks(cue), let line = CoachScript.line(for: cue, language: language, variant: variant) {
                say(line)
            }
        }
    }

    /// Posture is never an instruction, only a beep: a small low one when it
    /// turns bad (and for the reminders while it stays bad), a brighter one
    /// when it is good again. Theo keeps his words for check-ins and for the
    /// start and end of a session.
    private func speaks(_ cue: CoachCue) -> Bool {
        if case .nudge = cue { return false }
        return true
    }

    /// Plays the two posture beeps one after the other, so they can be
    /// heard without having to slouch first. Needs a running session.
    func playTestTones() {
        playChime(for: .nudge(.slouch, level: 0))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.playChime(for: .recovered)
        }
    }

    private func say(_ text: String, delay: TimeInterval = 0.45) {
        let voice = currentVoice()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // The natural voices are tuned for the default rate. The compact
        // fallback sounds less clipped when it is slowed down a little.
        let isNatural = (voice?.quality ?? .default) != .default
        utterance.rate = isNatural ? 0.49 : 0.46
        utterance.volume = 0.9
        utterance.preUtteranceDelay = delay
        speech.speak(utterance)
    }

    /// Looking through the installed voices is not free, so the result is
    /// kept until the language or the chosen voice changes.
    private func currentVoice() -> AVSpeechSynthesisVoice? {
        let key = "\(language.rawValue)|\(voiceID ?? "auto")"
        if key != voiceKey {
            voiceKey = key
            voice = CoachVoice.resolve(id: voiceID, language: language)
        }
        return voice
    }

    /// Speaks a sample line with the current voice, for the profile screen.
    /// Works without a running session.
    func preview() {
        if !isActive {
            // Without the playback category the ring switch would mute it.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
        // A voice may have been downloaded since the last look.
        voiceKey = nil
        speech.stopSpeaking(at: .immediate)
        say(CoachScript.preview(language: language), delay: 0)
    }

    /// Reads a routine step aloud. Works without a running session, so the
    /// floor exercises can be followed without looking at the phone. Only in
    /// voice mode.
    func speak(_ text: String) {
        guard mode == .voice else { return }
        if !isActive {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
        speech.stopSpeaking(at: .immediate)
        say(text, delay: 0.15)
    }

    /// Stops reading and, when no session is running, lets go of the audio
    /// session again so nothing stays powered for nothing.
    func stopSpeaking() {
        speech.stopSpeaking(at: .immediate)
        if !isActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    // MARK: Chimes

    private struct Note {
        var frequency: Double
        var at: Double
        var length: Double

        init(_ frequency: Double, _ at: Double, _ length: Double) {
            self.frequency = frequency
            self.at = at
            self.length = length
        }
    }

    private func playChime(for cue: CoachCue) {
        guard isWired, engine.isRunning else { return }
        let notes: [Note]
        var gain = 0.2
        switch cue {
        case .sessionStarted, .resumed:
            notes = [Note(523.25, 0, 0.5), Note(659.25, 0.14, 0.5), Note(783.99, 0.28, 0.9)]
        case .sessionEnded, .pausedLowPower:
            notes = [Note(783.99, 0, 0.5), Note(659.25, 0.14, 0.5), Note(523.25, 0.28, 0.9)]
        case .nudge(_, let level):
            // Posture turned bad: one small low beep (G4). A reminder while
            // it stays bad is the same beep twice. Loud enough to be heard
            // over music: it is the only signal.
            if level == 0 {
                notes = [Note(392.00, 0, 0.18)]
            } else {
                notes = [Note(392.00, 0, 0.16), Note(392.00, 0.22, 0.18)]
            }
            gain = 0.32
        case .recovered:
            // Posture is good again: two quick notes going up a fifth
            // (E5 to B5). Brighter and friendlier than the low beep.
            notes = [Note(659.25, 0, 0.12), Note(987.77, 0.10, 0.26)]
            gain = 0.22
        case .uprightSet:
            notes = [Note(659.25, 0, 0.35), Note(880, 0.12, 0.7)]
        case .checkIn:
            notes = [Note(523.25, 0, 0.6), Note(392, 0.25, 0.6), Note(523.25, 0.5, 1.0)]
        }
        if let buffer = render(notes, gain: gain) {
            tones.scheduleBuffer(buffer, at: nil, options: [])
            if !tones.isPlaying { tones.play() }
        }
    }

    /// Soft bell: a sine with two quiet overtones and an exponential decay.
    private func render(_ notes: [Note], gain: Double = 0.2) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let sampleRate = format.sampleRate
        let total = (notes.map { $0.at + $0.length }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        let count = Int(frames)
        var mono = [Float](repeating: 0, count: count)
        for note in notes {
            let start = Int(note.at * sampleRate)
            let length = Int(note.length * sampleRate)
            for i in 0..<length {
                let index = start + i
                if index >= count { break }
                let t = Double(i) / sampleRate
                let envelope = min(t / 0.01, 1) * exp(-4.5 * t / note.length)
                let w = 2 * Double.pi * note.frequency * t
                let wave = sin(w) + 0.28 * sin(2 * w) + 0.08 * sin(3 * w)
                mono[index] += Float(gain * envelope * wave)
            }
        }
        for c in 0..<Int(format.channelCount) {
            for i in 0..<count { channels[c][i] = mono[i] }
        }
        return buffer
    }
}
