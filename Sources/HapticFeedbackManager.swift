import Foundation
import CoreHaptics
import UIKit

/// Manages haptic feedback with morse code patterns for directional navigation
class HapticFeedbackManager: ObservableObject {

    // MARK: - Properties
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?
    private var isPlaying = false
    private var lastDirection: NavigationDirection = .straight
    private var lastIntensity: Float = 0

    enum NavigationDirection {
        case left
        case right
        case straight
        case blocked
    }

    // MARK: - Initialization
    init() {
        setupHapticEngine()
    }

    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("Device does not support haptics")
            return
        }

        do {
            hapticEngine = try CHHapticEngine()

            // Configure engine callbacks
            hapticEngine?.stoppedHandler = { [weak self] reason in
                print("Haptic engine stopped: \(reason)")
                self?.restartEngine()
            }

            hapticEngine?.resetHandler = { [weak self] in
                print("Haptic engine reset")
                self?.restartEngine()
            }

            try hapticEngine?.start()
        } catch {
            print("Failed to initialize haptic engine: \(error)")
        }
    }

    private func restartEngine() {
        do {
            try hapticEngine?.start()
        } catch {
            print("Failed to restart haptic engine: \(error)")
        }
    }

    // MARK: - Morse Code Patterns

    /// Generate morse code pattern for left (dots: • • •)
    private func createLeftPattern(intensity: Float) -> CHHapticPattern? {
        var events: [CHHapticEvent] = []

        // Three short dots with increasing intensity based on proximity
        for i in 0..<3 {
            let dotIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: min(1.0, intensity * (1 + Float(i) * 0.1)) // Slightly increase each dot
            )
            let dotSharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.3 // Soft dots
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [dotIntensity, dotSharpness],
                relativeTime: TimeInterval(i) * 0.15 // 150ms between dots
            )
            events.append(event)
        }

        do {
            return try CHHapticPattern(events: events, parameters: [])
        } catch {
            print("Failed to create left pattern: \(error)")
            return nil
        }
    }

    /// Generate morse code pattern for right (dash: —)
    private func createRightPattern(intensity: Float) -> CHHapticPattern? {
        var events: [CHHapticEvent] = []

        // One long dash
        let dashIntensity = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: min(1.0, intensity)
        )
        let dashSharpness = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: 0.7 // Sharper for dash
        )

        // Create continuous haptic for dash (500ms duration)
        let dashStart = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [dashIntensity, dashSharpness],
            relativeTime: 0,
            duration: 0.5
        )
        events.append(dashStart)

        do {
            return try CHHapticPattern(events: events, parameters: [])
        } catch {
            print("Failed to create right pattern: \(error)")
            return nil
        }
    }

    /// Generate warning pattern for blocked path
    private func createBlockedPattern(intensity: Float) -> CHHapticPattern? {
        var events: [CHHapticEvent] = []

        // Rapid pulses indicating danger
        for i in 0..<5 {
            let pulseIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: min(1.0, intensity * 1.2) // Extra strong for danger
            )
            let pulseSharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 1.0 // Very sharp
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [pulseIntensity, pulseSharpness],
                relativeTime: TimeInterval(i) * 0.08 // Very rapid pulses
            )
            events.append(event)
        }

        do {
            return try CHHapticPattern(events: events, parameters: [])
        } catch {
            print("Failed to create blocked pattern: \(error)")
            return nil
        }
    }

    // MARK: - Public Methods

    /// Play haptic feedback based on direction and distance
    /// - Parameters:
    ///   - direction: Navigation direction (left, right, straight, blocked)
    ///   - distance: Distance to obstacle in meters (affects intensity)
    func playNavigationFeedback(direction: NavigationDirection, distance: Float) {
        guard let engine = hapticEngine else { return }

        // Calculate intensity based on distance (closer = stronger)
        // 0.3m = max intensity (1.0), 2m = min intensity (0.2)
        let intensity = max(0.2, min(1.0, (2.0 - distance) / 1.7))

        // Don't replay same pattern if it hasn't changed significantly
        if direction == lastDirection && abs(intensity - lastIntensity) < 0.1 && isPlaying {
            return
        }

        lastDirection = direction
        lastIntensity = intensity

        // Stop current pattern
        stopCurrentPattern()

        // Create pattern based on direction
        let pattern: CHHapticPattern?
        switch direction {
        case .left:
            pattern = createLeftPattern(intensity: intensity)
        case .right:
            pattern = createRightPattern(intensity: intensity)
        case .blocked:
            pattern = createBlockedPattern(intensity: intensity)
        case .straight:
            // No haptic for straight path
            return
        }

        guard let hapticPattern = pattern else { return }

        do {
            hapticPlayer = try engine.makePlayer(with: hapticPattern)
            try hapticPlayer?.start(atTime: 0)
            isPlaying = true

            // Schedule stop after pattern duration
            let duration = direction == .right ? 0.5 : (direction == .left ? 0.45 : 0.4)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.isPlaying = false
            }
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }

    /// Play a single pulse for obstacle detection
    func playObstacleDetectedPulse(intensity: Float) {
        guard let engine = hapticEngine else { return }

        let hapticIntensity = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: min(1.0, intensity)
        )
        let hapticSharpness = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: 0.5
        )

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [hapticIntensity, hapticSharpness],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play pulse: \(error)")
        }
    }

    /// Play success pattern when path is clear
    func playPathClearPattern() {
        guard let engine = hapticEngine else { return }

        var events: [CHHapticEvent] = []

        // Two gentle pulses indicating clear path
        for i in 0..<2 {
            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 0.4
            )
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.2
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: TimeInterval(i) * 0.2
            )
            events.append(event)
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play clear pattern: \(error)")
        }
    }

    /// Stop current haptic pattern
    func stopCurrentPattern() {
        hapticPlayer?.stop(atTime: 0)
        isPlaying = false
    }

    /// Stop all haptic feedback
    func stopAll() {
        stopCurrentPattern()
        hapticEngine?.stop()
    }

    /// Resume haptic engine
    func resume() {
        restartEngine()
    }
}