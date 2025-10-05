import Foundation
import AVFoundation

/// Simple voice guidance system for key navigation moments
class VoiceGuidance: ObservableObject {

    // MARK: - Properties
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isEnabled = true
    @Published var voiceRate: Float = 0.5  // Normal speaking rate
    @Published var voicePitch: Float = 1.0  // Normal pitch

    // Timing control
    private var lastSpeechTime = Date()
    private let minimumInterval: TimeInterval = 2.0  // Don't speak more than once every 2 seconds
    private var currentUtterance: AVSpeechUtterance?

    // MARK: - Initialization
    init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session for speech: \(error)")
        }
    }

    // MARK: - Voice Commands

    /// Announce obstacle with direction
    func announceObstacle(direction: Direction, distance: Float) {
        guard isEnabled, shouldSpeak() else { return }

        var message = ""

        // Only announce if obstacle is close enough to matter
        if distance > 2.0 {
            return  // Don't announce far obstacles
        }

        switch direction {
        case .left:
            message = distance < 1.0 ? "Object left. Turn right." : "Object on left"
        case .right:
            message = distance < 1.0 ? "Object right. Turn left." : "Object on right"
        case .center:
            if distance < 0.5 {
                message = "Stop. Object ahead."
            } else if distance < 1.0 {
                message = "Caution. Object close."
            } else {
                message = "Object ahead"
            }
        case .multiple:
            message = "Multiple objects. Proceed carefully."
        }

        speak(message, priority: distance < 1.0 ? .high : .normal)
    }

    /// Announce clear path
    func announceClear() {
        guard isEnabled, shouldSpeak() else { return }
        speak("Path clear", priority: .low)
    }

    /// Announce turn suggestion
    func announceTurn(direction: TurnDirection) {
        guard isEnabled, shouldSpeak() else { return }

        let message: String
        switch direction {
        case .left:
            message = "Turn left"
        case .right:
            message = "Turn right"
        case .slightLeft:
            message = "Bear left"
        case .slightRight:
            message = "Bear right"
        case .around:
            message = "Turn around"
        }

        speak(message, priority: .normal)
    }

    /// Emergency stop announcement
    func announceStop() {
        guard isEnabled else { return }
        // Always announce stops regardless of timing
        speak("Stop!", priority: .immediate)
    }

    /// Distance announcement
    func announceDistance(_ distance: Float) {
        guard isEnabled, shouldSpeak() else { return }

        let message: String

        if distance < 1.0 {
            message = String(format: "%.1f meters", distance)
        } else {
            message = String(format: "%d meters", Int(distance))
        }

        speak(message, priority: .low)
    }

    // MARK: - Types

    enum Direction {
        case left
        case right
        case center
        case multiple
    }

    enum TurnDirection {
        case left
        case right
        case slightLeft
        case slightRight
        case around
    }

    enum Priority {
        case immediate  // Bypass all timing restrictions
        case high       // Important but respect minimum timing
        case normal     // Standard announcements
        case low        // Optional announcements
    }

    // MARK: - Speech Control

    private func speak(_ text: String, priority: Priority) {
        // Check priority and timing
        switch priority {
        case .immediate:
            // Always speak immediately
            stopCurrentSpeech()
        case .high:
            if !shouldSpeak(interval: 1.0) { return }
            stopCurrentSpeech()
        case .normal:
            if !shouldSpeak() { return }
        case .low:
            if !shouldSpeak(interval: 3.0) { return }
            if synthesizer.isSpeaking { return }  // Don't interrupt for low priority
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = voiceRate
        utterance.pitchMultiplier = voicePitch
        utterance.volume = 0.9

        // Use a clear voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        currentUtterance = utterance
        synthesizer.speak(utterance)
        lastSpeechTime = Date()
    }

    private func shouldSpeak(interval: TimeInterval = 2.0) -> Bool {
        return Date().timeIntervalSince(lastSpeechTime) >= interval
    }

    private func stopCurrentSpeech() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Stop all speech
    func stopAll() {
        stopCurrentSpeech()
    }

    /// Test voice with sample announcement
    func testVoice() {
        speak("Voice guidance activated. Object detected ahead at 1.5 meters.", priority: .immediate)
    }

    deinit {
        stopAll()
    }
}