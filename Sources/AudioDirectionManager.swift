import Foundation
import AVFoundation
import UIKit

/// Manages directional audio cues for navigation
class AudioDirectionManager: ObservableObject {

    // MARK: - Properties
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var mixer: AVAudioMixerNode
    private var audioFormat: AVAudioFormat

    // Audio buffers for different sounds
    private var leftBeepBuffer: AVAudioPCMBuffer?
    private var rightBeepBuffers: (high: AVAudioPCMBuffer?, low: AVAudioPCMBuffer?)
    private var warningBuffer: AVAudioPCMBuffer?
    private var clearPathBuffer: AVAudioPCMBuffer?

    // Control properties
    private var lastPlayedDirection: NavigationDirection?
    private var lastPlayedTime = Date()
    private let minimumPlayInterval: TimeInterval = 1.0 // Minimum time between audio cues

    @Published var audioEnabled = true
    @Published var volume: Float = 0.7

    enum NavigationDirection {
        case left
        case right
        case straight
        case blocked
    }

    // MARK: - Initialization
    init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        mixer = audioEngine.mainMixerNode
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

        setupAudioEngine()
        generateAudioBuffers()
        configureAudioSession()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: mixer, format: audioFormat)

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Audio Buffer Generation

    private func generateAudioBuffers() {
        // Generate different tones for navigation
        leftBeepBuffer = createToneBuffer(frequency: 440, duration: 0.15) // A4 note, single beep
        rightBeepBuffers.high = createToneBuffer(frequency: 523, duration: 0.15) // C5 note
        rightBeepBuffers.low = createToneBuffer(frequency: 349, duration: 0.15) // F4 note
        warningBuffer = createToneBuffer(frequency: 880, duration: 0.3, isWarning: true) // A5, urgent
        clearPathBuffer = createChimeBuffer() // Pleasant chime for clear path
    }

    /// Create a tone buffer with specified frequency and duration
    private func createToneBuffer(frequency: Float, duration: TimeInterval, isWarning: Bool = false) -> AVAudioPCMBuffer? {
        let sampleRate = audioFormat.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        let channelCount = Int(audioFormat.channelCount)

        // Generate sine wave
        let angularFrequency = Float(2.0 * Double.pi * Double(frequency))
        let fadeInDuration = Float(duration * 0.1) // 10% fade in
        let fadeOutDuration = Float(duration * 0.2) // 20% fade out

        for frame in 0..<frameCount {
            let time = Float(frame) / Float(sampleRate)
            var amplitude: Float = 0.3

            // Apply envelope (fade in/out)
            if time < fadeInDuration {
                amplitude *= time / fadeInDuration
            } else if time > Float(duration) - fadeOutDuration {
                let fadeTime = time - (Float(duration) - fadeOutDuration)
                amplitude *= 1.0 - (fadeTime / fadeOutDuration)
            }

            // Add tremolo effect for warning sounds
            if isWarning {
                amplitude *= (1.0 + 0.3 * sinf(20 * time)) // Tremolo at 20Hz
            }

            let sample = amplitude * sinf(angularFrequency * time)

            // Write to all channels
            for channel in 0..<channelCount {
                buffer.floatChannelData?[channel][Int(frame)] = sample
            }
        }

        return buffer
    }

    /// Create a pleasant chime sound for clear path indication
    private func createChimeBuffer() -> AVAudioPCMBuffer? {
        let duration: TimeInterval = 0.5
        let sampleRate = audioFormat.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        let channelCount = Int(audioFormat.channelCount)

        // Create a pleasant two-tone chime (C5 and E5)
        let frequencies: [Float] = [523.25, 659.25] // C5 and E5

        for frame in 0..<frameCount {
            let time = Float(frame) / Float(sampleRate)
            var sample: Float = 0

            for (index, frequency) in frequencies.enumerated() {
                let delay = Float(index) * 0.1 // Slight delay between notes
                if time > delay {
                    let adjustedTime = time - delay
                    let angularFrequency = Float(2.0 * Double.pi * Double(frequency))
                    let amplitude = 0.2 * expf(-3.0 * adjustedTime) // Exponential decay
                    sample += amplitude * sinf(angularFrequency * adjustedTime)
                }
            }

            // Write to all channels
            for channel in 0..<channelCount {
                buffer.floatChannelData?[channel][Int(frame)] = sample
            }
        }

        return buffer
    }

    // MARK: - Public Methods

    /// Play directional audio cue based on navigation direction
    /// - Parameters:
    ///   - direction: Navigation direction
    ///   - distance: Distance to obstacle (affects volume)
    ///   - forcePlay: Override minimum interval check
    func playDirectionalCue(direction: NavigationDirection, distance: Float, forcePlay: Bool = false) {
        guard audioEnabled else { return }

        // Check minimum interval unless forced
        if !forcePlay && Date().timeIntervalSince(lastPlayedTime) < minimumPlayInterval {
            return
        }

        // Calculate volume based on distance (closer = louder)
        let distanceVolume = max(0.3, min(1.0, (2.0 - distance) / 2.0))
        let finalVolume = volume * distanceVolume

        // Apply stereo panning based on direction
        var pan: Float = 0.0 // Center by default

        switch direction {
        case .left:
            playLeftCue(volume: finalVolume)
            pan = -0.5 // Pan slightly to left
        case .right:
            playRightCue(volume: finalVolume)
            pan = 0.5 // Pan slightly to right
        case .blocked:
            playWarningCue(volume: finalVolume)
            pan = 0.0 // Center for warnings
        case .straight:
            // No audio for straight ahead
            return
        }

        // Apply panning
        setPanning(pan)

        lastPlayedDirection = direction
        lastPlayedTime = Date()
    }

    /// Play single beep for left turn
    private func playLeftCue(volume: Float) {
        guard let buffer = leftBeepBuffer else { return }
        playBuffer(buffer, volume: volume)
    }

    /// Play two beeps for right turn
    private func playRightCue(volume: Float) {
        guard let highBuffer = rightBeepBuffers.high,
              let lowBuffer = rightBeepBuffers.low else { return }

        // Play high-low sequence
        playBuffer(highBuffer, volume: volume)

        // Schedule second beep
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.playBuffer(lowBuffer, volume: volume)
        }
    }

    /// Play warning sound for blocked path
    private func playWarningCue(volume: Float) {
        guard let buffer = warningBuffer else { return }
        playBuffer(buffer, volume: volume * 1.2) // Slightly louder for warnings
    }

    /// Play clear path chime
    func playClearPathSound() {
        guard audioEnabled, let buffer = clearPathBuffer else { return }
        playBuffer(buffer, volume: volume * 0.6) // Softer for pleasant feedback
    }

    /// Play audio buffer
    private func playBuffer(_ buffer: AVAudioPCMBuffer, volume: Float) {
        playerNode.stop()
        playerNode.volume = volume

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) {
            // Buffer completed playing
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// Set stereo panning (-1.0 = full left, 0 = center, 1.0 = full right)
    private func setPanning(_ pan: Float) {
        playerNode.pan = max(-1.0, min(1.0, pan))
    }

    /// Play test sound for each direction
    func playTestSound(for direction: NavigationDirection) {
        playDirectionalCue(direction: direction, distance: 1.0, forcePlay: true)
    }

    /// Stop all audio
    func stopAll() {
        playerNode.stop()
        audioEngine.pause()
    }

    /// Resume audio engine
    func resume() {
        do {
            try audioEngine.start()
        } catch {
            print("Failed to resume audio engine: \(error)")
        }
    }

    deinit {
        stopAll()
        audioEngine.stop()
    }
}