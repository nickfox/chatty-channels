// DatabaseConfiguration.swift
// Configuration and initialization for PostgreSQL database

import Foundation
import OSLog

/// Database configuration and management
public class DatabaseConfiguration {
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "DatabaseConfiguration")

    public static let shared = DatabaseConfiguration()

    private(set) public var database: PostgreSQLDatabase?
    private(set) public var embeddingService: EmbeddingService?

    // Current context
    private var currentProjectName: String?
    private var currentProjectID: UUID?
    private var currentSessionID: UUID?

    private init() {}

    /// Initialize database connection
    /// - Parameters:
    ///   - host: PostgreSQL host
    ///   - port: PostgreSQL port
    ///   - database: Database name
    ///   - username: Database username
    ///   - password: Database password
    public func initialize(
        host: String = "localhost",
        port: Int = 5432,
        database: String = "chatty_channels",
        username: String = "postgres",
        password: String = ""
    ) async throws {
        logger.info("Initializing database configuration...")

        // Create database instance
        self.database = PostgreSQLDatabase(
            host: host,
            port: port,
            database: database,
            username: username,
            password: password
        )

        // Connect to database
        try await self.database?.connect()

        // Initialize embedding service
        self.embeddingService = EmbeddingService()

        // Check if Ollama is available
        if let isAvailable = await embeddingService?.checkAvailability(), isAvailable {
            logger.info("Embedding service is available")
        } else {
            logger.warning("Embedding service not available - embeddings will be disabled")
        }

        logger.info("Database configuration initialized successfully")
    }

    /// Set up current project and session
    public func setupProject(name: String, logicProjectPath: String? = nil) async throws {
        guard let database = database else {
            throw DatabaseError.notConnected
        }

        logger.info("Setting up project: \(name)")

        // Get or create project
        let projectID = try await database.getOrCreateProject(name: name, logicProjectPath: logicProjectPath)
        self.currentProjectID = projectID
        self.currentProjectName = name

        // Get or create active session
        if let existingSession = try await database.getActiveSession(projectID: projectID) {
            self.currentSessionID = existingSession
            logger.info("Using existing active session: \(existingSession)")
        } else {
            let newSession = try await database.startSession(projectID: projectID)
            self.currentSessionID = newSession
            logger.info("Started new session: \(newSession)")
        }

        // Update database context
        await database.setCurrentProject(projectID)
        await database.setCurrentSession(currentSessionID!)
    }

    /// Get current project and session IDs
    public func getCurrentContext() -> (projectID: UUID, sessionID: UUID)? {
        guard let projectID = currentProjectID, let sessionID = currentSessionID else {
            return nil
        }
        return (projectID, sessionID)
    }

    /// Get current project name
    public func getCurrentProjectName() -> String? {
        return currentProjectName
    }

    /// Close database connection
    public func shutdown() async {
        await database?.closeConnection()
        logger.info("Database configuration shut down")
    }
}
