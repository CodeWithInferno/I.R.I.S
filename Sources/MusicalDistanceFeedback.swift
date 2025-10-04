import Foundation
import AVFoundation
import UIKit

/// Provides intuitive musical feedback based on obstacle distance
class MusicalDistanceFeedback: ObservableObject {

    // MARK: - Properties
    private var audioEngine: AVAudioEngine
    private var tonePlayer: AVAudioPlayerNode
    private var mixer: AVAudioMixerNode

    // Tone generation
    private var currentFrequency: Float = 440.0
    private var targetFrequency: Float = 440.0
    private var isPlaying = false
    private var updateTimer: Timer?

    // Settings
    @Published var isEnabled = true
    @Published var volume: Float = 0.5
    @Published var usePulsing = true  // Pulse rate increases with proximity

    // Distance to frequency mapping
    private let maxFrequency: Float = 1200.0  // High pitch for very close
    private let minFrequency: Float = 200.0   // Low pitch for far away
    private let silenceThreshold: Float = 3.0  // No sound beyond 3 meters

    // Pulsing parameters
    private var pulseTimer: Timer?
    private var pulseRate: TimeInterval = 1.0

    // MARK: - Initialization
    init() {
        audioEngine = AVAudioEngine()
        tonePlayer = AVAudioPlayerNode()
        mixer = audioEngine.mainMixerNode

        setupAudioEngine()
        setupAudioSession()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func setupAudioEngine() {
        audioEngine.attach(tonePlayer)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        audioEngine.connect(tonePlayer, to: mixer, format: format)

        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Distance-Based Feedback

    /// Update feedback based on obstacle distance and direction
    func updateFeedback(distance: Float, direction: Direction) {
        guard isEnabled else {
            stopFeedback()
            return
        }

        // No sound if obstacle is far away
        if distance > silenceThreshold {
            stopFeedback()
            return
        }

        // Calculate frequency based on distance (inverse relationship)
        // Closer = higher pitch, farther = lower pitch
        let normalizedDistance = (silenceThreshold - distance) / silenceThreshold
        targetFrequency = minFrequency + (maxFrequency - minFrequency) * normalizedDistance

        // Calculate pulse rate (faster when closer)
        if usePulsing {
            // Pulse rate from 0.1s (very close) to 1s (far)
            pulseRate = TimeInterval(0.1 + (1.0 - normalizedDistance) * 0.9)
            startPulsing()
        } else {
            // Continuous tone
            if !isPlaying {
                playTone()
            }
        }

        // Apply stereo panning based on direction
        applyPanning(for: direction)

        // Smooth frequency transition
        smoothlyTransitionFrequency()
    }

    /// Direction of obstacle
    enum Direction {
        case left
        case right
        case center
        case leftCenter
        case rightCenter
    }

    // MARK: - Tone Generation

    private func playTone() {
        guard !isPlaying else { return }
        isPlaying = true

        let sampleRate = 44100.0
        let frameCount = AVAudioFrameCount(sampleRate * 0.5) // 500ms buffer

        guard let buffer = AVAudioPCMBuffer(pcmFormat: tonePlayer.outputFormat(forBus: 0),
                                           frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount
        let channelCount = Int(buffer.format.channelCount)

        // Generate smooth sine wave
        for frame in 0..<frameCount {
            let time = Float(frame) / Float(sampleRate)

            // Interpolate frequency for smooth transitions
            let frequency = currentFrequency
            let amplitude = volume * 0.3

            // Apply envelope for smooth attack/release
            var envelope: Float = 1.0
            let attackTime: Float = 0.05
            let releaseTime: Float = 0.05

            if time < attackTime {
                envelope = time / attackTime
            } else if time > 0.5 - releaseTime {
                envelope = (0.5 - time) / releaseTime
            }

            let sample = amplitude * envelope * sinf(2.0 * Float.pi * frequency * time)

            for channel in 0..<channelCount {
                buffer.floatChannelData?[channel][Int(frame)] = sample
            }
        }

        tonePlayer.scheduleBuffer(buffer, at: nil, options: .loops) {
            // Buffer completed
        }

        tonePlayer.play()
    }

    private func stopTone() {
        isPlaying = false
        tonePlayer.stop()
    }

    // MARK: - Pulsing

    private func startPulsing() {
        stopPulsing()

        // Create pulse pattern
        pulseTimer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.isPlaying {
                self.stopTone()
                // Brief silence between pulses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.playTone()
                }
            } else {
                self.playTone()
            }
        }

        // Start immediately
        playTone()
    }

    private func stopPulsing() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    // MARK: - Stereo Panning

    private func applyPanning(for direction: Direction) {
        var pan: Float = 0.0

        switch direction {
        case .left:
            pan = -0.8  // Strong left
        case .leftCenter:
            pan = -0.4  // Slight left
        case .center:
            pan = 0.0   // Center
        case .rightCenter:
            pan = 0.4   // Slight right
        case .right:
            pan = 0.8   // Strong right
        }

        tonePlayer.pan = pan
    }

    // MARK: - Frequency Smoothing

    private func smoothlyTransitionFrequency() {
        updateTimer?.invalidate()

        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // Smooth interpolation
            let difference = self.targetFrequency - self.currentFrequency
            if abs(difference) > 1.0 {
                self.currentFrequency += difference * 0.2  // 20% per update
            } else {
                self.currentFrequency = self.targetFrequency
                self.updateTimer?.invalidate()
            }
        }
    }

    // MARK: - Control Methods

    /// Stop all audio feedback
    func stopFeedback() {
        stopTone()
        stopPulsing()
        updateTimer?.invalidate()
    }

    /// Play a test tone at specific distance
    func playTestTone(distance: Float) {
        updateFeedback(distance: distance, direction: .center)

        // Stop after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.stopFeedback()
        }
    }

    /// Play directional test
    func playDirectionalTest() {
        let directions: [Direction] = [.left, .leftCenter, .center, .rightCenter, .right]

        for (index, direction) in directions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.8) {
                self.updateFeedback(distance: 1.5, direction: direction)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(directions.count) * 0.8) {
            self.stopFeedback()
        }
    }

    deinit {
        stopFeedback()
        audioEngine.stop()
    }
}