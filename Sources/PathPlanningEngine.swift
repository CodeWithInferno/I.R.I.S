import Foundation
import simd
import Combine

/// A* pathfinding engine for real-time navigation around obstacles
class PathPlanningEngine: ObservableObject {

    // MARK: - Types

    /// Node in the pathfinding graph
    struct PathNode: Equatable, Hashable {
        let position: simd_float3
        var gCost: Float = Float.infinity // Cost from start
        var hCost: Float = 0 // Heuristic cost to goal
        var parent: simd_float3?

        var fCost: Float {
            gCost + hCost
        }

        static func == (lhs: PathNode, rhs: PathNode) -> Bool {
            simd_equal(lhs.position, rhs.position)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(position.x)
            hasher.combine(position.y)
            hasher.combine(position.z)
        }
    }

    /// Waypoint in the planned path
    struct Waypoint {
        let position: simd_float3
        let direction: simd_float3
        let distanceFromStart: Float
        let isKeyPoint: Bool // Important turn or decision point
    }

    /// Navigation instruction
    struct NavigationInstruction {
        enum Action {
            case goStraight(meters: Float)
            case turnLeft(degrees: Float)
            case turnRight(degrees: Float)
            case stop
            case avoid(obstacle: String)
        }

        let action: Action
        let position: simd_float3
        let distance: Float
    }

    // MARK: - Properties

    @Published var currentPath: [Waypoint] = []
    @Published var navigationInstructions: [NavigationInstruction] = []
    @Published var isPlanning = false
    @Published var pathStatus: PathStatus = .idle
    @Published var nextWaypoint: Waypoint?

    private let gridResolution: Float = 0.25 // 25cm grid cells
    private let maxSearchNodes = 1000
    private let planningQueue = DispatchQueue(label: "path.planning.queue", qos: .userInitiated)
    private var planningCancellable: AnyCancellable?

    enum PathStatus {
        case idle
        case planning
        case pathFound
        case noPathAvailable
        case recalculating
    }

    // MARK: - Public Methods

    /// Plan path from start to goal avoiding obstacles
    func planPath(
        from start: simd_float3,
        to goal: simd_float3,
        obstacles: [ObstacleMemoryMap.Obstacle],
        userHeading: simd_float3? = nil
    ) {
        // Cancel any existing planning
        planningCancellable?.cancel()

        DispatchQueue.main.async {
            self.isPlanning = true
            self.pathStatus = .planning
        }

        planningQueue.async { [weak self] in
            guard let self = self else { return }

            // Run A* algorithm
            let path = self.findPath(
                start: start,
                goal: goal,
                obstacles: obstacles,
                userHeading: userHeading
            )

            DispatchQueue.main.async {
                self.isPlanning = false

                if let path = path, !path.isEmpty {
                    self.currentPath = path
                    self.navigationInstructions = self.generateInstructions(from: path)
                    self.nextWaypoint = path.first
                    self.pathStatus = .pathFound
                } else {
                    self.currentPath = []
                    self.navigationInstructions = []
                    self.nextWaypoint = nil
                    self.pathStatus = .noPathAvailable
                }
            }
        }
    }

    /// Update user position and check if replanning is needed
    func updateUserPosition(
        _ position: simd_float3,
        heading: simd_float3,
        obstacles: [ObstacleMemoryMap.Obstacle]
    ) {
        guard !currentPath.isEmpty else { return }

        // Check if user has reached the next waypoint
        if let nextWaypoint = nextWaypoint,
           simd_distance(position, nextWaypoint.position) < 0.5 {
            advanceToNextWaypoint()
        }

        // Check if user has deviated from path
        let distanceFromPath = distanceToPath(position: position)
        if distanceFromPath > 1.0 {
            // User has deviated significantly, replan
            if let lastWaypoint = currentPath.last {
                pathStatus = .recalculating
                planPath(from: position, to: lastWaypoint.position, obstacles: obstacles, userHeading: heading)
            }
        }

        // Check if any new obstacles block the path
        if isPathBlocked(by: obstacles) {
            // Path is blocked, replan
            if let lastWaypoint = currentPath.last {
                pathStatus = .recalculating
                planPath(from: position, to: lastWaypoint.position, obstacles: obstacles, userHeading: heading)
            }
        }
    }

    // MARK: - A* Algorithm Implementation

    private func findPath(
        start: simd_float3,
        goal: simd_float3,
        obstacles: [ObstacleMemoryMap.Obstacle],
        userHeading: simd_float3?
    ) -> [Waypoint]? {

        // Quantize positions to grid
        let startPos = quantizePosition(start)
        let goalPos = quantizePosition(goal)

        // Initialize nodes
        var openSet = Set<PathNode>()
        var closedSet = Set<simd_float3>()
        var nodeMap: [simd_float3: PathNode] = [:]

        // Create start node
        var startNode = PathNode(position: startPos)
        startNode.gCost = 0
        startNode.hCost = heuristic(startPos, goalPos)
        openSet.insert(startNode)
        nodeMap[startPos] = startNode

        var nodesExplored = 0

        // A* main loop
        while !openSet.isEmpty && nodesExplored < maxSearchNodes {
            // Get node with lowest fCost
            guard let current = openSet.min(by: { $0.fCost < $1.fCost }) else { break }

            // Remove from open set
            openSet.remove(current)
            closedSet.insert(current.position)
            nodesExplored += 1

            // Check if we reached the goal
            if simd_distance(current.position, goalPos) < gridResolution {
                return reconstructPath(from: nodeMap, endNode: current)
            }

            // Explore neighbors
            let neighbors = getNeighbors(of: current.position)

            for neighborPos in neighbors {
                // Skip if in closed set
                if closedSet.contains(neighborPos) {
                    continue
                }

                // Check if position is blocked by obstacle
                if isBlocked(position: neighborPos, obstacles: obstacles) {
                    closedSet.insert(neighborPos)
                    continue
                }

                // Calculate tentative gCost
                let movementCost = simd_distance(current.position, neighborPos)
                let tentativeGCost = current.gCost + movementCost

                // Get or create neighbor node
                var neighbor = nodeMap[neighborPos] ?? PathNode(position: neighborPos)

                if tentativeGCost < neighbor.gCost {
                    // This path is better
                    neighbor.gCost = tentativeGCost
                    neighbor.hCost = heuristic(neighborPos, goalPos)
                    neighbor.parent = current.position
                    nodeMap[neighborPos] = neighbor

                    // Add to open set if not already there
                    if !openSet.contains(neighbor) {
                        openSet.insert(neighbor)
                    }
                }
            }
        }

        // No path found
        return nil
    }

    /// Reconstruct path from node map
    private func reconstructPath(from nodeMap: [simd_float3: PathNode], endNode: PathNode) -> [Waypoint] {
        var path: [simd_float3] = []
        var current = endNode

        // Trace back from goal to start
        while let parent = current.parent {
            path.append(current.position)
            guard let parentNode = nodeMap[parent] else { break }
            current = parentNode
        }
        path.append(current.position)

        path.reverse()

        // Smooth and convert to waypoints
        let smoothedPath = smoothPath(path)
        return createWaypoints(from: smoothedPath)
    }

    /// Smooth path using line-of-sight optimization
    private func smoothPath(_ path: [simd_float3]) -> [simd_float3] {
        guard path.count > 2 else { return path }

        var smoothed: [simd_float3] = [path[0]]
        var currentIndex = 0

        while currentIndex < path.count - 1 {
            var furthestVisible = currentIndex + 1

            // Find furthest visible point
            for i in (currentIndex + 2)..<path.count {
                if hasLineOfSight(from: path[currentIndex], to: path[i]) {
                    furthestVisible = i
                } else {
                    break
                }
            }

            smoothed.append(path[furthestVisible])
            currentIndex = furthestVisible
        }

        return smoothed
    }

    /// Create waypoints with metadata
    private func createWaypoints(from path: [simd_float3]) -> [Waypoint] {
        var waypoints: [Waypoint] = []
        var totalDistance: Float = 0

        for i in 0..<path.count {
            let position = path[i]
            var direction = simd_float3(0, 0, 1) // Default forward

            if i < path.count - 1 {
                direction = simd_normalize(path[i + 1] - position)
            } else if i > 0 {
                direction = simd_normalize(position - path[i - 1])
            }

            if i > 0 {
                totalDistance += simd_distance(path[i - 1], position)
            }

            // Mark as key point if there's a significant direction change
            var isKeyPoint = false
            if i > 0 && i < path.count - 1 {
                let prevDir = simd_normalize(position - path[i - 1])
                let nextDir = simd_normalize(path[i + 1] - position)
                let angle = acos(simd_dot(prevDir, nextDir))
                isKeyPoint = angle > Float.pi / 6 // 30 degrees
            }

            waypoints.append(Waypoint(
                position: position,
                direction: direction,
                distanceFromStart: totalDistance,
                isKeyPoint: isKeyPoint || i == 0 || i == path.count - 1
            ))
        }

        return waypoints
    }

    // MARK: - Helper Methods

    /// Quantize position to grid
    private func quantizePosition(_ position: simd_float3) -> simd_float3 {
        return simd_float3(
            round(position.x / gridResolution) * gridResolution,
            position.y, // Keep Y unchanged for elevation
            round(position.z / gridResolution) * gridResolution
        )
    }

    /// Get neighbor positions
    private func getNeighbors(of position: simd_float3) -> [simd_float3] {
        var neighbors: [simd_float3] = []

        // 8-directional movement on XZ plane
        let offsets: [(Float, Float)] = [
            (1, 0), (-1, 0), (0, 1), (0, -1),  // Cardinal
            (1, 1), (1, -1), (-1, 1), (-1, -1) // Diagonal
        ]

        for (dx, dz) in offsets {
            let neighbor = simd_float3(
                position.x + dx * gridResolution,
                position.y,
                position.z + dz * gridResolution
            )
            neighbors.append(neighbor)
        }

        return neighbors
    }

    /// Heuristic function for A* (Euclidean distance)
    private func heuristic(_ a: simd_float3, _ b: simd_float3) -> Float {
        return simd_distance(a, b)
    }

    /// Check if position is blocked by obstacles
    private func isBlocked(position: simd_float3, obstacles: [ObstacleMemoryMap.Obstacle]) -> Bool {
        let safetyMargin: Float = 0.4 // 40cm safety margin

        for obstacle in obstacles {
            if simd_distance(position, obstacle.position) < (safetyMargin + obstacle.size.x / 2) {
                return true
            }
        }
        return false
    }

    /// Check line of sight between two points
    private func hasLineOfSight(from: simd_float3, to: simd_float3) -> Bool {
        // Simplified line of sight check
        // In production, would ray cast against obstacle map
        return true
    }

    /// Calculate distance from position to path
    private func distanceToPath(position: simd_float3) -> Float {
        guard currentPath.count >= 2 else { return 0 }

        var minDistance = Float.infinity

        for i in 0..<(currentPath.count - 1) {
            let segmentStart = currentPath[i].position
            let segmentEnd = currentPath[i + 1].position
            let distance = distanceToLineSegment(
                point: position,
                lineStart: segmentStart,
                lineEnd: segmentEnd
            )
            minDistance = min(minDistance, distance)
        }

        return minDistance
    }

    /// Calculate distance from point to line segment
    private func distanceToLineSegment(point: simd_float3, lineStart: simd_float3, lineEnd: simd_float3) -> Float {
        let lineVec = lineEnd - lineStart
        let pointVec = point - lineStart
        let lineLength = simd_length(lineVec)

        if lineLength == 0 {
            return simd_distance(point, lineStart)
        }

        let t = max(0, min(1, simd_dot(pointVec, lineVec) / (lineLength * lineLength)))
        let projection = lineStart + t * lineVec
        return simd_distance(point, projection)
    }

    /// Check if path is blocked by new obstacles
    private func isPathBlocked(by obstacles: [ObstacleMemoryMap.Obstacle]) -> Bool {
        for waypoint in currentPath {
            if isBlocked(position: waypoint.position, obstacles: obstacles) {
                return true
            }
        }
        return false
    }

    /// Advance to next waypoint
    private func advanceToNextWaypoint() {
        guard !currentPath.isEmpty else { return }
        currentPath.removeFirst()
        nextWaypoint = currentPath.first
    }

    /// Generate turn-by-turn navigation instructions
    private func generateInstructions(from waypoints: [Waypoint]) -> [NavigationInstruction] {
        var instructions: [NavigationInstruction] = []

        for i in 0..<waypoints.count {
            let waypoint = waypoints[i]

            if i == 0 {
                // Start instruction
                if waypoints.count > 1 {
                    let distance = simd_distance(waypoint.position, waypoints[1].position)
                    instructions.append(NavigationInstruction(
                        action: .goStraight(meters: distance),
                        position: waypoint.position,
                        distance: 0
                    ))
                }
            } else if i == waypoints.count - 1 {
                // Destination reached
                instructions.append(NavigationInstruction(
                    action: .stop,
                    position: waypoint.position,
                    distance: waypoint.distanceFromStart
                ))
            } else if waypoint.isKeyPoint {
                // Turn instruction
                let prevDir = simd_normalize(waypoint.position - waypoints[i - 1].position)
                let nextDir = simd_normalize(waypoints[i + 1].position - waypoint.position)

                let cross = simd_cross(prevDir, nextDir)
                let angle = acos(simd_dot(prevDir, nextDir)) * (180 / Float.pi)

                if cross.y > 0 {
                    instructions.append(NavigationInstruction(
                        action: .turnLeft(degrees: angle),
                        position: waypoint.position,
                        distance: waypoint.distanceFromStart
                    ))
                } else {
                    instructions.append(NavigationInstruction(
                        action: .turnRight(degrees: angle),
                        position: waypoint.position,
                        distance: waypoint.distanceFromStart
                    ))
                }

                // Add straight after turn
                if i + 1 < waypoints.count {
                    let distance = simd_distance(waypoint.position, waypoints[i + 1].position)
                    instructions.append(NavigationInstruction(
                        action: .goStraight(meters: distance),
                        position: waypoint.position,
                        distance: waypoint.distanceFromStart
                    ))
                }
            }
        }

        return instructions
    }

    /// Clear current path
    func clearPath() {
        currentPath = []
        navigationInstructions = []
        nextWaypoint = nil
        pathStatus = .idle
    }
}