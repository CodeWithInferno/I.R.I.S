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
    private let minimumInterval: TimeInterval = 0.5  // Prevent overwhelming feedback

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

    // MARK: - Simplified Feedback Patterns

    /// Single gentle tap - minor obstacle detected
    func singleTap(intensity: Float = 0.5) {
        guard isEnabled, canProvideFeedback() else { return }

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

        playPattern(events: [event])
    }

    /// Double tap - turn recommended
    func doubleTap(intensity: Float = 0.7) {
        guard isEnabled, canProvideFeedback() else { return }

        var events: [CHHapticEvent] = []

        for i in 0..<2 {
            let hapticIntensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: min(1.0, intensity)
            )
            let hapticSharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.7
            )

            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [hapticIntensity, hapticSharpness],
                relativeTime: TimeInterval(i) * 0.15
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

    /// Distance-based feedback - intensity increases as obstacle gets closer
    func distanceBasedFeedback(distance: Float) {
        guard isEnabled else { return }

        // Calculate intensity based on distance
        // 0.3m = max intensity (1.0), 2m = min intensity (0.2)
        let intensity = max(0.2, min(1.0, (2.0 - distance) / 1.7))

        if distance < 0.5 {
            // Very close - continuous warning
            continuousWarning(duration: 0.3, intensity: intensity)
        } else if distance < 1.0 {
            // Close - double tap
            doubleTap(intensity: intensity)
        } else if distance < 2.0 {
            // Moderate distance - single tap
            singleTap(intensity: intensity)
        }
        // No haptic beyond 2m
    }

    /// Direction indicator - left or right
    func directionIndicator(direction: Direction) {
        guard isEnabled, canProvideFeedback() else { return }

        switch direction {
        case .left:
            // Single tap for left
            singleTap(intensity: 0.6)
        case .right:
            // Double tap for right
            doubleTap(intensity: 0.6)
        case .straight:
            // No haptic for straight
            break
        }
    }

    enum Direction {
        case left
        case right
        case straight
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