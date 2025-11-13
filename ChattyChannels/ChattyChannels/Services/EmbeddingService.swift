// EmbeddingService.swift
// Service for generating text embeddings using Ollama nomic-embed-text model

import Foundation
import OSLog

/// Service for generating text embeddings using Ollama
public actor EmbeddingService {
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "EmbeddingService")
    private let ollamaEndpoint: String
    private let modelName: String
    private let session: URLSession

    /// Initialize embedding service
    /// - Parameters:
    ///   - ollamaEndpoint: Ollama API endpoint (default: http://localhost:11434)
    ///   - modelName: Model name (default: nomic-embed-text)
    public init(
        ollamaEndpoint: String = "http://localhost:11434",
        modelName: String = "nomic-embed-text"
    ) {
        self.ollamaEndpoint = ollamaEndpoint
        self.modelName = modelName
        self.session = URLSession.shared
    }

    /// Generate embeddings for a text string
    /// - Parameter text: Input text to embed
    /// - Returns: 768-dimensional embedding vector
    public func generateEmbedding(for text: String) async throws -> [Float] {
        let url = URL(string: "\(ollamaEndpoint)/api/embeddings")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": modelName,
            "prompt": text
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw EmbeddingError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("Ollama API returned status code: \(httpResponse.statusCode)")
                throw EmbeddingError.apiError(statusCode: httpResponse.statusCode)
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let embedding = json?["embedding"] as? [Double] else {
                logger.error("Failed to parse embedding from response")
                throw EmbeddingError.invalidResponse
            }

            // Convert Double to Float
            let floatEmbedding = embedding.map { Float($0) }

            logger.debug("Generated embedding with \(floatEmbedding.count) dimensions")
            return floatEmbedding

        } catch let error as EmbeddingError {
            throw error
        } catch {
            logger.error("Failed to generate embedding: \(error.localizedDescription)")
            throw EmbeddingError.networkError(error.localizedDescription)
        }
    }

    /// Generate embeddings for multiple texts in batch
    /// - Parameter texts: Array of input texts
    /// - Returns: Array of embedding vectors
    public func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        var embeddings: [[Float]] = []

        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            embeddings.append(embedding)
        }

        logger.info("Generated \(embeddings.count) embeddings")
        return embeddings
    }

    /// Check if Ollama is running and model is available
    public func checkAvailability() async -> Bool {
        let url = URL(string: "\(ollamaEndpoint)/api/tags")!

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let models = json?["models"] as? [[String: Any]] else {
                return false
            }

            let hasModel = models.contains { model in
                if let name = model["name"] as? String {
                    return name.contains(modelName)
                }
                return false
            }

            if hasModel {
                logger.info("Ollama is available with \(self.modelName) model")
            } else {
                logger.warning("Ollama is available but \(self.modelName) model not found")
            }

            return hasModel

        } catch {
            logger.error("Ollama availability check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Calculate cosine similarity between two embeddings
    /// - Parameters:
    ///   - embedding1: First embedding vector
    ///   - embedding2: Second embedding vector
    /// - Returns: Cosine similarity score (0 to 1)
    public static func cosineSimilarity(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
        guard embedding1.count == embedding2.count else {
            return 0.0
        }

        var dotProduct: Float = 0.0
        var magnitude1: Float = 0.0
        var magnitude2: Float = 0.0

        for i in 0..<embedding1.count {
            dotProduct += embedding1[i] * embedding2[i]
            magnitude1 += embedding1[i] * embedding1[i]
            magnitude2 += embedding2[i] * embedding2[i]
        }

        magnitude1 = sqrt(magnitude1)
        magnitude2 = sqrt(magnitude2)

        guard magnitude1 > 0 && magnitude2 > 0 else {
            return 0.0
        }

        return dotProduct / (magnitude1 * magnitude2)
    }
}

// MARK: - Error Types

public enum EmbeddingError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case networkError(String)
    case modelNotAvailable

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Ollama API"
        case .apiError(let statusCode):
            return "Ollama API error: HTTP \(statusCode)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .modelNotAvailable:
            return "Ollama model not available"
        }
    }
}
