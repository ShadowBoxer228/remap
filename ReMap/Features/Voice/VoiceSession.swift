import AVFoundation
import Speech
import Observation

/// On-device voice I/O for the coach: live mic level, speech-to-text and text-to-speech.
/// The "brain" stays the coach; this only turns talking into replies and replies into speech.
@Observable
final class VoiceSession: NSObject {
    enum State: Equatable {
        case idle, listening, thinking, speaking
        case unavailable(String)
    }

    var state: State = .idle
    /// Smoothed 0…1 loudness — drives the orb.
    var level: Double = 0
    var transcript = ""

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var lifecycle = UUID()
    @ObservationIgnored private var listeningID = UUID()
    @ObservationIgnored private var hasTap = false
    @ObservationIgnored private var activeUtteranceID: ObjectIdentifier?
    @ObservationIgnored private var speakingPulse: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Permissions

    func ensurePermissions() async -> Bool {
        let id = lifecycle
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard lifecycle == id, !Task.isCancelled else { return false }
        guard speech == .authorized else {
            state = .unavailable(String(localized: "Speech recognition is off. Enable it in Settings → ReMap, or type your answer."))
            return false
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard lifecycle == id, !Task.isCancelled else { return false }
        guard micAllowed else {
            state = .unavailable(String(localized: "Microphone access is off. Enable it in Settings → ReMap, or type your answer."))
            return false
        }
        return true
    }

    // MARK: Listening

    func startListening() async {
        stopListening()
        let id = lifecycle
        let turnID = listeningID
        stopSpeaking()
        guard await ensurePermissions(), lifecycle == id, listeningID == turnID, !Task.isCancelled else { return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable(String(localized: "Speech recognition isn't available right now. Type your answer instead."))
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
            self.request = request
            transcript = ""

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                state = .unavailable(String(localized: "No microphone input is available. Type your answer instead."))
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format,
                             block: Self.makeTapBlock(request: request) { [weak self] rms in
                guard let self, self.listeningID == turnID, self.state == .listening else { return }
                self.ingest(level: rms)
            })
            hasTap = true
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] text, isFinal, failed in
                guard let self, self.listeningID == turnID, self.state == .listening else { return }
                if failed {
                    self.stopListening()
                    self.state = .unavailable(String(localized: "Speech recognition stopped. Close voice mode and try again, or type your answer."))
                    return
                }
                self.transcript = text
                if isFinal { self.level = 0 }
            })
            state = .listening
        } catch {
            stopListening()
            state = .unavailable(String(localized: "Microphone audio is unavailable. Close voice mode and try again, or type your answer."))
        }
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stopListening() -> String {
        listeningID = UUID()
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
        if state == .listening { state = .idle }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ingest(level rms: Float) {
        // Map roughly −50…−10 dBFS to 0…1, then smooth so the orb breathes instead of flickering.
        let db = 20 * log10(max(Double(rms), 0.000_01))
        let target = min(max((db + 50) / 40, 0), 1)
        level = level * 0.75 + target * 0.25
    }

    /// Built outside the main actor: the audio engine calls it on its realtime thread.
    private nonisolated static func makeTapBlock(request: SFSpeechAudioBufferRecognitionRequest,
                                                 onLevel: @escaping @MainActor (Float) -> Void) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request
        return { buffer, _ in
            request.append(buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += data[i] * data[i] }
            let rms = (sum / Float(count)).squareRoot()
            Task { @MainActor in onLevel(rms) }
        }
    }

    private nonisolated static func makeResultHandler(_ onResult: @escaping @MainActor (String, Bool, Bool) -> Void)
        -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            guard let result else {
                if error != nil { Task { @MainActor in onResult("", false, true) } }
                return
            }
            let text = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            Task { @MainActor in onResult(text, isFinal, false) }
        }
    }

    // MARK: Speaking

    func speak(_ text: String) {
        let clean = text.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "“", with: "").replacingOccurrences(of: "”", with: "")
        guard !clean.isEmpty else { return }
        if state == .listening { stopListening() }
        stopSpeaking()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.bestVoice
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.02
        utterance.postUtteranceDelay = 0.1
        activeUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
        state = .speaking
        // TTS doesn't expose loudness; give the orb a speech-like envelope instead.
        speakingPulse?.cancel()
        speakingPulse = Task { [weak self] in
            var t = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                t += 0.06
                guard let self, self.state == .speaking else { return }
                let syllables = abs(sin(t * 9.3)) * 0.6 + abs(sin(t * 3.1)) * 0.4
                self.level = self.level * 0.6 + syllables * 0.75 * 0.4
            }
        }
    }

    func stopSpeaking() {
        activeUtteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        speakingPulse?.cancel()
        if state == .speaking { state = .idle }
        level = 0
    }

    func shutDown() {
        lifecycle = UUID()
        stopListening()
        stopSpeaking()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static var bestVoice: AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return english.first { $0.quality == .premium } ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    fileprivate func didFinishSpeaking(id: ObjectIdentifier) {
        guard activeUtteranceID == id else { return }
        activeUtteranceID = nil
        speakingPulse?.cancel()
        if state == .speaking { state = .idle }
        level = 0
    }
}

extension VoiceSession: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didFinishSpeaking(id: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didFinishSpeaking(id: id) }
    }
}
