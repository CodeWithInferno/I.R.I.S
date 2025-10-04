import Foundation
import simd
import ARKit

/// Stores and manages spatial memory of detected obstacles
class ObstacleMemoryMap: ObservableObject {

    // MARK: - Types

    /// Represents a single obstacle in 3D space
    struct Obstacle: Identifiable {
        let id = UUID()
        var position: simd_float3
        var size: simd_float3
        var confidence: Float
        var lastSeen: Date
        var classification: ObstacleType
        var updateCount: Int = 1

        /// Calculate age of obstacle detection
        var age: TimeInterval {
            Date().timeIntervalSince(lastSeen)
        }

        /// Check if obstacle should be forgotten
        var isStale: Bool {
            age > 30.0 // Forget after 30 seconds
        }

        /// Check if obstacle is reliable
        var isReliable: Bool {
            confidence > 0.6 && updateCount > 3
        }
    }

    enum ObstacleType: String, CaseIterable {
        case wall = "Wall"
        case table = "Table"
        case chair = "Chair"
        case person = "Person"
        case unknown = "Unknown"
        case floor = "Floor"
        case ceiling = "Ceiling"

        var priority: Int {
            switch self {
            case .person: return 10 // Highest priority
            case .table, .chair: return 8
            case .wall: return 6
            case .unknown: return 5
            case .floor, .ceiling: return 1 // Lowest priority
            }
        }
    }

    /// Voxel grid for efficient spatial queries
    struct VoxelGrid {
        let resolution: Float = 0.5 // 0.5 meter voxels
        private var voxels: [simd_int3: Set<UUID>] = [:]

        mutating func insert(obstacleId: UUID, at position: simd_float3) {
            let voxelCoord = getVoxelCoordinate(for: position)
            voxels[voxelCoord, default: []].insert(obstacleId)
        }

        mutating func remove(obstacleId: UUID, from position: simd_float3) {
            let voxelCoord = getVoxelCoordinate(for: position)
            voxels[voxelCoord]?.remove(obstacleId)
            if voxels[voxelCoord]?.isEmpty == true {
                voxels.removeValue(forKey: voxelCoord)
            }
        }

        func getObstacleIds(at position: simd_float3) -> Set<UUID> {
            let voxelCoord = getVoxelCoordinate(for: position)
            return voxels[voxelCoord] ?? []
        }

        func getObstacleIds(near position: simd_float3, radius: Float) -> Set<UUID> {
            var allIds = Set<UUID>()
            let radiusInVoxels = Int(ceil(radius / resolution))

            let centerVoxel = getVoxelCoordinate(for: position)

            for x in -radiusInVoxels...radiusInVoxels {
                for y in -radiusInVoxels...radiusInVoxels {
                    for z in -radiusInVoxels...radiusInVoxels {
                        let voxelCoord = simd_int3(
                            centerVoxel.x + Int32(x),
                            centerVoxel.y + Int32(y),
                            centerVoxel.z + Int32(z)
                        )
                        if let ids = voxels[voxelCoord] {
                            allIds.formUnion(ids)
                        }
                    }
                }
            }

            return allIds
        }

        private func getVoxelCoordinate(for position: simd_float3) -> simd_int3 {
            return simd_int3(
                Int32(floor(position.x / resolution)),
                Int32(floor(position.y / resolution)),
                Int32(floor(position.z / resolution))
            )
        }

        mutating func clear() {
            voxels.removeAll()
        }
    }

    // MARK: - Properties

    @Published private(set) var obstacles: [UUID: Obstacle] = [:]
    private var voxelGrid = VoxelGrid()
    private let updateQueue = DispatchQueue(label: "obstacle.map.queue", attributes: .concurrent)
    private let cleanupInterval: TimeInterval = 5.0
    private var cleanupTimer: Timer?

    // Statistics
    @Published var totalObstaclesDetected = 0
    @Published var activeObstacles = 0

    // MARK: - Initialization

    init() {
        startCleanupTimer()
    }

    // MARK: - Obstacle Management

    /// Add or update an obstacle in the map
    func addOrUpdateObstacle(
        position: simd_float3,
        size: simd_float3,
        confidence: Float,
        classification: ObstacleType = .unknown
    ) {
        updateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Check if there's an existing obstacle nearby
            let nearbyIds = self.voxelGrid.getObstacleIds(near: position, radius: 0.3)

            var updated = false
            for id in nearbyIds {
                if let existingObstacle = self.obstacles[id],
                   simd_distance(existingObstacle.position, position) < 0.3 {
                    // Update existing obstacle
                    self.updateExistingObstacle(id: id, position: position, confidence: confidence)
                    updated = true
                    break
                }
            }

            if !updated {
                // Add new obstacle
                self.addNewObstacle(
                    position: position,
                    size: size,
                    confidence: confidence,
                    classification: classification
                )
            }

            DispatchQueue.main.async {
                self.activeObstacles = self.obstacles.filter { !$0.value.isStale }.count
            }
        }
    }

    private func addNewObstacle(
        position: simd_float3,
        size: simd_float3,
        confidence: Float,
        classification: ObstacleType
    ) {
        let obstacle = Obstacle(
            position: position,
            size: size,
            confidence: confidence,
            lastSeen: Date(),
            classification: classification
        )

        obstacles[obstacle.id] = obstacle
        voxelGrid.insert(obstacleId: obstacle.id, at: position)

        DispatchQueue.main.async {
            self.totalObstaclesDetected += 1
        }
    }

    private func updateExistingObstacle(id: UUID, position: simd_float3, confidence: Float) {
        guard var obstacle = obstacles[id] else { return }

        // Remove from old voxel
        voxelGrid.remove(obstacleId: id, from: obstacle.position)

        // Update with weighted average position
        let weight = Float(obstacle.updateCount) / Float(obstacle.updateCount + 1)
        obstacle.position = obstacle.position * weight + position * (1.0 - weight)
        obstacle.confidence = max(obstacle.confidence, confidence)
        obstacle.lastSeen = Date()
        obstacle.updateCount += 1

        // Add to new voxel
        voxelGrid.insert(obstacleId: id, at: obstacle.position)
        obstacles[id] = obstacle
    }

    /// Get obstacles near a specific position
    func getObstacles(near position: simd_float3, radius: Float) -> [Obstacle] {
        var result: [Obstacle] = []

        updateQueue.sync {
            let nearbyIds = voxelGrid.getObstacleIds(near: position, radius: radius)
            for id in nearbyIds {
                if let obstacle = obstacles[id],
                   !obstacle.isStale,
                   simd_distance(obstacle.position, position) <= radius {
                    result.append(obstacle)
                }
            }
        }

        // Sort by distance and priority
        return result.sorted { first, second in
            let dist1 = simd_distance(first.position, position)
            let dist2 = simd_distance(second.position, position)

            if abs(dist1 - dist2) < 0.1 {
                // If distances are similar, sort by priority
                return first.classification.priority > second.classification.priority
            }
            return dist1 < dist2
        }
    }

    /// Check if position is occupied by an obstacle
    func isOccupied(position: simd_float3, tolerance: Float = 0.3) -> Bool {
        return updateQueue.sync {
            let nearbyIds = voxelGrid.getObstacleIds(near: position, radius: tolerance)
            for id in nearbyIds {
                if let obstacle = obstacles[id],
                   !obstacle.isStale,
                   simd_distance(obstacle.position, position) <= tolerance {
                    return true
                }
            }
            return false
        }
    }

    /// Get all reliable obstacles for path planning
    func getReliableObstacles() -> [Obstacle] {
        return updateQueue.sync {
            obstacles.values.filter { $0.isReliable && !$0.isStale }
        }
    }

    /// Convert ARMeshAnchor classification to ObstacleType
    func classifyFromARMesh(_ classification: ARMeshClassification) -> ObstacleType {
        switch classification {
        case .wall, .window, .door:
            return .wall
        case .table:
            return .table
        case .seat:
            return .chair
        case .floor:
            return .floor
        case .ceiling:
            return .ceiling
        case .none:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            self?.cleanupStaleObstacles()
        }
    }

    private func cleanupStaleObstacles() {
        updateQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let staleIds = self.obstacles.compactMap { (id, obstacle) in
                obstacle.isStale ? id : nil
            }

            for id in staleIds {
                if let obstacle = self.obstacles[id] {
                    self.voxelGrid.remove(obstacleId: id, from: obstacle.position)
                    self.obstacles.removeValue(forKey: id)
                }
            }

            if !staleIds.isEmpty {
                DispatchQueue.main.async {
                    self.activeObstacles = self.obstacles.count
                }
            }
        }
    }

    /// Clear all obstacles
    func clearAll() {
        updateQueue.async(flags: .barrier) { [weak self] in
            self?.obstacles.removeAll()
            self?.voxelGrid.clear()

            DispatchQueue.main.async {
                self?.activeObstacles = 0
            }
        }
    }

    /// Export obstacle map for debugging
    func exportMap() -> [[String: Any]] {
        return updateQueue.sync {
            obstacles.values.map { obstacle in
                [
                    "id": obstacle.id.uuidString,
                    "position": [obstacle.position.x, obstacle.position.y, obstacle.position.z],
                    "size": [obstacle.size.x, obstacle.size.y, obstacle.size.z],
                    "type": obstacle.classification.rawValue,
                    "confidence": obstacle.confidence,
                    "age": obstacle.age,
                    "reliable": obstacle.isReliable
                ]
            }
        }
    }

    deinit {
        cleanupTimer?.invalidate()
    }
}