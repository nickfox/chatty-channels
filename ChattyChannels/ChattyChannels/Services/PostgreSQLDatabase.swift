// PostgreSQLDatabase.swift
// PostgreSQL database service for Chatty Channels
// Replaces SQLiteDatabase with full schema support

import Foundation
import PostgresNIO
import OSLog
import NIOCore
import NIOPosix

/// PostgreSQL database service for track assignments, messages, and conversation history
public actor PostgreSQLDatabase {
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private var connectionPool: PostgresConnection?
    private let configuration: PostgresConnection.Configuration
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "PostgreSQLDatabase")

    // Current session tracking
    private var currentProjectID: UUID?
    private var currentSessionID: UUID?

    /// Initialize PostgreSQL database connection
    /// - Parameters:
    ///   - host: Database host (default: localhost)
    ///   - port: Database port (default: 5432)
    ///   - database: Database name (default: chatty_channels)
    ///   - username: Database username (default: postgres)
    ///   - password: Database password (default: empty)
    public init(
        host: String = "localhost",
        port: Int = 5432,
        database: String = "chatty_channels",
        username: String = "postgres",
        password: String = ""
    ) {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)

        // Configure PostgreSQL connection
        self.configuration = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
    }

    deinit {
        Task {
            await closeConnection()
            try? await eventLoopGroup.shutdownGracefully()
        }
    }

    // MARK: - Connection Management

    /// Connect to PostgreSQL database
    public func connect() async throws {
        logger.info("Connecting to PostgreSQL database...")

        do {
            connectionPool = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: configuration,
                id: 1
            )
            logger.info("Successfully connected to PostgreSQL")
        } catch {
            logger.error("Failed to connect to PostgreSQL: \(error.localizedDescription)")
            throw DatabaseError.connectionFailed(error.localizedDescription)
        }
    }

    /// Close database connection
    public func closeConnection() async {
        guard let connection = connectionPool else { return }
        try? await connection.close()
        connectionPool = nil
        logger.info("PostgreSQL connection closed")
    }

    /// Ensure connection is active, reconnect if needed
    private func ensureConnection() async throws {
        if connectionPool == nil {
            try await connect()
        }
    }

    // MARK: - Project & Session Management

    /// Get or create a project by name
    public func getOrCreateProject(name: String, logicProjectPath: String? = nil) async throws -> UUID {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            SELECT id FROM projects WHERE name = $1 AND deleted_at IS NULL
            """

        do {
            let rows = try await connection.query(query, [name])

            if let row = rows.first, let projectID = try? row.decode(UUID.self, context: .default) {
                // Update last opened time
                let updateQuery = "UPDATE projects SET last_opened_at = CURRENT_TIMESTAMP WHERE id = $1"
                try await connection.query(updateQuery, [projectID])

                logger.info("Found existing project: \(name) with ID: \(projectID)")
                return projectID
            }

            // Create new project
            let insertQuery = """
                INSERT INTO projects (name, logic_project_path, last_opened_at)
                VALUES ($1, $2, CURRENT_TIMESTAMP)
                RETURNING id
                """

            let insertRows = try await connection.query(insertQuery, [name, logicProjectPath ?? ""])
            guard let firstRow = insertRows.first,
                  let newProjectID = try? firstRow.decode(UUID.self, context: .default) else {
                throw DatabaseError.queryFailed("Failed to create project")
            }

            logger.info("Created new project: \(name) with ID: \(newProjectID)")
            currentProjectID = newProjectID
            return newProjectID

        } catch {
            logger.error("Failed to get or create project: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    /// Start a new session for a project
    public func startSession(projectID: UUID) async throws -> UUID {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        // End any active sessions for this project
        let endQuery = """
            UPDATE sessions SET is_active = FALSE, ended_at = CURRENT_TIMESTAMP
            WHERE project_id = $1 AND is_active = TRUE
            """
        try await connection.query(endQuery, [projectID])

        // Create new session
        let insertQuery = """
            INSERT INTO sessions (project_id)
            VALUES ($1)
            RETURNING id
            """

        do {
            let rows = try await connection.query(insertQuery, [projectID])
            guard let row = rows.first,
                  let sessionID = try? row.decode(UUID.self, context: .default) else {
                throw DatabaseError.queryFailed("Failed to create session")
            }

            logger.info("Started new session: \(sessionID) for project: \(projectID)")
            currentSessionID = sessionID
            return sessionID

        } catch {
            logger.error("Failed to start session: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    /// Get current active session for a project
    public func getActiveSession(projectID: UUID) async throws -> UUID? {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            SELECT id FROM sessions
            WHERE project_id = $1 AND is_active = TRUE
            ORDER BY started_at DESC
            LIMIT 1
            """

        do {
            let rows = try await connection.query(query, [projectID])
            if let row = rows.first, let sessionID = try? row.decode(UUID.self, context: .default) {
                return sessionID
            }
            return nil
        } catch {
            logger.error("Failed to get active session: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Track Assignments

    /// Save a track assignment (replaces SQLite's saveTrackMapping)
    public func saveTrackAssignment(
        projectID: UUID,
        sessionID: UUID,
        trackNumber: Int,
        trackName: String,
        pluginID: String
    ) async throws {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        // Mark previous assignment as not current
        let updateQuery = """
            UPDATE track_assignments
            SET is_current = FALSE
            WHERE project_id = $1 AND session_id = $2 AND track_number = $3 AND is_current = TRUE
            """
        try await connection.query(updateQuery, [projectID, sessionID, trackNumber])

        // Insert new assignment
        let insertQuery = """
            INSERT INTO track_assignments (project_id, session_id, track_number, track_name, plugin_id, is_current)
            VALUES ($1, $2, $3, $4, $5, TRUE)
            """

        do {
            try await connection.query(insertQuery, [projectID, sessionID, trackNumber, trackName, pluginID])
            logger.info("Saved track assignment: \(pluginID) -> \(trackName) (track \(trackNumber))")
        } catch {
            logger.error("Failed to save track assignment: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    /// Get all current track assignments for a session
    public func getAllTrackAssignments(projectID: UUID, sessionID: UUID) async throws -> [String: String] {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            SELECT track_name, plugin_id
            FROM track_assignments
            WHERE project_id = $1 AND session_id = $2 AND is_current = TRUE
            ORDER BY track_number
            """

        do {
            let rows = try await connection.query(query, [projectID, sessionID])
            var mappings: [String: String] = [:]

            for row in rows {
                if let trackName = try? row.decode(String.self, context: .default, at: 0),
                   let pluginID = try? row.decode(String.self, context: .default, at: 1) {
                    mappings[trackName] = pluginID
                }
            }

            logger.info("Retrieved \(mappings.count) track assignments")
            return mappings

        } catch {
            logger.error("Failed to get track assignments: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    /// Get track assignment by plugin ID
    public func getTrackAssignmentByPluginID(
        projectID: UUID,
        sessionID: UUID,
        pluginID: String
    ) async throws -> (trackName: String, trackNumber: Int)? {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            SELECT track_name, track_number
            FROM track_assignments
            WHERE project_id = $1 AND session_id = $2 AND plugin_id = $3 AND is_current = TRUE
            """

        do {
            let rows = try await connection.query(query, [projectID, sessionID, pluginID])
            if let row = rows.first,
               let trackName = try? row.decode(String.self, context: .default, at: 0),
               let trackNumber = try? row.decode(Int.self, context: .default, at: 1) {
                return (trackName: trackName, trackNumber: trackNumber)
            }
            return nil
        } catch {
            logger.error("Failed to get track assignment by plugin ID: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    /// Clear all track assignments for a session
    public func clearTrackAssignments(projectID: UUID, sessionID: UUID) async throws {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            UPDATE track_assignments
            SET is_current = FALSE
            WHERE project_id = $1 AND session_id = $2 AND is_current = TRUE
            """

        do {
            try await connection.query(query, [projectID, sessionID])
            logger.info("Cleared all track assignments for session")
        } catch {
            logger.error("Failed to clear track assignments: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Messages & Conversations

    /// Save a conversation message
    public func saveMessage(
        projectID: UUID,
        sessionID: UUID,
        role: String,
        content: String,
        model: String? = nil,
        embedding: [Float]? = nil,
        isKeyDecision: Bool = false,
        decisionSummary: String? = nil
    ) async throws -> UUID {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            INSERT INTO messages (project_id, session_id, role, content, model, embedding, is_key_decision, decision_summary)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id
            """

        do {
            let rows = try await connection.query(
                query,
                [projectID, sessionID, role, content, model ?? "", embedding, isKeyDecision, decisionSummary ?? ""]
            )

            guard let row = rows.first,
                  let messageID = try? row.decode(UUID.self, context: .default) else {
                throw DatabaseError.queryFailed("Failed to save message")
            }

            logger.info("Saved message: \(messageID) (role: \(role))")
            return messageID

        } catch {
            logger.error("Failed to save message: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    /// Get recent messages for a project
    public func getRecentMessages(projectID: UUID, limit: Int = 10) async throws -> [(id: UUID, role: String, content: String, createdAt: Date)] {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            SELECT id, role, content, created_at
            FROM messages
            WHERE project_id = $1
            ORDER BY created_at DESC
            LIMIT $2
            """

        do {
            let rows = try await connection.query(query, [projectID, limit])
            var messages: [(id: UUID, role: String, content: String, createdAt: Date)] = []

            for row in rows {
                if let id = try? row.decode(UUID.self, context: .default, at: 0),
                   let role = try? row.decode(String.self, context: .default, at: 1),
                   let content = try? row.decode(String.self, context: .default, at: 2),
                   let createdAt = try? row.decode(Date.self, context: .default, at: 3) {
                    messages.append((id: id, role: role, content: content, createdAt: createdAt))
                }
            }

            return messages

        } catch {
            logger.error("Failed to get recent messages: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Mission Control

    /// Save a Mission Control conversation entry
    public func saveMissionControlConversation(
        projectID: UUID,
        sessionID: UUID,
        role: String,
        content: String,
        displayType: String = "chat"
    ) async throws -> UUID {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            INSERT INTO mission_control_conversations (project_id, session_id, role, content, display_type)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id
            """

        do {
            let rows = try await connection.query(query, [projectID, sessionID, role, content, displayType])

            guard let row = rows.first,
                  let entryID = try? row.decode(UUID.self, context: .default) else {
                throw DatabaseError.queryFailed("Failed to save mission control conversation")
            }

            logger.info("Saved mission control conversation: \(entryID)")
            return entryID

        } catch {
            logger.error("Failed to save mission control conversation: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    /// Save a Mission Control debug entry
    public func saveMissionControlDebug(
        projectID: UUID,
        sessionID: UUID,
        sender: String,
        receiver: String?,
        messageType: String,
        content: String,
        payload: String? = nil,
        severity: String = "info"
    ) async throws -> UUID {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            INSERT INTO mission_control_debug (project_id, session_id, sender, receiver, message_type, content, payload, severity)
            VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8)
            RETURNING id
            """

        do {
            let rows = try await connection.query(
                query,
                [projectID, sessionID, sender, receiver ?? "", messageType, content, payload ?? "{}", severity]
            )

            guard let row = rows.first,
                  let debugID = try? row.decode(UUID.self, context: .default) else {
                throw DatabaseError.queryFailed("Failed to save mission control debug entry")
            }

            logger.debug("Saved mission control debug: \(debugID) from \(sender)")
            return debugID

        } catch {
            logger.error("Failed to save mission control debug: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Context & Embeddings

    /// Create a context snapshot
    public func createContextSnapshot(
        projectID: UUID,
        sessionID: UUID,
        name: String,
        description: String?,
        messageIDs: [UUID],
        trackState: String?
    ) async throws -> UUID {
        try await ensureConnection()
        guard let connection = connectionPool else {
            throw DatabaseError.notConnected
        }

        let query = """
            INSERT INTO context_snapshots (project_id, session_id, name, description, message_ids, track_state)
            VALUES ($1, $2, $3, $4, $5, $6::jsonb)
            RETURNING id
            """

        do {
            let messageIDsArray = messageIDs.map { $0.uuidString }
            let rows = try await connection.query(
                query,
                [projectID, sessionID, name, description ?? "", messageIDsArray, trackState ?? "{}"]
            )

            guard let row = rows.first,
                  let snapshotID = try? row.decode(UUID.self, context: .default) else {
                throw DatabaseError.queryFailed("Failed to create context snapshot")
            }

            logger.info("Created context snapshot: \(name) with ID: \(snapshotID)")
            return snapshotID

        } catch {
            logger.error("Failed to create context snapshot: \(error.localizedDescription)")
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    // MARK: - Current Context Helpers

    public func setCurrentProject(_ projectID: UUID) {
        currentProjectID = projectID
    }

    public func setCurrentSession(_ sessionID: UUID) {
        currentSessionID = sessionID
    }

    public func getCurrentProject() -> UUID? {
        return currentProjectID
    }

    public func getCurrentSession() -> UUID? {
        return currentSessionID
    }
}

// MARK: - Error Types

public enum DatabaseError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case queryFailed(String)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Database not connected"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        }
    }
}
