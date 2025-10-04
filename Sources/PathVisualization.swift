import Foundation
import RealityKit
import ARKit
import simd
import Combine

/// Manages AR visualization of the planned path
class PathVisualization: ObservableObject {

    // MARK: - Properties

    private var arView: ARView?
    private var pathAnchor: AnchorEntity?
    private var waypointAnchors: [AnchorEntity] = []
    private var arrowEntities: [ModelEntity] = []
    private var pathLineEntity: ModelEntity?
    private var destinationMarker: ModelEntity?

    @Published var isVisualizationEnabled = true
    @Published var showWaypoints = true
    @Published var showPathLine = true
    @Published var showArrows = true
    @Published var pathColor = UIColor.systemGreen

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupBindings()
    }

    private func setupBindings() {
        // React to visualization settings changes
        $isVisualizationEnabled
            .sink { [weak self] enabled in
                self?.setVisualizationVisibility(enabled)
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    /// Setup visualization in AR view
    func setup(in arView: ARView) {
        self.arView = arView

        // Create main path anchor
        pathAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(pathAnchor!)
    }

    // MARK: - Path Visualization

    /// Visualize the planned path
    func visualizePath(_ waypoints: [PathPlanningEngine.Waypoint]) {
        clearVisualization()

        guard isVisualizationEnabled, !waypoints.isEmpty else { return }

        if showPathLine {
            createPathLine(waypoints)
        }

        if showWaypoints {
            createWaypointMarkers(waypoints)
        }

        if showArrows {
            createDirectionalArrows(waypoints)
        }

        // Create destination marker
        if let lastWaypoint = waypoints.last {
            createDestinationMarker(at: lastWaypoint.position)
        }
    }

    /// Create continuous path line
    private func createPathLine(_ waypoints: [PathPlanningEngine.Waypoint]) {
        guard waypoints.count >= 2 else { return }

        var positions: [simd_float3] = []
        for waypoint in waypoints {
            positions.append(waypoint.position)
        }

        // Create mesh for path line
        let pathMesh = generatePathMesh(from: positions)
        let material = SimpleMaterial(color: pathColor.withAlphaComponent(0.8), isMetallic: false)

        pathLineEntity = ModelEntity(mesh: pathMesh, materials: [material])
        pathAnchor?.addChild(pathLineEntity!)
    }

    /// Generate mesh for path line
    private func generatePathMesh(from positions: [simd_float3]) -> MeshResource {
        var meshDescriptor = MeshDescriptor()
        var vertices: [simd_float3] = []
        var indices: [UInt32] = []
        let lineWidth: Float = 0.05 // 5cm wide path

        // Generate vertices for path segments
        for i in 0..<positions.count - 1 {
            let start = positions[i]
            let end = positions[i + 1]

            // Calculate perpendicular direction for width
            let direction = simd_normalize(end - start)
            let right = simd_normalize(simd_cross(direction, simd_float3(0, 1, 0))) * lineWidth / 2

            // Add vertices for this segment (quad)
            let baseIndex = UInt32(vertices.count)
            vertices.append(start - right + simd_float3(0, 0.01, 0)) // Left start
            vertices.append(start + right + simd_float3(0, 0.01, 0)) // Right start
            vertices.append(end - right + simd_float3(0, 0.01, 0))   // Left end
            vertices.append(end + right + simd_float3(0, 0.01, 0))   // Right end

            // Add indices for two triangles
            indices.append(contentsOf: [
                baseIndex, baseIndex + 1, baseIndex + 2,
                baseIndex + 1, baseIndex + 3, baseIndex + 2
            ])
        }

        meshDescriptor.positions = MeshBuffer(vertices.map { SIMD3<Float>($0) })
        meshDescriptor.primitives = .triangles(indices)

        return try! MeshResource.generate(from: [meshDescriptor])
    }

    /// Create waypoint markers
    private func createWaypointMarkers(_ waypoints: [PathPlanningEngine.Waypoint]) {
        for (index, waypoint) in waypoints.enumerated() {
            // Skip intermediate non-key waypoints
            if !waypoint.isKeyPoint && index != 0 && index != waypoints.count - 1 {
                continue
            }

            let marker = createWaypointMarker(
                at: waypoint.position,
                isKeyPoint: waypoint.isKeyPoint,
                index: index
            )

            let anchor = AnchorEntity(world: waypoint.position)
            anchor.addChild(marker)
            arView?.scene.addAnchor(anchor)
            waypointAnchors.append(anchor)
        }
    }

    /// Create individual waypoint marker
    private func createWaypointMarker(at position: simd_float3, isKeyPoint: Bool, index: Int) -> ModelEntity {
        let size: Float = isKeyPoint ? 0.15 : 0.1
        let color = isKeyPoint ? UIColor.systemOrange : UIColor.systemBlue

        let mesh = MeshResource.generateSphere(radius: size)
        let material = SimpleMaterial(color: color.withAlphaComponent(0.7), isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Add pulsing animation for key points
        if isKeyPoint {
            addPulsingAnimation(to: entity)
        }

        return entity
    }

    /// Create directional arrows along path
    private func createDirectionalArrows(_ waypoints: [PathPlanningEngine.Waypoint]) {
        let arrowSpacing: Float = 2.0 // Place arrows every 2 meters

        var currentDistance: Float = 0
        var lastArrowDistance: Float = 0

        for i in 0..<waypoints.count - 1 {
            let start = waypoints[i]
            let end = waypoints[i + 1]
            let segmentLength = simd_distance(start.position, end.position)

            // Place arrows along this segment
            while currentDistance < start.distanceFromStart + segmentLength {
                if currentDistance - lastArrowDistance >= arrowSpacing {
                    // Calculate position along segment
                    let t = (currentDistance - start.distanceFromStart) / segmentLength
                    let arrowPosition = simd_mix(start.position, end.position, simd_float3(repeating: t))

                    // Create arrow pointing in direction of travel
                    let arrow = createArrow(
                        at: arrowPosition,
                        direction: simd_normalize(end.position - start.position)
                    )
                    pathAnchor?.addChild(arrow)
                    arrowEntities.append(arrow)

                    lastArrowDistance = currentDistance
                }
                currentDistance += 0.1
            }
        }
    }

    /// Create arrow model
    private func createArrow(at position: simd_float3, direction: simd_float3) -> ModelEntity {
        // Create arrow mesh using box as alternative to cone for iOS 15 compatibility
        let mesh = MeshResource.generateBox(size: simd_float3(0.08, 0.2, 0.08), cornerRadius: 0.02)
        let material = SimpleMaterial(color: pathColor.withAlphaComponent(0.6), isMetallic: false)
        let arrow = ModelEntity(mesh: mesh, materials: [material])

        // Position and orient arrow
        arrow.position = position + simd_float3(0, 0.1, 0) // Slightly above ground

        // Calculate rotation to point in direction
        let forward = simd_float3(0, 0, -1) // Default forward direction
        let rotation = simd_quatf(from: forward, to: direction)
        arrow.orientation = rotation

        // Add floating animation
        addFloatingAnimation(to: arrow)

        return arrow
    }

    /// Create destination marker
    private func createDestinationMarker(at position: simd_float3) {
        // Create a distinctive destination marker using boxes for iOS 15 compatibility
        let baseMesh = MeshResource.generateBox(size: simd_float3(0.5, 0.02, 0.5), cornerRadius: 0.1)
        let baseMaterial = SimpleMaterial(color: .systemRed.withAlphaComponent(0.5), isMetallic: false)
        let baseEntity = ModelEntity(mesh: baseMesh, materials: [baseMaterial])
        baseEntity.position = position + simd_float3(0, 0.01, 0)

        // Create pole using thin box
        let poleMesh = MeshResource.generateBox(size: simd_float3(0.04, 1.0, 0.04), cornerRadius: 0.01)
        let poleMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let poleEntity = ModelEntity(mesh: poleMesh, materials: [poleMaterial])
        poleEntity.position = simd_float3(0, 0.5, 0)
        baseEntity.addChild(poleEntity)

        // Create flag
        let flagMesh = MeshResource.generateBox(width: 0.3, height: 0.2, depth: 0.01)
        let flagMaterial = SimpleMaterial(color: .systemRed, isMetallic: false)
        let flagEntity = ModelEntity(mesh: flagMesh, materials: [flagMaterial])
        flagEntity.position = simd_float3(0.15, 0.9, 0)
        baseEntity.addChild(flagEntity)

        destinationMarker = baseEntity
        pathAnchor?.addChild(destinationMarker!)

        // Add rotation animation to flag
        addRotationAnimation(to: flagEntity)
    }

    // MARK: - Obstacle Visualization

    /// Visualize detected obstacles
    func visualizeObstacles(_ obstacles: [ObstacleMemoryMap.Obstacle]) {
        // Clear existing obstacle visualization
        clearObstacleVisualization()

        for obstacle in obstacles where obstacle.isReliable {
            let obstacleEntity = createObstacleVisualization(obstacle)
            pathAnchor?.addChild(obstacleEntity)
        }
    }

    /// Create obstacle visualization
    private func createObstacleVisualization(_ obstacle: ObstacleMemoryMap.Obstacle) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: obstacle.size)
        let color = obstacleColor(for: obstacle.classification)
        let material = SimpleMaterial(color: color.withAlphaComponent(0.3), isMetallic: false)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = obstacle.position

        return entity
    }

    /// Get color for obstacle type
    private func obstacleColor(for type: ObstacleMemoryMap.ObstacleType) -> UIColor {
        switch type {
        case .wall: return .systemGray
        case .table: return .systemBrown
        case .chair: return .systemOrange
        case .person: return .systemRed
        case .unknown: return .systemPurple
        case .floor: return .systemGray2
        case .ceiling: return .systemGray3
        }
    }

    // MARK: - Animations

    /// Add pulsing animation to entity
    private func addPulsingAnimation(to entity: ModelEntity) {
        let duration: Float = 1.0
        let originalScale = entity.scale

        var transform = entity.transform
        transform.scale = originalScale * 1.2

        entity.move(to: transform, relativeTo: entity.parent, duration: TimeInterval(duration), timingFunction: .easeInOut)

        Timer.scheduledTimer(withTimeInterval: TimeInterval(duration), repeats: true) { _ in
            if entity.scale == originalScale {
                transform.scale = originalScale * 1.2
            } else {
                transform.scale = originalScale
            }
            entity.move(to: transform, relativeTo: entity.parent, duration: TimeInterval(duration), timingFunction: .easeInOut)
        }
    }

    /// Add floating animation to entity
    private func addFloatingAnimation(to entity: ModelEntity) {
        let duration: Float = 2.0
        let originalPosition = entity.position

        Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { _ in
            var transform = entity.transform
            transform.translation = originalPosition + simd_float3(0, 0.05, 0)

            entity.move(to: transform, relativeTo: entity.parent, duration: TimeInterval(duration), timingFunction: .easeInOut)

            Timer.scheduledTimer(withTimeInterval: TimeInterval(duration), repeats: true) { _ in
                if entity.position.y > originalPosition.y {
                    transform.translation = originalPosition
                } else {
                    transform.translation = originalPosition + simd_float3(0, 0.05, 0)
                }
                entity.move(to: transform, relativeTo: entity.parent, duration: TimeInterval(duration), timingFunction: .easeInOut)
            }
        }
    }

    /// Add rotation animation to entity
    private func addRotationAnimation(to entity: ModelEntity) {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            entity.transform.rotation *= simd_quatf(angle: 0.05, axis: simd_float3(0, 1, 0))
        }
    }

    // MARK: - Visibility Control

    /// Set visibility of all visualization elements
    private func setVisualizationVisibility(_ visible: Bool) {
        pathLineEntity?.isEnabled = visible
        destinationMarker?.isEnabled = visible

        for arrow in arrowEntities {
            arrow.isEnabled = visible
        }

        for anchor in waypointAnchors {
            anchor.isEnabled = visible
        }
    }

    /// Clear all visualizations
    func clearVisualization() {
        pathLineEntity?.removeFromParent()
        pathLineEntity = nil

        destinationMarker?.removeFromParent()
        destinationMarker = nil

        for arrow in arrowEntities {
            arrow.removeFromParent()
        }
        arrowEntities.removeAll()

        for anchor in waypointAnchors {
            anchor.removeFromParent()
        }
        waypointAnchors.removeAll()
    }

    /// Clear obstacle visualization
    private func clearObstacleVisualization() {
        // Implementation would clear obstacle-specific entities
    }

    // MARK: - Utility

    /// Update path color
    func updatePathColor(_ color: UIColor) {
        pathColor = color
        // Recreate visualization with new color if path exists
        if let pathLineEntity = pathLineEntity {
            let material = SimpleMaterial(color: color.withAlphaComponent(0.8), isMetallic: false)
            pathLineEntity.model?.materials = [material]
        }
    }
}