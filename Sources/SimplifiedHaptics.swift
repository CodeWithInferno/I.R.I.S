import Foundation
import CoreHaptics
import UIKit

/// Simplified haptic feedback system for intuitive navigation
class SimplifiedHaptics: ObservableObject {

    // MARK: - Properties
    private var hapticEngine: CHHapticEngine?
    @Published var isEnabled = true

    // Feedback timing control
    private var lastFeedbackTime = Date()
    private let minimumInterval: TimeInterval = 2.5  // Much longer gap between feedbacks
    private var lastDirection: Direction? = nil

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

    /// Dots pattern (. . . .) - Turn LEFT
    func dotsForLeft() {
        guard isEnabled, canProvideFeedback() else { return }

        var events: [CHHapticEvent] = []

        // 4 short taps for LEFT
        for i in 0..<4 {
            let hapticIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 0.8  // Strong enough to feel
            )
            let hapticSharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 1.0  // Sharp, distinct taps
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [hapticIntensity, hapticSharpness],
                relativeTime: TimeInterval(i) * 0.2  // Quick dots
            )
            events.append(event)
        }

        playPattern(events: events)
    }

    /// Dash pattern (---) - Turn RIGHT
    func dashForRight() {
        guard isEnabled, canProvideFeedback() else { return }

        let hapticIntensity = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: 0.8  // Strong vibration
        )
        let hapticSharpness = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: 0.3  // Smooth, continuous
        )

        // One long continuous vibration for RIGHT
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [hapticIntensity, hapticSharpness],
            relativeTime: 0,
            duration: 0.8  // Long dash
        )

        playPattern(events: [event])
    }

    /// Two short taps - Go STRAIGHT
    func goStraight() {
        guard isEnabled, canProvideFeedback() else { return }

        var events: [CHHapticEvent] = []

        // 2 gentle taps for STRAIGHT
        for i in 0..<2 {
            let hapticIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 0.6  // Gentler
            )
            let hapticSharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.8
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [hapticIntensity, hapticSharpness],
                relativeTime: TimeInterval(i) * 0.3
            )
            events.append(event)
        }

        playPattern(events: events)
    }

    /// Continuous vibration - stop, obstacle directly ahead
    func continuousWarning(duration: TimeInterval = 0.5, intensity: Float = 0.9) {
        guard isEnabled else { return }

        let hapticIntensity = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: min(1.0, intensity)
        )
        let hapticSharpness = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: 1.0  // Sharp for urgency
        )

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [hapticIntensity, hapticSharpness],
            relativeTime: 0,
            duration: duration
        )

        playPattern(events: [event])
    }

    /// Simple navigation feedback - only one at a time
    func navigationFeedback(direction: Direction, distance: Float) {
        guard isEnabled else { return }

        // Don't repeat same direction too quickly
        if direction == lastDirection &&
           Date().timeIntervalSince(lastFeedbackTime) < minimumInterval {
            return
        }

        // Only give feedback for important navigation
        switch direction {
        case .left:
            // Dots for left (. . . .)
            dotsForLeft()
            lastDirection = .left
            lastFeedbackTime = Date()
        case .right:
            // Dash for right (---)
            dashForRight()
            lastDirection = .right
            lastFeedbackTime = Date()
        case .straight:
            // Two taps for go straight
            goStraight()
            lastDirection = .straight
            lastFeedbackTime = Date()
        case .stop:
            // Only warn if very close
            if distance < 0.5 {
                continuousWarning(duration: 0.5, intensity: 1.0)
                lastDirection = .stop
                lastFeedbackTime = Date()
            }
        }
    }

    enum Direction {
        case left
        case right
        case straight
        case stop
    }

    /// Success feedback - path is clear
    func successFeedback() {
        guard isEnabled else { return }

        // Two gentle, pleasant taps
        var events: [CHHapticEvent] = []

        for i in 0..<2 {
            let hapticIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 0.3
            )
            let hapticSharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.2  // Soft and pleasant
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [hapticIntensity, hapticSharpness],
                relativeTime: TimeInterval(i) * 0.2
            )
            events.append(event)
        }

        playPattern(events: events)
    }

    // MARK: - Helper Methods

    private func canProvideFeedback() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastFeedbackTime) < minimumInterval {
            return false
        }
        lastFeedbackTime = now
        return true
    }

    private func playPattern(events: [CHHapticEvent]) {
        guard let engine = hapticEngine else { return }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }

    /// Stop all haptic feedback
    func stopAll() {
        hapticEngine?.stop()
    }

    /// Resume haptic engine
    func resume() {
        restartEngine()
    }

    deinit {
        hapticEngine?.stop()
    }
}