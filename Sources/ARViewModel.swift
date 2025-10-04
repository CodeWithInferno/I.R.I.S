import SwiftUI
import RealityKit
import ARKit
import Combine
import AVFoundation
import CoreHaptics

class ARViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var centerDistance: Float = -1
    @Published var leftDistance: Float = -1
    @Published var rightDistance: Float = -1
    @Published var closestObstacleDistance: Float = -1
    @Published var isTracking = false
    @Published var showWarning = false
    @Published var isLiDARAvailable = false
    @Published var showLiDARAlert = false
    @Published var trackingQuality = "Unknown"

    // Settings
    @Published var warningThreshold: Float = 1.5
    @Published var criticalThreshold: Float = 0.5
    @Published var hapticEnabled = true
    @Published var audioEnabled = true
    @Published var visualWarningsEnabled = true
    @Published var showMesh = false
    @Published var showDepthMap = false
    @Published var showDebugInfo = false

    // MARK: - Private Properties
    private var arView: ARView?
    private var session: ARSession?
    private var hapticEngine: CHHapticEngine?
    private var audioPlayer: AVAudioPlayer?
    private var lastWarningTime = Date()
    private var warningCooldown: TimeInterval = 2.0

    // Depth processing
    private let depthQueue = DispatchQueue(label: "depth.processing.queue")
    private var currentDepthBuffer: CVPixelBuffer?
    private var depthConfidence: ARConfidenceLevel = .low

    // Mesh anchors
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]

    // MARK: - Initialization
    override init() {
        super.init()
        setupHapticEngine()
        setupAudioPlayer()
    }

    // MARK: - LiDAR Check
    func checkLiDARAvailability() {
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

        if !isLiDARAvailable {
            showLiDARAlert = true
        }
    }

    // MARK: - AR Setup
    func setupAR(in arView: ARView) {
        self.arView = arView
        self.session = arView.session

        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()

        // Check for LiDAR support and configure accordingly
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }

        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        configuration.isLightEstimationEnabled = true

        // Set delegates
        arView.session.delegate = self

        // Run the session
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        // Setup scene
        setupScene()
    }

    private func setupScene() {
        guard let arView = arView else { return }

        // Add lighting
        let directionalLight = DirectionalLight()
        directionalLight.light.intensity = 1000
        // isRealWorldProxyLightingEnabled is not available in iOS 15
        directionalLight.shadow?.maximumDistance = 10
        directionalLight.shadow?.depthBias = 5

        let lightAnchor = AnchorEntity(world: .zero)
        lightAnchor.addChild(directionalLight)
        arView.scene.addAnchor(lightAnchor)
    }

    // MARK: - Depth Processing
    private func processDepthData(_ depthData: ARDepthData) {
        depthQueue.async { [weak self] in
            guard let self = self else { return }

            let depthBuffer = depthData.depthMap
            guard let confidenceBuffer = depthData.confidenceMap else { return }

            CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
            CVPixelBufferLockBaseAddress(confidenceBuffer, .readOnly)

            defer {
                CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)
                CVPixelBufferUnlockBaseAddress(confidenceBuffer, .readOnly)
            }

            let width = CVPixelBufferGetWidth(depthBuffer)
            let height = CVPixelBufferGetHeight(depthBuffer)

            guard let depthAddress = CVPixelBufferGetBaseAddress(depthBuffer)?.assumingMemoryBound(to: Float32.self),
                  let confidenceAddress = CVPixelBufferGetBaseAddress(confidenceBuffer)?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            // Sample points for distance calculation
            let centerX = width / 2
            let centerY = height / 2
            let leftX = width / 4
            let rightX = (width * 3) / 4

            // Get center distance
            let centerIndex = centerY * width + centerX
            let centerConfidence = ARConfidenceLevel(rawValue: Int(confidenceAddress[centerIndex])) ?? .low

            if centerConfidence != .low {
                let distance = depthAddress[centerIndex]
                DispatchQueue.main.async {
                    self.centerDistance = distance
                }
            }

            // Get left distance
            let leftIndex = centerY * width + leftX
            let leftConfidence = ARConfidenceLevel(rawValue: Int(confidenceAddress[leftIndex])) ?? .low

            if leftConfidence != .low {
                let distance = depthAddress[leftIndex]
                DispatchQueue.main.async {
                    self.leftDistance = distance
                }
            }

            // Get right distance
            let rightIndex = centerY * width + rightX
            let rightConfidence = ARConfidenceLevel(rawValue: Int(confidenceAddress[rightIndex])) ?? .low

            if rightConfidence != .low {
                let distance = depthAddress[rightIndex]
                DispatchQueue.main.async {
                    self.rightDistance = distance
                }
            }

            // Find closest obstacle in forward path
            var minDistance: Float = Float.greatestFiniteMagnitude
            let scanWidth = width / 3
            let scanStartX = centerX - scanWidth / 2
            let scanEndX = centerX + scanWidth / 2

            for y in (height/3)...(2*height/3) {
                for x in scanStartX...scanEndX {
                    let index = y * width + x
                    let confidence = ARConfidenceLevel(rawValue: Int(confidenceAddress[index])) ?? .low

                    if confidence != .low {
                        let distance = depthAddress[index]
                        if distance > 0 && distance < minDistance {
                            minDistance = distance
                        }
                    }
                }
            }

            if minDistance < Float.greatestFiniteMagnitude {
                DispatchQueue.main.async {
                    self.closestObstacleDistance = minDistance
                    self.checkForWarnings(distance: minDistance)
                }
            }
        }
    }

    // MARK: - Warning System
    private func checkForWarnings(distance: Float) {
        let now = Date()

        if distance < warningThreshold {
            if now.timeIntervalSince(lastWarningTime) > warningCooldown {
                lastWarningTime = now

                if visualWarningsEnabled {
                    showWarning = true
                }

                if hapticEnabled {
                    if distance < criticalThreshold {
                        triggerCriticalHaptic()
                    } else {
                        triggerWarningHaptic()
                    }
                }

                if audioEnabled {
                    playWarningSound(isCritical: distance < criticalThreshold)
                }
            }
        }
    }

    // MARK: - Haptic Feedback
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Failed to start haptic engine: \(error)")
        }
    }

    private func triggerWarningHaptic() {
        guard let engine = hapticEngine else { return }

        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic: \(error)")
        }
    }

    private func triggerCriticalHaptic() {
        guard let engine = hapticEngine else { return }

        var events: [CHHapticEvent] = []

        for i in 0..<3 {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: TimeInterval(i) * 0.1)
            events.append(event)
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play critical haptic: \(error)")
        }
    }

    // MARK: - Audio Feedback
    private func setupAudioPlayer() {
        // Create a simple beep sound
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.ambient, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func playWarningSound(isCritical: Bool) {
        // Use system sounds for warnings
        let soundID: SystemSoundID = isCritical ? 1073 : 1052
        AudioServicesPlaySystemSound(soundID)
    }

    // MARK: - Mesh Processing
    private func processMeshAnchor(_ anchor: ARMeshAnchor) {
        meshAnchors[anchor.identifier] = anchor

        // Process mesh for obstacle detection
        let geometry = anchor.geometry
        let vertices = geometry.vertices
        let classification = geometry.classification

        // Analyze mesh for obstacles (tables, walls, etc.)
        analyzeMeshForObstacles(vertices: vertices, classification: classification, transform: anchor.transform)
    }

    private func analyzeMeshForObstacles(vertices: ARGeometrySource, classification: ARGeometrySource?, transform: simd_float4x4) {
        // This would analyze the mesh geometry to identify specific obstacles
        // For now, we're using depth data for distance calculation
    }
}

// MARK: - ARSessionDelegate
extension ARViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update tracking status
        if case .normal = frame.camera.trackingState {
            isTracking = true
        } else {
            isTracking = false
        }

        // Update tracking quality
        switch frame.camera.trackingState {
        case .normal:
            trackingQuality = "Good"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                trackingQuality = "Excessive Motion"
            case .insufficientFeatures:
                trackingQuality = "Low Features"
            case .initializing:
                trackingQuality = "Initializing"
            case .relocalizing:
                trackingQuality = "Relocalizing"
            @unknown default:
                trackingQuality = "Limited"
            }
        case .notAvailable:
            trackingQuality = "Not Available"
        }

        // Process depth data if available
        if let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth {
            processDepthData(depthData)
            // confidenceLevel is not a direct property, confidence is determined per pixel
            depthConfidence = .medium
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                processMeshAnchor(meshAnchor)
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                processMeshAnchor(meshAnchor)
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            meshAnchors.removeValue(forKey: anchor.identifier)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR Session failed: \(error)")
        isTracking = false
    }

    func sessionWasInterrupted(_ session: ARSession) {
        isTracking = false
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and anchors
        guard let arView = arView else { return }
        setupAR(in: arView)
    }
}