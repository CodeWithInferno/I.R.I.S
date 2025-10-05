import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    @StateObject private var arViewModel = ARViewModel()
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            // AR View
            ARViewContainer(arViewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
                .accessibilityLabel("Camera view for obstacle detection")
                .accessibilityHint("Hold phone upright and point forward to detect obstacles")

            // Overlay UI
            VStack {
                // Top Bar with status and settings
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LiDAR Obstacle Detection")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack {
                            Circle()
                                .fill(arViewModel.isTracking ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(arViewModel.isTracking ? "Tracking Active" : "Initializing...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    Spacer()

                    Button(action: { showingSettings.toggle() }) {
                        Image(systemName: "gear")
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))

                Spacer()

                // Distance Display
                VStack(spacing: 16) {
                    // Main distance indicator
                    DistanceIndicator(
                        distance: arViewModel.centerDistance,
                        label: "Front",
                        isWarning: arViewModel.centerDistance < arViewModel.warningThreshold
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(getAccessibilityLabel(for: arViewModel.centerDistance, direction: "front"))
                    .accessibilityHint("Distance to obstacle directly ahead")

                    // Side distances
                    HStack(spacing: 40) {
                        DistanceIndicator(
                            distance: arViewModel.leftDistance,
                            label: "Left",
                            isWarning: arViewModel.leftDistance < arViewModel.warningThreshold,
                            isCompact: true
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(getAccessibilityLabel(for: arViewModel.leftDistance, direction: "left"))

                        DistanceIndicator(
                            distance: arViewModel.rightDistance,
                            label: "Right",
                            isWarning: arViewModel.rightDistance < arViewModel.warningThreshold,
                            isCompact: true
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(getAccessibilityLabel(for: arViewModel.rightDistance, direction: "right"))
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
                .padding()
            }

            // Warning overlay
            if arViewModel.showWarning {
                WarningOverlay(distance: arViewModel.closestObstacleDistance)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(arViewModel: arViewModel)
        }
        .onAppear {
            arViewModel.checkLiDARAvailability()
        }
        .alert("LiDAR Not Available", isPresented: $arViewModel.showLiDARAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This app requires a device with LiDAR Scanner (iPhone 12 Pro or later).")
        }
    }

    // MARK: - Accessibility Helpers

    private func getAccessibilityLabel(for distance: Float, direction: String) -> String {
        if distance < 0 {
            return "No obstacle detected on \(direction)"
        } else if distance > 5.0 {
            return "Clear path on \(direction), no obstacles nearby"
        } else if distance < 0.5 {
            return "Warning! Obstacle very close on \(direction), \(String(format: "%.1f", distance)) meters"
        } else if distance < 1.0 {
            return "Caution, obstacle on \(direction) at \(String(format: "%.1f", distance)) meters"
        } else {
            return "Obstacle on \(direction) at \(String(format: "%.1f", distance)) meters"
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arViewModel: ARViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arViewModel.setupAR(in: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Update AR view if needed
    }
}

struct DistanceIndicator: View {
    let distance: Float
    let label: String
    let isWarning: Bool
    var isCompact: Bool = false

    private var distanceText: String {
        if distance > 5.0 {
            return ">5m"
        } else if distance < 0 {
            return "--"
        } else {
            return String(format: "%.1fm", distance)
        }
    }

    private var indicatorColor: Color {
        // High contrast colors for accessibility
        if distance < 0 {
            return Color.white
        } else if distance < 0.5 {
            return Color.red  // Danger
        } else if distance < 1.0 {
            return Color.orange  // Warning
        } else if distance < 2.0 {
            return Color.yellow  // Caution
        } else {
            return Color.green  // Safe
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(isCompact ? .headline : .title3)  // Larger text
                .fontWeight(.semibold)
                .foregroundColor(.white)  // Full white for contrast

            Text(distanceText)
                .font(isCompact ? .title2 : .largeTitle)  // Much larger
                .fontWeight(.heavy)  // Bolder for visibility
                .foregroundColor(indicatorColor)
                .shadow(color: .black, radius: 2)  // Black shadow for contrast
        }
        .padding(isCompact ? 16 : 20)  // More padding
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.9))  // Darker background
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(indicatorColor, lineWidth: isWarning ? 4 : 2)  // Thicker border
                )
        )
        .scaleEffect(isWarning && !isCompact ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isWarning)
    }
}

struct WarningOverlay: View {
    let distance: Float
    @State private var opacity: Double = 0

    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("OBSTACLE DETECTED")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(String(format: "%.1f meters ahead", distance))
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.red.opacity(0.9))
        )
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var arViewModel: ARViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Detection Settings") {
                    VStack(alignment: .leading) {
                        Text("Warning Distance: \(String(format: "%.1fm", arViewModel.warningThreshold))")
                            .font(.subheadline)
                        Slider(value: $arViewModel.warningThreshold, in: 0.5...3.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        Text("Critical Distance: \(String(format: "%.1fm", arViewModel.criticalThreshold))")
                            .font(.subheadline)
                        Slider(value: $arViewModel.criticalThreshold, in: 0.3...1.5, step: 0.1)
                    }
                }

                Section("Feedback") {
                    Toggle("Haptic Feedback", isOn: $arViewModel.hapticEnabled)
                    Toggle("Audio Alerts", isOn: $arViewModel.audioEnabled)
                    Toggle("Visual Warnings", isOn: $arViewModel.visualWarningsEnabled)
                }

                Section("Display") {
                    Toggle("Show Mesh", isOn: $arViewModel.showMesh)
                    Toggle("Show Depth Map", isOn: $arViewModel.showDepthMap)
                    Toggle("Debug Info", isOn: $arViewModel.showDebugInfo)
                }

                Section("Navigation") {
                    Toggle("Path Planning", isOn: $arViewModel.pathPlanningEnabled)
                    Toggle("Show AR Path", isOn: $arViewModel.showPath)

                    if arViewModel.navigationDirection != .straight {
                        HStack {
                            Text("Direction Guidance")
                            Spacer()
                            Text(navigationDirectionText(arViewModel.navigationDirection))
                                .foregroundColor(navigationDirectionColor(arViewModel.navigationDirection))
                                .fontWeight(.semibold)
                        }
                    }

                    Button(action: testNavigationFeedback) {
                        Label("Test Navigation Feedback", systemImage: "speaker.wave.3")
                    }
                }

                Section("About") {
                    HStack {
                        Text("LiDAR Status")
                        Spacer()
                        Text(arViewModel.isLiDARAvailable ? "Available" : "Not Available")
                            .foregroundColor(arViewModel.isLiDARAvailable ? .green : .red)
                    }

                    HStack {
                        Text("Tracking Quality")
                        Spacer()
                        Text(arViewModel.trackingQuality)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func navigationDirectionText(_ direction: HapticFeedbackManager.NavigationDirection) -> String {
        switch direction {
        case .left: return "Turn Left"
        case .right: return "Turn Right"
        case .blocked: return "Path Blocked"
        case .straight: return "Straight Ahead"
        }
    }

    private func navigationDirectionColor(_ direction: HapticFeedbackManager.NavigationDirection) -> Color {
        switch direction {
        case .left, .right: return .yellow
        case .blocked: return .red
        case .straight: return .green
        }
    }

    private func testNavigationFeedback() {
        // Test left morse code pattern
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // This would trigger test feedback in the AR model
        }
    }
}

#Preview {
    ContentView()
}