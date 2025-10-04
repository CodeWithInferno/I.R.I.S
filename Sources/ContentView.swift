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

                    // Side distances
                    HStack(spacing: 40) {
                        DistanceIndicator(
                            distance: arViewModel.leftDistance,
                            label: "Left",
                            isWarning: arViewModel.leftDistance < arViewModel.warningThreshold,
                            isCompact: true
                        )

                        DistanceIndicator(
                            distance: arViewModel.rightDistance,
                            label: "Right",
                            isWarning: arViewModel.rightDistance < arViewModel.warningThreshold,
                            isCompact: true
                        )
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
        if distance < 0 {
            return Color.gray
        } else if distance < 0.5 {
            return Color.red
        } else if distance < 1.0 {
            return Color.orange
        } else if distance < 2.0 {
            return Color.yellow
        } else {
            return Color.green
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(isCompact ? .caption : .subheadline)
                .foregroundColor(.white.opacity(0.7))

            Text(distanceText)
                .font(isCompact ? .title3 : .title)
                .fontWeight(.bold)
                .foregroundColor(indicatorColor)
                .shadow(color: indicatorColor.opacity(0.5), radius: isWarning ? 10 : 5)
        }
        .padding(isCompact ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(indicatorColor.opacity(0.5), lineWidth: isWarning ? 3 : 1)
                )
        )
        .scaleEffect(isWarning && !isCompact ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: isWarning)
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
}

#Preview {
    ContentView()
}