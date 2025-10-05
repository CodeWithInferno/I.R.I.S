import Foundation
import simd
import CoreLocation
import Network
import SystemConfiguration.CaptiveNetwork

/// Optimizes memory usage and scanning strategy based on location familiarity
class MemoryOptimizer: ObservableObject {

    // MARK: - Singleton
    static let shared = MemoryOptimizer()

    // MARK: - Properties
    @Published var currentMode: ScanMode = .aggressive
    @Published var batteryUsageRate: Float = 0.05 // 5% per hour default
    @Published var isInKnownLocation = false
    @Published var locationConfidence: Float = 0.0
    @Published var predictedObstacles: [SpatialMemoryDB.CachedObstacle] = []

    private let spatialDB = SpatialMemoryDB.shared
    private var currentLocationId: Int64?
    private var lastFingerprint: SpatialMemoryDB.LocationFingerprint?
    private var scanStartTime = Date()
    private var obstacleBuffer: [(position: simd_float3, size: simd_float3, type: String)] = []
    private let locationManager = CLLocationManager()

    // Scan modes affect battery usage
    enum ScanMode {
        case aggressive  // New location: 60Hz full scan
        case normal     // Semi-familiar: 30Hz partial scan
        case conservative // Very familiar: 15Hz minimal scan
        case predictive  // Known location with patterns: 10Hz verification only

        var scanFrequency: Int {
            switch self {
            case .aggressive: return 60
            case .normal: return 30
            case .conservative: return 15
            case .predictive: return 10
            }
        }

        var scanCoverage: Float {
            switch self {
            case .aggressive: return 1.0    // 100% area scan
            case .normal: return 0.6        // 60% area scan
            case .conservative: return 0.3  // 30% area scan
            case .predictive: return 0.2    // 20% verification scan
            }
        }

        var batteryImpact: Float {
            switch self {
            case .aggressive: return 0.08   // 8% per hour
            case .normal: return 0.05       // 5% per hour
            case .conservative: return 0.03 // 3% per hour
            case .predictive: return 0.02   // 2% per hour
            }
        }
    }

    // MARK: - Initialization

    private init() {
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
    }

    // MARK: - Public API

    /// Generate fingerprint for current location
    func generateFingerprint(
        obstacles: [(position: simd_float3, size: simd_float3, type: String)],
        roomBounds: (min: simd_float3, max: simd_float3)?
    ) -> SpatialMemoryDB.LocationFingerprint {

        // Extract dominant obstacles (largest 10)
        let sortedObstacles = obstacles.sorted { obs1, obs2 in
            let volume1 = obs1.size.x * obs1.size.y * obs1.size.z
            let volume2 = obs2.size.x * obs2.size.y * obs2.size.z
            return volume1 > volume2
        }

        let dominantObstacles = Array(sortedObstacles.prefix(10)).map { $0.position }

        // Calculate room dimensions
        let roomDimensions: simd_float3
        if let bounds = roomBounds {
            roomDimensions = bounds.max - bounds.min
        } else {
            // Estimate from obstacle spread
            let positions = obstacles.map { $0.position }
            let minPos = positions.reduce(simd_float3(Float.infinity, Float.infinity, Float.infinity)) { simd_min($0, $1) }
            let maxPos = positions.reduce(simd_float3(-Float.infinity, -Float.infinity, -Float.infinity)) { simd_max($0, $1) }
            roomDimensions = maxPos - minPos
        }

        // Count corners (simplified - obstacles near room edges)
        let cornerThreshold: Float = 1.5
        let corners = obstacles.filter { obs in
            let pos = obs.position
            let nearEdgeX = abs(pos.x - roomDimensions.x/2) > (roomDimensions.x/2 - cornerThreshold)
            let nearEdgeZ = abs(pos.z - roomDimensions.z/2) > (roomDimensions.z/2 - cornerThreshold)
            return nearEdgeX && nearEdgeZ
        }.count

        // Get WiFi signatures
        let wifiSignatures = getCurrentWiFiSSIDs()

        // Get magnetic field (simplified)
        let magneticSignature: Float? = nil // Would use Core Motion in production

        return SpatialMemoryDB.LocationFingerprint(
            dominantObstacles: dominantObstacles,
            roomDimensions: roomDimensions,
            cornerCount: corners,
            obstacleCount: obstacles.count,
            wifiSignatures: Set(wifiSignatures),
            magneticSignature: magneticSignature
        )
    }

    /// Check if we're in a known location and adjust scan strategy
    func checkLocation(
        obstacles: [(position: simd_float3, size: simd_float3, type: String)],
        roomBounds: (min: simd_float3, max: simd_float3)?
    ) {
        let fingerprint = generateFingerprint(obstacles: obstacles, roomBounds: roomBounds)
        lastFingerprint = fingerprint

        // Check database for matching location
        if let knownLocation = spatialDB.findMatchingLocation(fingerprint: fingerprint, threshold: 0.75) {
            // We're in a known location!
            currentLocationId = knownLocation.id
            isInKnownLocation = true
            locationConfidence = knownLocation.confidence

            // Adjust scan mode based on familiarity
            if knownLocation.visitCount > 20 && knownLocation.confidence > 0.9 {
                currentMode = .predictive
                batteryUsageRate = ScanMode.predictive.batteryImpact

                // Load predicted obstacles
                if let predicted = spatialDB.getPredictedLayout(for: knownLocation.id) {
                    predictedObstacles = predicted
                }
            } else if knownLocation.visitCount > 10 {
                currentMode = .conservative
                batteryUsageRate = ScanMode.conservative.batteryImpact
            } else if knownLocation.visitCount > 5 {
                currentMode = .normal
                batteryUsageRate = ScanMode.normal.batteryImpact
            } else {
                currentMode = .aggressive
                batteryUsageRate = ScanMode.aggressive.batteryImpact
            }

            print("📍 Recognized location: \(knownLocation.name ?? "Unknown") - Visit #\(knownLocation.visitCount)")
            print("🔋 Battery mode: \(currentMode) - \(batteryUsageRate * 100)% per hour")
        } else {
            // New location
            currentLocationId = nil
            isInKnownLocation = false
            locationConfidence = 0.0
            currentMode = .aggressive
            batteryUsageRate = ScanMode.aggressive.batteryImpact
            predictedObstacles = []

            print("📍 New location detected - aggressive scanning")
        }
    }

    /// Save current scan data to database
    func saveCurrentLocation(
        obstacles: [(position: simd_float3, size: simd_float3, type: String)],
        name: String? = nil
    ) {
        guard let fingerprint = lastFingerprint else { return }

        let locationId = spatialDB.saveLocation(
            fingerprint: fingerprint,
            obstacles: obstacles,
            name: name
        )

        currentLocationId = locationId
        print("💾 Location saved to database (ID: \(locationId))")
    }

    /// Record successful navigation path
    func saveNavigationPath(waypoints: [simd_float3]) {
        guard let locationId = currentLocationId else { return }

        let traversalTime = Date().timeIntervalSince(scanStartTime)
        spatialDB.savePath(locationId: locationId, waypoints: waypoints, traversalTime: traversalTime)

        print("🗺 Navigation path saved (\(waypoints.count) waypoints)")
    }

    /// Get optimized scan parameters
    func getOptimizedScanParameters() -> (frequency: Int, coverage: Float, skipAreas: [simd_float3]) {
        var skipAreas: [simd_float3] = []

        // In predictive mode, skip areas with permanent obstacles
        if currentMode == .predictive {
            skipAreas = predictedObstacles
                .filter { $0.permanence > 0.9 }
                .map { $0.position }
        }

        return (
            frequency: currentMode.scanFrequency,
            coverage: currentMode.scanCoverage,
            skipAreas: skipAreas
        )
    }

    /// Should we do a full scan or use cached data?
    func shouldUseCache(for position: simd_float3) -> Bool {
        guard isInKnownLocation,
              currentMode == .predictive || currentMode == .conservative else {
            return false
        }

        // Check if we have recent cached data for this position
        let cacheAge = Date().timeIntervalSince(scanStartTime)

        // Use cache if we're in a very familiar location and cache is fresh
        if currentMode == .predictive && cacheAge < 60 {
            return true
        }

        // In conservative mode, use cache for static obstacles
        if currentMode == .conservative && cacheAge < 30 {
            // Only use cache for high-permanence obstacles
            return predictedObstacles.contains { obstacle in
                obstacle.permanence > 0.8 &&
                simd_distance(obstacle.position, position) < 3.0
            }
        }

        return false
    }

    /// Merge cached obstacles with live scan
    func mergeWithCache(
        liveObstacles: [(position: simd_float3, size: simd_float3, type: String)]
    ) -> [(position: simd_float3, size: simd_float3, type: String)] {

        guard !predictedObstacles.isEmpty else {
            return liveObstacles
        }

        var merged = liveObstacles

        // Add high-confidence cached obstacles not seen in live scan
        for cached in predictedObstacles where cached.permanence > 0.7 {
            let existsInLive = liveObstacles.contains { live in
                simd_distance(live.position, cached.position) < 0.5
            }

            if !existsInLive {
                merged.append((
                    position: cached.position,
                    size: cached.size,
                    type: cached.type
                ))
            }
        }

        return merged
    }

    /// Get memory statistics
    func getMemoryStats() -> String {
        let stats = spatialDB.getMemoryStats()

        return """
        📊 Memory Statistics:
        Locations: \(stats.locationCount)
        Obstacles: \(stats.totalObstacles)
        Storage: \(formatBytes(stats.storageSize))
        Mode: \(currentMode)
        Battery: \(batteryUsageRate * 100)% per hour
        """
    }

    /// Clean up old data
    func performMaintenance() {
        spatialDB.cleanupOldLocations(olderThan: 30)
        print("🧹 Database maintenance completed")
    }

    // MARK: - Private Methods

    private func getCurrentWiFiSSIDs() -> [String] {
        var ssids: [String] = []

        #if !targetEnvironment(simulator)
        if let interfaces = CNCopySupportedInterfaces() as NSArray? {
            for interface in interfaces {
                if let interfaceInfo = CNCopyCurrentNetworkInfo(interface as! CFString) as NSDictionary?,
                   let ssid = interfaceInfo[kCNNetworkInfoKeySSID as String] as? String {
                    ssids.append(ssid)
                }
            }
        }
        #endif

        return ssids
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Scan Strategy Optimization

    /// Dynamically adjust scan strategy based on movement and obstacles
    func adaptScanStrategy(
        userSpeed: Float,
        obstacleProximity: Float,
        pathComplexity: Float
    ) {
        // Fast movement or close obstacles require more aggressive scanning
        if userSpeed > 1.5 || obstacleProximity < 0.5 {
            if currentMode != .aggressive {
                currentMode = .normal
                print("⚡ Increased scan rate due to fast movement/close obstacles")
            }
            return
        }

        // In known locations with clear paths, reduce scanning
        if isInKnownLocation && pathComplexity < 0.3 && obstacleProximity > 2.0 {
            if currentMode == .normal || currentMode == .aggressive {
                currentMode = .conservative
                print("🔋 Reduced scan rate - clear familiar path")
            }
        }
    }

    /// Predict user's destination based on history
    func predictDestination(currentPosition: simd_float3, heading: simd_float3) -> simd_float3? {
        guard let locationId = currentLocationId,
              let location = spatialDB.findMatchingLocation(fingerprint: lastFingerprint ?? SpatialMemoryDB.LocationFingerprint(
                dominantObstacles: [],
                roomDimensions: simd_float3(0, 0, 0),
                cornerCount: 0,
                obstacleCount: 0,
                wifiSignatures: Set(),
                magneticSignature: nil
              )) else {
            return nil
        }

        // Find paths that start near current position
        for path in location.commonPaths {
            if let firstWaypoint = path.waypoints.first,
               simd_distance(firstWaypoint, currentPosition) < 1.0 {

                // Check if user is heading in the right direction
                if let secondWaypoint = path.waypoints.dropFirst().first {
                    let pathDirection = simd_normalize(secondWaypoint - firstWaypoint)
                    let dotProduct = simd_dot(pathDirection, heading)

                    if dotProduct > 0.7 {  // Heading in similar direction
                        return path.waypoints.last
                    }
                }
            }
        }

        return nil
    }
}