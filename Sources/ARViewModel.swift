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

    // Settings - reduced sensitivity
    @Published var warningThreshold: Float = 1.2  // Reduced from 1.5
    @Published var criticalThreshold: Float = 0.4  // Reduced from 0.5
    @Published var hapticEnabled = true
    @Published var audioEnabled = true
    @Published var visualWarningsEnabled = true
    @Published var showMesh = false
    @Published var showDepthMap = false
    @Published var showDebugInfo = false

    // Path Planning
    @Published var pathPlanningEnabled = true
    @Published var showPath = true
    @Published var navigationDirection: HapticFeedbackManager.NavigationDirection = .straight

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

    // New Managers
    private let hapticFeedbackManager = HapticFeedbackManager()
    private let audioDirectionManager = AudioDirectionManager()
    private let obstacleMemoryMap = ObstacleMemoryMap()
    private let pathPlanningEngine = PathPlanningEngine()
    private let pathVisualization = PathVisualization()

    // Intelligent Memory System
    private let memoryOptimizer = MemoryOptimizer.shared
    private var lastLocationCheck = Date()
    private var scanFrameCounter = 0

    // Improved Feedback Systems
    private let musicalFeedback = MusicalDistanceFeedback()
    private let simplifiedHaptics = SimplifiedHaptics()
    private let voiceGuidance = VoiceGuidance()
    private let accessibilityManager = AccessibilityManager.shared
    private var lastFeedbackTime = Date()

    // User position tracking
    private var userPosition = simd_float3(0, 0, 0)
    private var userHeading = simd_float3(0, 0, -1)
    private var destinationPosition: simd_float3?

    // MARK: - Initialization
    override init() {
        super.init()
        setupHapticEngine()
        setupAudioPlayer()
        setupManagers()
    }

    // MARK: - Setup Managers
    private func setupManagers() {
        // Configure audio direction manager
        audioDirectionManager.audioEnabled = audioEnabled

        // Set up path planning observer
        pathPlanningEngine.$currentPath
            .sink { [weak self] path in
                self?.pathVisualization.visualizePath(path)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

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

        // Setup path visualization
        pathVisualization.setup(in: arView)

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
            // Focus on upper 2/3 of frame to avoid ground detection
            let centerX = width / 2
            let centerY = height / 2 - height / 6  // Shift up to avoid ground
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

            // Find closest obstacle in forward path (exclude ground level)
            var minDistance: Float = Float.greatestFiniteMagnitude
            let scanWidth = width / 3
            let scanStartX = centerX - scanWidth / 2
            let scanEndX = centerX + scanWidth / 2

            // Scan only eye level area (avoid ground completely)
            let scanStartY = height / 3  // Start from upper third
            let scanEndY = height / 2  // Only scan middle area, not bottom half

            for y in scanStartY...scanEndY {
                for x in scanStartX...scanEndX {
                    let index = y * width + x
                    let confidence = ARConfidenceLevel(rawValue: Int(confidenceAddress[index])) ?? .low

                    if confidence != .low {
                        let distance = depthAddress[index]
                        // Much stricter filtering - ignore anything below 0.8m or above 3m
                        // This should only detect obstacles at torso/head level
                        if distance > 0.8 && distance < 3.0 && distance < minDistance {
                            minDistance = distance
                        }
                    }
                }
            }

            if minDistance < Float.greatestFiniteMagnitude {
                DispatchQueue.main.async {
                    self.closestObstacleDistance = minDistance
                    self.checkForWarnings(distance: minDistance)
                    self.updateNavigationGuidance()
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

    // MARK: - Intelligent Memory Methods

    /// Check current location and optimize scanning strategy
    private func checkAndOptimizeLocation() {
        // Collect current obstacles
        let obstacles = obstacleMemoryMap.getReliableObstacles().map { obs in
            (position: obs.position, size: obs.size, type: obs.classification.rawValue)
        }

        // Generate fingerprint and check location
        let bounds = calculateRoomBounds()
        memoryOptimizer.checkLocation(obstacles: obstacles, roomBounds: bounds)

        // If in known location, show stats
        if memoryOptimizer.isInKnownLocation {
            print(memoryOptimizer.getMemoryStats())
        }

        // Save location periodically
        if obstacles.count > 5 {
            memoryOptimizer.saveCurrentLocation(obstacles: obstacles)
        }
    }

    /// Use cached obstacles instead of scanning
    private func useCachedObstacles() {
        let cachedObstacles = memoryOptimizer.predictedObstacles

        // Convert to format for distance calculation
        for cached in cachedObstacles {
            obstacleMemoryMap.addOrUpdateObstacle(
                position: cached.position,
                size: cached.size,
                confidence: cached.permanence,
                classification: .unknown
            )
        }

        // Update distances using cached data
        updateDistancesFromCache(cachedObstacles)
    }

    /// Update distances using cached obstacles
    private func updateDistancesFromCache(_ obstacles: [SpatialMemoryDB.CachedObstacle]) {
        var minCenter = Float.infinity
        var minLeft = Float.infinity
        var minRight = Float.infinity

        for obstacle in obstacles {
            let distance = simd_distance(userPosition, obstacle.position)

            // Determine direction relative to user
            let toObstacle = obstacle.position - userPosition
            let forward = userHeading
            let right = simd_cross(simd_float3(0, 1, 0), forward)

            let forwardDot = simd_dot(simd_normalize(toObstacle), forward)
            let rightDot = simd_dot(simd_normalize(toObstacle), right)

            // Categorize by direction
            if abs(rightDot) < 0.5 && forwardDot > 0 {
                minCenter = min(minCenter, distance)
            } else if rightDot < -0.5 {
                minLeft = min(minLeft, distance)
            } else if rightDot > 0.5 {
                minRight = min(minRight, distance)
            }
        }

        // Update published distances
        DispatchQueue.main.async { [weak self] in
            self?.centerDistance = minCenter.isFinite ? minCenter : -1
            self?.leftDistance = minLeft.isFinite ? minLeft : -1
            self?.rightDistance = minRight.isFinite ? minRight : -1
        }
    }

    /// Calculate room bounds from obstacles
    private func calculateRoomBounds() -> (min: simd_float3, max: simd_float3)? {
        let obstacles = obstacleMemoryMap.getReliableObstacles()
        guard !obstacles.isEmpty else { return nil }

        let positions = obstacles.map { $0.position }
        let minPos = positions.reduce(simd_float3(Float.infinity, Float.infinity, Float.infinity)) { simd_min($0, $1) }
        let maxPos = positions.reduce(simd_float3(-Float.infinity, -Float.infinity, -Float.infinity)) { simd_max($0, $1) }

        return (min: minPos, max: maxPos)
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
        // Extract obstacle information from mesh
        guard let classificationData = classification else { return }

        // Sample vertices to create obstacle entries
        let vertexCount = vertices.count / vertices.stride  // Number of actual vertices
        let sampleStride = max(1, vertexCount / 100) // Sample every N vertices for performance

        for i in Swift.stride(from: 0, to: vertexCount, by: sampleStride) {
            // Get vertex position
            let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (i * vertices.stride))
            let vertex = vertexPointer.assumingMemoryBound(to: simd_float3.self).pointee

            // Transform to world coordinates
            let worldPos = simd_make_float3(transform * simd_float4(vertex, 1.0))

            // Get classification
            let classPointer = classificationData.buffer.contents().advanced(by: classificationData.offset + (i * classificationData.stride))
            let classValue = classPointer.assumingMemoryBound(to: UInt8.self).pointee
            let meshClass = ARMeshClassification(rawValue: Int(classValue)) ?? .none

            // Add to obstacle memory with height filtering
            let obstacleType = obstacleMemoryMap.classifyFromARMesh(meshClass)

            // Much stricter ground filtering
            let relativeHeight = worldPos.y - userPosition.y

            // Ignore anything below waist level (1m below camera) or above head (0.5m above camera)
            let isTooLow = relativeHeight < -1.0  // Below waist
            let isTooHigh = relativeHeight > 0.5  // Above head level

            // Also check if it's classified as floor/ceiling
            let isGroundOrCeiling = obstacleType == ObstacleMemoryMap.ObstacleType.floor ||
                                   obstacleType == ObstacleMemoryMap.ObstacleType.ceiling

            // Only add obstacles that are at reasonable height and not floor/ceiling
            if !isGroundOrCeiling && !isTooLow && !isTooHigh {
                obstacleMemoryMap.addOrUpdateObstacle(
                    position: worldPos,
                    size: simd_float3(0.3, 0.3, 0.3), // Default size
                    confidence: 0.8,
                    classification: obstacleType
                )
            }
        }
    }

    // MARK: - Navigation Methods

    /// Update navigation guidance based on obstacles
    private func updateNavigationGuidance() {
        // Determine navigation direction based on obstacles
        let leftClear = leftDistance > warningThreshold || leftDistance < 0
        let rightClear = rightDistance > warningThreshold || rightDistance < 0
        let frontClear = centerDistance > warningThreshold || centerDistance < 0

        // Find closest obstacle and its direction
        let distances = [
            (centerDistance, MusicalDistanceFeedback.Direction.center),
            (leftDistance, MusicalDistanceFeedback.Direction.left),
            (rightDistance, MusicalDistanceFeedback.Direction.right)
        ].filter { $0.0 > 0 }  // Filter out invalid readings

        if let closest = distances.min(by: { $0.0 < $1.0 }) {
            let (distance, obstacleDirection) = closest

            // Only use haptic feedback - no audio/voice
            // Musical feedback disabled - too annoying
            // musicalFeedback.updateFeedback(distance: distance, direction: obstacleDirection)

            // Morse code haptic feedback will be provided based on navigation direction

            // VoiceOver announcements for accessibility
            if obstacleDirection == .center {
                accessibilityManager.announceObstacle(distance: distance, direction: "ahead")
            } else if obstacleDirection == .left {
                accessibilityManager.announceObstacle(distance: distance, direction: "on your left")
            } else if obstacleDirection == .right {
                accessibilityManager.announceObstacle(distance: distance, direction: "on your right")
            }

            // Simplified navigation - focus on clear walking path
            if distance < criticalThreshold {
                // Very close - STOP
                simplifiedHaptics.navigationFeedback(direction: .stop, distance: distance)
                navigationDirection = .blocked
            } else if !frontClear && distance < warningThreshold {
                // Obstacle ahead - need to turn

                // Check if there's enough space to walk through
                let canWalkStraight = (leftDistance > 0.8 || rightDistance > 0.8) &&
                                     frontClear

                if canWalkStraight {
                    // Can squeeze through - go straight
                    simplifiedHaptics.navigationFeedback(direction: .straight, distance: 999)
                    navigationDirection = .straight
                } else if leftClear && rightClear {
                    // Both sides available - pick side with more room
                    if leftDistance > rightDistance + 0.3 {  // Prefer left if significantly more space
                        simplifiedHaptics.navigationFeedback(direction: .left, distance: distance)
                        navigationDirection = .left
                    } else if rightDistance > leftDistance + 0.3 {
                        simplifiedHaptics.navigationFeedback(direction: .right, distance: distance)
                        navigationDirection = .right
                    } else {
                        // Similar space - default to right
                        simplifiedHaptics.navigationFeedback(direction: .right, distance: distance)
                        navigationDirection = .right
                    }
                } else if leftClear {
                    // Only left available
                    simplifiedHaptics.navigationFeedback(direction: .left, distance: distance)
                    navigationDirection = .left
                } else if rightClear {
                    // Only right available
                    simplifiedHaptics.navigationFeedback(direction: .right, distance: distance)
                    navigationDirection = .right
                } else {
                    // No path - STOP
                    simplifiedHaptics.navigationFeedback(direction: .stop, distance: distance)
                    navigationDirection = .blocked
                }
            } else if frontClear {
                // Path is clear - tell them to go straight
                simplifiedHaptics.navigationFeedback(direction: .straight, distance: 999)
                navigationDirection = .straight
            }
        } else {
            // No obstacles detected - clear path
            // musicalFeedback.stopFeedback()  // Disabled
            navigationDirection = .straight

            // Announce clear path for VoiceOver users
            if Date().timeIntervalSince(lastWarningTime) > 5.0 {
                accessibilityManager.announceClearPath()  // VoiceOver announcement
                simplifiedHaptics.successFeedback()
                lastWarningTime = Date()
            }
        }

        // Update path if needed
        if pathPlanningEnabled && destinationPosition != nil {
            updatePath()
        }
    }

    /// Map haptic direction to audio direction
    private func mapToAudioDirection(_ direction: HapticFeedbackManager.NavigationDirection) -> AudioDirectionManager.NavigationDirection {
        switch direction {
        case .left: return .left
        case .right: return .right
        case .straight: return .straight
        case .blocked: return .blocked
        }
    }

    /// Set navigation destination
    func setDestination(_ position: simd_float3) {
        destinationPosition = position
        updatePath()
    }

    /// Update path planning
    private func updatePath() {
        guard let destination = destinationPosition else { return }

        let obstacles = obstacleMemoryMap.getReliableObstacles()
        pathPlanningEngine.planPath(
            from: userPosition,
            to: destination,
            obstacles: obstacles,
            userHeading: userHeading
        )
    }

    /// Clear navigation
    func clearNavigation() {
        destinationPosition = nil
        pathPlanningEngine.clearPath()
        hapticFeedbackManager.stopAll()
        audioDirectionManager.stopAll()
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

        // Update user position and heading
        let transform = frame.camera.transform
        userPosition = simd_make_float3(transform.columns.3)
        userHeading = -simd_make_float3(transform.columns.2) // Forward direction

        // Intelligent Memory: Check location every 5 seconds
        if Date().timeIntervalSince(lastLocationCheck) > 5.0 {
            checkAndOptimizeLocation()
            lastLocationCheck = Date()
        }

        // Intelligent Memory: Adjust scan frequency based on mode
        let scanParams = memoryOptimizer.getOptimizedScanParameters()
        scanFrameCounter += 1

        // Skip frames based on optimization mode
        let shouldSkipFrame = scanFrameCounter % (60 / scanParams.frequency) != 0

        // Update path planning with user position
        pathPlanningEngine.updateUserPosition(
            userPosition,
            heading: userHeading,
            obstacles: obstacleMemoryMap.getReliableObstacles()
        )

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

        // Process depth data if available (with intelligent optimization)
        if let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth {
            // Check if we should use cache instead of processing
            if !shouldSkipFrame && !memoryOptimizer.shouldUseCache(for: userPosition) {
                processDepthData(depthData)
            } else if memoryOptimizer.isInKnownLocation {
                // Use cached/predicted obstacles
                useCachedObstacles()
            }
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