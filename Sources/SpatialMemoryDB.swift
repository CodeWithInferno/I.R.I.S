import Foundation
import SQLite3
import CoreLocation
import simd
import CryptoKit

/// Intelligent spatial memory database for location learning and pattern recognition
class SpatialMemoryDB {

    // MARK: - Singleton
    static let shared = SpatialMemoryDB()

    // MARK: - Properties
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "spatial.memory.db", attributes: .concurrent)
    private var memoryCache = [String: LocationMemory]()
    private let maxCacheSize = 3 // Keep 3 locations in RAM

    // MARK: - Data Models

    struct LocationMemory {
        let id: Int64
        let fingerprint: String
        let name: String?
        var visitCount: Int
        var lastVisit: Date
        var obstacles: [CachedObstacle]
        var patterns: [TemporalPattern]
        var commonPaths: [SavedPath]
        var averageScanTime: TimeInterval
        var confidence: Float

        var isFrequent: Bool {
            visitCount > 5
        }

        var isFresh: Bool {
            Date().timeIntervalSince(lastVisit) < 3600 // Visited within last hour
        }
    }

    public struct CachedObstacle {
        public let x: Float
        public let y: Float
        public let z: Float
        public let width: Float
        public let height: Float
        public let depth: Float
        public let type: String
        public let permanence: Float // 0.0 = always moves, 1.0 = never moves
        public let lastSeen: Date

        public var position: simd_float3 {
            simd_float3(x, y, z)
        }

        public var size: simd_float3 {
            simd_float3(width, height, depth)
        }
    }

    struct TemporalPattern {
        let dayOfWeek: Int // 1 = Sunday, 7 = Saturday
        let hourOfDay: Int // 0-23
        let changeType: String // "added", "removed", "moved"
        let affectedArea: simd_float3 // Center of change
        let radius: Float // Radius of change
        let confidence: Float

        func matches(date: Date = Date()) -> Bool {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.weekday, .hour], from: date)

            let currentDay = components.weekday ?? 0
            let currentHour = components.hour ?? 0

            // Match within 1 hour window
            return currentDay == dayOfWeek &&
                   abs(currentHour - hourOfDay) <= 1
        }
    }

    struct SavedPath {
        let waypoints: [simd_float3]
        let usageCount: Int
        let averageTraversalTime: TimeInterval
        let successRate: Float
    }

    struct LocationFingerprint {
        let dominantObstacles: [simd_float3] // Top 10 largest obstacles
        let roomDimensions: simd_float3 // Approximate width, height, depth
        let cornerCount: Int
        let obstacleCount: Int
        let wifiSignatures: Set<String> // BSSIDs if available
        let magneticSignature: Float? // Magnetic field strength

        func hash() -> String {
            var hasher = SHA256()

            // Hash dominant obstacles
            for obstacle in dominantObstacles {
                hasher.update(data: obstacle.x.bitPattern.data)
                hasher.update(data: obstacle.y.bitPattern.data)
                hasher.update(data: obstacle.z.bitPattern.data)
            }

            // Hash room characteristics
            hasher.update(data: roomDimensions.x.bitPattern.data)
            hasher.update(data: cornerCount.data)
            hasher.update(data: obstacleCount.data)

            // Hash WiFi if available
            for wifi in wifiSignatures.sorted() {
                hasher.update(data: wifi.data(using: .utf8) ?? Data())
            }

            let digest = hasher.finalize()
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        }

        func similarity(to other: LocationFingerprint) -> Float {
            var score: Float = 0.0
            var factors = 0

            // Compare dominant obstacles
            let commonObstacles = dominantObstacles.filter { obstacle in
                other.dominantObstacles.contains { other in
                    simd_distance(obstacle, other) < 0.5
                }
            }
            score += Float(commonObstacles.count) / Float(max(dominantObstacles.count, 1))
            factors += 1

            // Compare room dimensions
            let dimSimilarity = 1.0 - (simd_distance(roomDimensions, other.roomDimensions) / 10.0)
            score += max(0, dimSimilarity)
            factors += 1

            // Compare corner count
            let cornerSimilarity = 1.0 - (Float(abs(cornerCount - other.cornerCount)) / 10.0)
            score += max(0, cornerSimilarity)
            factors += 1

            // Compare WiFi signatures
            if !wifiSignatures.isEmpty && !other.wifiSignatures.isEmpty {
                let common = wifiSignatures.intersection(other.wifiSignatures)
                score += Float(common.count) / Float(max(wifiSignatures.count, other.wifiSignatures.count))
                factors += 1
            }

            return score / Float(factors)
        }
    }

    // MARK: - Initialization

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("SpatialMemory.sqlite")

        if sqlite3_open(fileURL.path, &db) == SQLITE_OK {
            createTables()
        } else {
            print("Unable to open spatial memory database")
        }
    }

    private func createTables() {
        let createLocationsTable = """
            CREATE TABLE IF NOT EXISTS locations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fingerprint TEXT UNIQUE NOT NULL,
                name TEXT,
                visit_count INTEGER DEFAULT 1,
                last_visit REAL,
                avg_scan_time REAL DEFAULT 0,
                confidence REAL DEFAULT 0.5,
                created_at REAL,
                updated_at REAL
            );
        """

        let createObstaclesTable = """
            CREATE TABLE IF NOT EXISTS obstacles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                location_id INTEGER,
                x REAL, y REAL, z REAL,
                width REAL, height REAL, depth REAL,
                type TEXT,
                permanence REAL DEFAULT 0.5,
                last_seen REAL,
                FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE
            );
        """

        let createPatternsTable = """
            CREATE TABLE IF NOT EXISTS patterns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                location_id INTEGER,
                day_of_week INTEGER,
                hour_of_day INTEGER,
                change_type TEXT,
                area_x REAL, area_y REAL, area_z REAL,
                radius REAL,
                confidence REAL DEFAULT 0.5,
                FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE
            );
        """

        let createPathsTable = """
            CREATE TABLE IF NOT EXISTS paths (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                location_id INTEGER,
                waypoints TEXT,
                usage_count INTEGER DEFAULT 1,
                avg_traversal_time REAL,
                success_rate REAL DEFAULT 1.0,
                FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE
            );
        """

        let createIndices = """
            CREATE INDEX IF NOT EXISTS idx_fingerprint ON locations(fingerprint);
            CREATE INDEX IF NOT EXISTS idx_location_obstacles ON obstacles(location_id);
            CREATE INDEX IF NOT EXISTS idx_location_patterns ON patterns(location_id);
            CREATE INDEX IF NOT EXISTS idx_pattern_time ON patterns(day_of_week, hour_of_day);
        """

        executeSQL(createLocationsTable)
        executeSQL(createObstaclesTable)
        executeSQL(createPatternsTable)
        executeSQL(createPathsTable)
        executeSQL(createIndices)
    }

    // MARK: - Public API

    /// Check if current environment matches a known location
    func findMatchingLocation(fingerprint: LocationFingerprint, threshold: Float = 0.75) -> LocationMemory? {
        // First check cache
        let fingerprintHash = fingerprint.hash()
        if let cached = memoryCache[fingerprintHash] {
            return cached
        }

        // Check database for similar locations
        var matchedLocation: LocationMemory?

        dbQueue.sync {
            let query = "SELECT * FROM locations ORDER BY last_visit DESC LIMIT 20"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let storedFingerprint = String(cString: sqlite3_column_text(statement, 1))

                    // Quick exact match
                    if storedFingerprint == fingerprintHash {
                        matchedLocation = loadLocation(id: sqlite3_column_int64(statement, 0))
                        break
                    }

                    // TODO: Implement fuzzy matching for similar but not exact locations
                }
            }
            sqlite3_finalize(statement)
        }

        // Cache the result
        if let location = matchedLocation {
            updateCache(location)
        }

        return matchedLocation
    }

    /// Save or update location with current scan data
    func saveLocation(
        fingerprint: LocationFingerprint,
        obstacles: [(position: simd_float3, size: simd_float3, type: String)],
        name: String? = nil
    ) -> Int64 {
        let fingerprintHash = fingerprint.hash()
        var locationId: Int64 = -1

        dbQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Check if location exists
            if let existing = self.findLocationId(fingerprint: fingerprintHash) {
                locationId = existing
                self.updateLocation(id: existing, obstacles: obstacles)
            } else {
                locationId = self.createLocation(
                    fingerprint: fingerprintHash,
                    name: name,
                    obstacles: obstacles
                )
            }

            // Detect patterns if this is a frequent location
            if let location = self.loadLocation(id: locationId), location.isFrequent {
                self.detectPatterns(for: locationId, currentObstacles: obstacles)
            }
        }

        return locationId
    }

    /// Get predicted obstacle layout based on patterns
    func getPredictedLayout(for locationId: Int64, at date: Date = Date()) -> [CachedObstacle]? {
        guard let location = loadLocation(id: locationId) else { return nil }

        var predictedObstacles = location.obstacles

        // Apply temporal patterns
        for pattern in location.patterns {
            if pattern.matches(date: date) && pattern.confidence > 0.7 {
                // Apply pattern changes
                switch pattern.changeType {
                case "removed":
                    predictedObstacles.removeAll { obstacle in
                        simd_distance(obstacle.position, pattern.affectedArea) < pattern.radius
                    }
                case "added":
                    // TODO: Add predicted obstacles based on pattern
                    break
                case "moved":
                    // TODO: Adjust positions based on pattern
                    break
                default:
                    break
                }
            }
        }

        return predictedObstacles
    }

    /// Record successful navigation path
    func savePath(locationId: Int64, waypoints: [simd_float3], traversalTime: TimeInterval) {
        dbQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let waypointsJSON = waypoints.map { [$0.x, $0.y, $0.z] }
            guard let jsonData = try? JSONSerialization.data(withJSONObject: waypointsJSON),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let insert = """
                INSERT OR REPLACE INTO paths
                (location_id, waypoints, usage_count, avg_traversal_time, success_rate)
                VALUES (?, ?,
                    COALESCE((SELECT usage_count + 1 FROM paths WHERE location_id = ? AND waypoints = ?), 1),
                    ?, 1.0)
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(self.db, insert, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, locationId)
                sqlite3_bind_text(statement, 2, jsonString, -1, nil)
                sqlite3_bind_int64(statement, 3, locationId)
                sqlite3_bind_text(statement, 4, jsonString, -1, nil)
                sqlite3_bind_double(statement, 5, traversalTime)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    /// Get memory statistics
    func getMemoryStats() -> (locationCount: Int, totalObstacles: Int, storageSize: Int64) {
        var stats = (locationCount: 0, totalObstacles: 0, storageSize: Int64(0))

        dbQueue.sync {
            // Count locations
            if let count = executeScalar("SELECT COUNT(*) FROM locations") {
                stats.locationCount = Int(count)
            }

            // Count obstacles
            if let count = executeScalar("SELECT COUNT(*) FROM obstacles") {
                stats.totalObstacles = Int(count)
            }

            // Get database file size
            if let dbPath = sqlite3_db_filename(db, "main"),
               let attributes = try? FileManager.default.attributesOfItem(atPath: String(cString: dbPath)),
               let fileSize = attributes[.size] as? Int64 {
                stats.storageSize = fileSize
            }
        }

        return stats
    }

    /// Clean up old, unused locations
    func cleanupOldLocations(olderThan days: Int = 30) {
        dbQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 3600))
            let delete = "DELETE FROM locations WHERE last_visit < ? AND visit_count < 3"

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(self.db, delete, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_double(statement, 1, cutoffDate.timeIntervalSince1970)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Private Methods

    private func loadLocation(id: Int64) -> LocationMemory? {
        var location: LocationMemory?

        dbQueue.sync {
            let query = "SELECT * FROM locations WHERE id = ?"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, id)

                if sqlite3_step(statement) == SQLITE_ROW {
                    location = LocationMemory(
                        id: id,
                        fingerprint: String(cString: sqlite3_column_text(statement, 1)),
                        name: sqlite3_column_text(statement, 2).map { String(cString: $0) },
                        visitCount: Int(sqlite3_column_int(statement, 3)),
                        lastVisit: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                        obstacles: loadObstacles(for: id),
                        patterns: loadPatterns(for: id),
                        commonPaths: loadPaths(for: id),
                        averageScanTime: sqlite3_column_double(statement, 5),
                        confidence: Float(sqlite3_column_double(statement, 6))
                    )
                }
            }
            sqlite3_finalize(statement)
        }

        return location
    }

    private func loadObstacles(for locationId: Int64) -> [CachedObstacle] {
        var obstacles: [CachedObstacle] = []

        let query = "SELECT * FROM obstacles WHERE location_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, locationId)

            while sqlite3_step(statement) == SQLITE_ROW {
                obstacles.append(CachedObstacle(
                    x: Float(sqlite3_column_double(statement, 2)),
                    y: Float(sqlite3_column_double(statement, 3)),
                    z: Float(sqlite3_column_double(statement, 4)),
                    width: Float(sqlite3_column_double(statement, 5)),
                    height: Float(sqlite3_column_double(statement, 6)),
                    depth: Float(sqlite3_column_double(statement, 7)),
                    type: String(cString: sqlite3_column_text(statement, 8)),
                    permanence: Float(sqlite3_column_double(statement, 9)),
                    lastSeen: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
                ))
            }
        }
        sqlite3_finalize(statement)

        return obstacles
    }

    private func loadPatterns(for locationId: Int64) -> [TemporalPattern] {
        var patterns: [TemporalPattern] = []

        let query = "SELECT * FROM patterns WHERE location_id = ? AND confidence > 0.6"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, locationId)

            while sqlite3_step(statement) == SQLITE_ROW {
                patterns.append(TemporalPattern(
                    dayOfWeek: Int(sqlite3_column_int(statement, 2)),
                    hourOfDay: Int(sqlite3_column_int(statement, 3)),
                    changeType: String(cString: sqlite3_column_text(statement, 4)),
                    affectedArea: simd_float3(
                        Float(sqlite3_column_double(statement, 5)),
                        Float(sqlite3_column_double(statement, 6)),
                        Float(sqlite3_column_double(statement, 7))
                    ),
                    radius: Float(sqlite3_column_double(statement, 8)),
                    confidence: Float(sqlite3_column_double(statement, 9))
                ))
            }
        }
        sqlite3_finalize(statement)

        return patterns
    }

    private func loadPaths(for locationId: Int64) -> [SavedPath] {
        var paths: [SavedPath] = []

        let query = "SELECT * FROM paths WHERE location_id = ? ORDER BY usage_count DESC LIMIT 5"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, locationId)

            while sqlite3_step(statement) == SQLITE_ROW {
                if let waypointsJSON = sqlite3_column_text(statement, 2),
                   let jsonData = String(cString: waypointsJSON).data(using: .utf8),
                   let waypointArrays = try? JSONSerialization.jsonObject(with: jsonData) as? [[Float]] {

                    let waypoints = waypointArrays.map { simd_float3($0[0], $0[1], $0[2]) }

                    paths.append(SavedPath(
                        waypoints: waypoints,
                        usageCount: Int(sqlite3_column_int(statement, 3)),
                        averageTraversalTime: sqlite3_column_double(statement, 4),
                        successRate: Float(sqlite3_column_double(statement, 5))
                    ))
                }
            }
        }
        sqlite3_finalize(statement)

        return paths
    }

    private func findLocationId(fingerprint: String) -> Int64? {
        let query = "SELECT id FROM locations WHERE fingerprint = ?"
        var statement: OpaquePointer?
        var locationId: Int64?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, fingerprint, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                locationId = sqlite3_column_int64(statement, 0)
            }
        }
        sqlite3_finalize(statement)

        return locationId
    }

    private func createLocation(
        fingerprint: String,
        name: String?,
        obstacles: [(position: simd_float3, size: simd_float3, type: String)]
    ) -> Int64 {
        let now = Date().timeIntervalSince1970

        let insert = """
            INSERT INTO locations (fingerprint, name, visit_count, last_visit, created_at, updated_at)
            VALUES (?, ?, 1, ?, ?, ?)
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, fingerprint, -1, nil)
            if let name = name {
                sqlite3_bind_text(statement, 2, name, -1, nil)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            sqlite3_bind_double(statement, 3, now)
            sqlite3_bind_double(statement, 4, now)
            sqlite3_bind_double(statement, 5, now)

            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        let locationId = sqlite3_last_insert_rowid(db)

        // Save obstacles
        for obstacle in obstacles {
            saveObstacle(locationId: locationId, obstacle: obstacle)
        }

        return locationId
    }

    private func updateLocation(id: Int64, obstacles: [(position: simd_float3, size: simd_float3, type: String)]) {
        // Update visit count and last visit
        let update = "UPDATE locations SET visit_count = visit_count + 1, last_visit = ? WHERE id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, update, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, id)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // Update obstacles with permanence scoring
        updateObstaclesWithPermanence(locationId: id, newObstacles: obstacles)
    }

    private func saveObstacle(
        locationId: Int64,
        obstacle: (position: simd_float3, size: simd_float3, type: String)
    ) {
        let insert = """
            INSERT INTO obstacles (location_id, x, y, z, width, height, depth, type, last_seen)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, locationId)
            sqlite3_bind_double(statement, 2, Double(obstacle.position.x))
            sqlite3_bind_double(statement, 3, Double(obstacle.position.y))
            sqlite3_bind_double(statement, 4, Double(obstacle.position.z))
            sqlite3_bind_double(statement, 5, Double(obstacle.size.x))
            sqlite3_bind_double(statement, 6, Double(obstacle.size.y))
            sqlite3_bind_double(statement, 7, Double(obstacle.size.z))
            sqlite3_bind_text(statement, 8, obstacle.type, -1, nil)
            sqlite3_bind_double(statement, 9, Date().timeIntervalSince1970)

            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func updateObstaclesWithPermanence(
        locationId: Int64,
        newObstacles: [(position: simd_float3, size: simd_float3, type: String)]
    ) {
        let existingObstacles = loadObstacles(for: locationId)

        for newObs in newObstacles {
            var found = false
            var permanenceUpdate: Float = 0

            for existing in existingObstacles {
                if simd_distance(existing.position, newObs.position) < 0.5 {
                    // Obstacle still exists - increase permanence
                    permanenceUpdate = min(1.0, existing.permanence + 0.1)
                    found = true

                    let update = """
                        UPDATE obstacles SET permanence = ?, last_seen = ?
                        WHERE location_id = ? AND ABS(x - ?) < 0.5 AND ABS(z - ?) < 0.5
                    """

                    var statement: OpaquePointer?
                    if sqlite3_prepare_v2(db, update, -1, &statement, nil) == SQLITE_OK {
                        sqlite3_bind_double(statement, 1, Double(permanenceUpdate))
                        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
                        sqlite3_bind_int64(statement, 3, locationId)
                        sqlite3_bind_double(statement, 4, Double(newObs.position.x))
                        sqlite3_bind_double(statement, 5, Double(newObs.position.z))
                        sqlite3_step(statement)
                    }
                    sqlite3_finalize(statement)
                    break
                }
            }

            if !found {
                // New obstacle detected
                saveObstacle(locationId: locationId, obstacle: newObs)
            }
        }

        // Decrease permanence for obstacles not seen
        for existing in existingObstacles {
            let stillExists = newObstacles.contains { newObs in
                simd_distance(existing.position, newObs.position) < 0.5
            }

            if !stillExists {
                let update = """
                    UPDATE obstacles SET permanence = ?
                    WHERE location_id = ? AND x = ? AND y = ? AND z = ?
                """

                var statement: OpaquePointer?
                if sqlite3_prepare_v2(db, update, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_double(statement, 1, Double(max(0, existing.permanence - 0.2)))
                    sqlite3_bind_int64(statement, 2, locationId)
                    sqlite3_bind_double(statement, 3, Double(existing.x))
                    sqlite3_bind_double(statement, 4, Double(existing.y))
                    sqlite3_bind_double(statement, 5, Double(existing.z))
                    sqlite3_step(statement)
                }
                sqlite3_finalize(statement)
            }
        }
    }

    private func detectPatterns(
        for locationId: Int64,
        currentObstacles: [(position: simd_float3, size: simd_float3, type: String)]
    ) {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.weekday, .hour], from: now)

        guard let dayOfWeek = components.weekday,
              let hourOfDay = components.hour else { return }

        // Load historical obstacles for this time
        let historicalObstacles = loadObstacles(for: locationId)

        // Detect changes
        for historical in historicalObstacles {
            let stillExists = currentObstacles.contains { current in
                simd_distance(historical.position, current.position) < 0.5
            }

            if !stillExists && historical.permanence < 0.7 {
                // Object frequently disappears at this time
                updateOrCreatePattern(
                    locationId: locationId,
                    dayOfWeek: dayOfWeek,
                    hourOfDay: hourOfDay,
                    changeType: "removed",
                    area: historical.position,
                    radius: max(historical.width, historical.depth) / 2
                )
            }
        }

        // Check for new objects that appear at this time
        for current in currentObstacles {
            let isNew = !historicalObstacles.contains { historical in
                simd_distance(historical.position, current.position) < 0.5
            }

            if isNew {
                updateOrCreatePattern(
                    locationId: locationId,
                    dayOfWeek: dayOfWeek,
                    hourOfDay: hourOfDay,
                    changeType: "added",
                    area: current.position,
                    radius: max(current.size.x, current.size.z) / 2
                )
            }
        }
    }

    private func updateOrCreatePattern(
        locationId: Int64,
        dayOfWeek: Int,
        hourOfDay: Int,
        changeType: String,
        area: simd_float3,
        radius: Float
    ) {
        // Check if pattern exists
        let query = """
            SELECT id, confidence FROM patterns
            WHERE location_id = ? AND day_of_week = ? AND hour_of_day = ?
            AND change_type = ? AND ABS(area_x - ?) < 1.0 AND ABS(area_z - ?) < 1.0
        """

        var statement: OpaquePointer?
        var patternId: Int64?
        var currentConfidence: Float = 0.5

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, locationId)
            sqlite3_bind_int(statement, 2, Int32(dayOfWeek))
            sqlite3_bind_int(statement, 3, Int32(hourOfDay))
            sqlite3_bind_text(statement, 4, changeType, -1, nil)
            sqlite3_bind_double(statement, 5, Double(area.x))
            sqlite3_bind_double(statement, 6, Double(area.z))

            if sqlite3_step(statement) == SQLITE_ROW {
                patternId = sqlite3_column_int64(statement, 0)
                currentConfidence = Float(sqlite3_column_double(statement, 1))
            }
        }
        sqlite3_finalize(statement)

        if let id = patternId {
            // Update confidence
            let newConfidence = min(1.0, currentConfidence + 0.15)
            let update = "UPDATE patterns SET confidence = ? WHERE id = ?"

            if sqlite3_prepare_v2(db, update, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_double(statement, 1, Double(newConfidence))
                sqlite3_bind_int64(statement, 2, id)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        } else {
            // Create new pattern
            let insert = """
                INSERT INTO patterns
                (location_id, day_of_week, hour_of_day, change_type, area_x, area_y, area_z, radius, confidence)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0.5)
            """

            if sqlite3_prepare_v2(db, insert, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, locationId)
                sqlite3_bind_int(statement, 2, Int32(dayOfWeek))
                sqlite3_bind_int(statement, 3, Int32(hourOfDay))
                sqlite3_bind_text(statement, 4, changeType, -1, nil)
                sqlite3_bind_double(statement, 5, Double(area.x))
                sqlite3_bind_double(statement, 6, Double(area.y))
                sqlite3_bind_double(statement, 7, Double(area.z))
                sqlite3_bind_double(statement, 8, Double(radius))
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    private func updateCache(_ location: LocationMemory) {
        memoryCache[location.fingerprint] = location

        // Evict oldest if cache is full
        if memoryCache.count > maxCacheSize {
            if let oldest = memoryCache.values.min(by: { $0.lastVisit < $1.lastVisit }) {
                memoryCache.removeValue(forKey: oldest.fingerprint)
            }
        }
    }

    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func executeScalar(_ sql: String) -> Int64? {
        var statement: OpaquePointer?
        var result: Int64?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                result = sqlite3_column_int64(statement, 0)
            }
        }
        sqlite3_finalize(statement)

        return result
    }
}

// MARK: - Helper Extensions

private extension Float {
    var bitPattern: UInt32 {
        return self.bitPattern
    }
}

private extension UInt32 {
    var data: Data {
        var value = self
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

private extension Int {
    var data: Data {
        var value = self
        return Data(bytes: &value, count: MemoryLayout<Int>.size)
    }
}