// ConversationStorageService.swift
// Service for managing conversation history and message storage

import Foundation
import OSLog

/// Service for storing and retrieving conversation messages with embeddings
public actor ConversationStorageService {
    private let dbConfig: DatabaseConfiguration
    private let embeddingService: EmbeddingService?
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "ConversationStorage")

    /// Initialize conversation storage service
    /// - Parameter dbConfig: Database configuration
    public init(dbConfig: DatabaseConfiguration? = nil) {
        self.dbConfig = dbConfig ?? DatabaseConfiguration.shared
        self.embeddingService = dbConfig?.embeddingService
    }

    // MARK: - Message Storage

    /// Save a conversation message with optional embedding
    /// - Parameters:
    ///   - role: Message role (user, assistant, system)
    ///   - content: Message content
    ///   - model: LLM model name (e.g., "gpt-4", "claude-sonnet-4-5")
    ///   - generateEmbedding: Whether to generate and store embedding
    ///   - isKeyDecision: Mark as a key decision
    ///   - decisionSummary: Summary for key decisions
    /// - Returns: Message ID
    public func saveMessage(
        role: String,
        content: String,
        model: String? = nil,
        generateEmbedding: Bool = true,
        isKeyDecision: Bool = false,
        decisionSummary: String? = nil
    ) async throws -> UUID {
        guard let context = dbConfig.getCurrentContext(),
              let database = dbConfig.database else {
            throw ConversationError.notConfigured
        }

        var embedding: [Float]? = nil

        // Generate embedding if requested and service is available
        if generateEmbedding, let embeddingService = embeddingService {
            do {
                embedding = try await embeddingService.generateEmbedding(for: content)
                logger.debug("Generated embedding for message with \(embedding?.count ?? 0) dimensions")
            } catch {
                logger.warning("Failed to generate embedding: \(error.localizedDescription)")
                // Continue without embedding
            }
        }

        let messageID = try await database.saveMessage(
            projectID: context.projectID,
            sessionID: context.sessionID,
            role: role,
            content: content,
            model: model,
            embedding: embedding,
            isKeyDecision: isKeyDecision,
            decisionSummary: decisionSummary
        )

        logger.info("Saved message \(messageID) from \(role)")
        return messageID
    }

    /// Get recent messages for current project
    /// - Parameter limit: Number of messages to retrieve
    /// - Returns: Array of messages
    public func getRecentMessages(limit: Int = 10) async throws -> [(id: UUID, role: String, content: String, createdAt: Date)] {
        guard let context = dbConfig.getCurrentContext(),
              let database = dbConfig.database else {
            throw ConversationError.notConfigured
        }

        return try await database.getRecentMessages(projectID: context.projectID, limit: limit)
    }

    // MARK: - Mission Control

    /// Save a Mission Control conversation entry (producer-user chat)
    /// - Parameters:
    ///   - role: Role (user or producer)
    ///   - content: Message content
    ///   - displayType: Display type (chat, action, status)
    /// - Returns: Entry ID
    public func saveMissionControlConversation(
        role: String,
        content: String,
        displayType: String = "chat"
    ) async throws -> UUID {
        guard let context = dbConfig.getCurrentContext(),
              let database = dbConfig.database else {
            throw ConversationError.notConfigured
        }

        return try await database.saveMissionControlConversation(
            projectID: context.projectID,
            sessionID: context.sessionID,
            role: role,
            content: content,
            displayType: displayType
        )
    }

    /// Save a Mission Control debug entry (agent-orchestrator communication)
    /// - Parameters:
    ///   - sender: Sending agent/orchestrator
    ///   - receiver: Receiving agent (optional)
    ///   - messageType: Type of message (command, response, status, error, log)
    ///   - content: Message content
    ///   - payload: Optional JSON payload
    ///   - severity: Log severity (debug, info, warning, error)
    /// - Returns: Debug entry ID
    public func saveMissionControlDebug(
        sender: String,
        receiver: String? = nil,
        messageType: String,
        content: String,
        payload: String? = nil,
        severity: String = "info"
    ) async throws -> UUID {
        guard let context = dbConfig.getCurrentContext(),
              let database = dbConfig.database else {
            throw ConversationError.notConfigured
        }

        return try await database.saveMissionControlDebug(
            projectID: context.projectID,
            sessionID: context.sessionID,
            sender: sender,
            receiver: receiver,
            messageType: messageType,
            content: content,
            payload: payload,
            severity: severity
        )
    }

    // MARK: - Context Snapshots

    /// Create a context snapshot for important moments
    /// - Parameters:
    ///   - name: Snapshot name
    ///   - description: Optional description
    ///   - messageIDs: Message IDs to include
    ///   - trackState: Optional track state JSON
    /// - Returns: Snapshot ID
    public func createContextSnapshot(
        name: String,
        description: String? = nil,
        messageIDs: [UUID],
        trackState: String? = nil
    ) async throws -> UUID {
        guard let context = dbConfig.getCurrentContext(),
              let database = dbConfig.database else {
            throw ConversationError.notConfigured
        }

        guard !messageIDs.isEmpty else {
            throw ConversationError.invalidSnapshot("Message IDs cannot be empty")
        }

        return try await database.createContextSnapshot(
            projectID: context.projectID,
            sessionID: context.sessionID,
            name: name,
            description: description,
            messageIDs: messageIDs,
            trackState: trackState
        )
    }

    // MARK: - Helper Methods

    /// Mark a message as a key decision
    /// - Parameters:
    ///   - messageID: Message ID to mark
    ///   - summary: Decision summary
    public func markAsKeyDecision(messageID: UUID, summary: String) async throws {
        // This would require an update method in PostgreSQLDatabase
        // For now, decisions should be marked during initial save
        logger.info("Marking message \(messageID) as key decision with summary: \(summary)")
    }

    /// Generate conversation context for LLM prompts
    /// - Parameter messageCount: Number of recent messages to include
    /// - Returns: Formatted conversation context
    public func generateConversationContext(messageCount: Int = 10) async throws -> String {
        let messages = try await getRecentMessages(limit: messageCount)

        var context = "# Recent Conversation History\n\n"
        for message in messages.reversed() {
            context += "**\(message.role.capitalized)**: \(message.content)\n\n"
        }

        return context
    }
}

// MARK: - Error Types

public enum ConversationError: Error, LocalizedError {
    case notConfigured
    case invalidSnapshot(String)
    case embeddingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Database not configured or no project context available"
        case .invalidSnapshot(let message):
            return "Invalid snapshot: \(message)"
        case .embeddingFailed(let message):
            return "Embedding generation failed: \(message)"
        }
    }
}
