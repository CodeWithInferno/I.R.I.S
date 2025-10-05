import Foundation
import UIKit

/// Manages accessibility features for blind and low vision users
class AccessibilityManager: ObservableObject {

    // MARK: - Properties
    static let shared = AccessibilityManager()

    private var lastAnnouncementTime = Date()
    private let minimumAnnouncementInterval: TimeInterval = 3.0
    private var lastAnnouncedDistance: Float = -1
    private let significantDistanceChange: Float = 0.3  // Only announce if distance changed by 30cm

    @Published var voiceOverEnabled: Bool = false

    // MARK: - Initialization
    init() {
        checkVoiceOverStatus()
        setupNotifications()
    }

    private func checkVoiceOverStatus() {
        voiceOverEnabled = UIAccessibility.isVoiceOverRunning
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(voiceOverStatusChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func voiceOverStatusChanged() {
        checkVoiceOverStatus()
    }

    // MARK: - VoiceOver Announcements

    /// Announce obstacle detection to VoiceOver
    func announceObstacle(distance: Float, direction: String) {
        guard voiceOverEnabled else { return }

        // Check if enough time has passed
        guard Date().timeIntervalSince(lastAnnouncementTime) > minimumAnnouncementInterval else { return }

        // Check if distance has changed significantly
        let distanceChanged = abs(distance - lastAnnouncedDistance) > significantDistanceChange
        guard distanceChanged || lastAnnouncedDistance < 0 else { return }

        var announcement = ""

        if distance < 0.5 {
            announcement = "Warning: Obstacle very close \(direction), \(String(format: "%.1f", distance)) meters. Stop or turn."
            // Post with high priority
            UIAccessibility.post(notification: .announcement, argument: announcement)
        } else if distance < 1.0 {
            announcement = "Caution: Obstacle \(direction) at \(String(format: "%.1f", distance)) meters"
            UIAccessibility.post(notification: .announcement, argument: announcement)
        } else if distance < 1.5 {
            announcement = "Obstacle detected \(direction) at \(String(format: "%.1f", distance)) meters"
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }

        lastAnnouncementTime = Date()
        lastAnnouncedDistance = distance
    }

    /// Announce clear path
    func announceClearPath() {
        guard voiceOverEnabled else { return }

        // Only announce occasionally
        guard Date().timeIntervalSince(lastAnnouncementTime) > minimumAnnouncementInterval * 2 else { return }

        UIAccessibility.post(notification: .announcement, argument: "Path is clear")
        lastAnnouncementTime = Date()
        lastAnnouncedDistance = -1
    }

    /// Announce direction suggestion
    func announceDirection(_ direction: String) {
        guard voiceOverEnabled else { return }

        UIAccessibility.post(notification: .announcement, argument: "Suggested direction: \(direction)")
    }

    /// Announce app status
    func announceStatus(_ status: String) {
        guard voiceOverEnabled else { return }

        UIAccessibility.post(notification: .announcement, argument: status)
    }

    // MARK: - Screen Change Notifications

    /// Notify when screen content changes significantly
    func notifyScreenChange() {
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// Notify layout change
    func notifyLayoutChange() {
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    // MARK: - Accessibility Actions

    /// Check if reduce motion is enabled
    var reduceMotionEnabled: Bool {
        return UIAccessibility.isReduceMotionEnabled
    }

    /// Check if bold text is enabled
    var boldTextEnabled: Bool {
        return UIAccessibility.isBoldTextEnabled
    }

    /// Check if larger text is preferred
    var preferredContentSizeCategory: UIContentSizeCategory {
        return UIApplication.shared.preferredContentSizeCategory
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}