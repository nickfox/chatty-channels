// ChattyChannels/ChattyChannels/ClaudeProvider.swift

import Foundation
import os.log

// MARK: - Claude DTOs (Specific to this provider)

/// Represents a single message in a conversation for the Anthropic Claude Messages API.
///
/// Each message has a `role` ("user" or "assistant") and `content`.
/// For simplicity, this implementation uses a single string for content. The Claude API
/// supports a more complex array of content blocks (e.g., for images), which could be
/// an future enhancement.
private struct ClaudeMessage: Codable {
    /// The role of the entity sending the message. Must be "user" or "assistant".
    let role: String
    /// The textual content of the message.
    let content: String
    // For more complex content (e.g., images), this would be:
    // let content: [ClaudeContentBlock]
}

// Example for a richer content block structure if needed in the future:
// /// Represents a block of content within a ``ClaudeMessage``.
// private struct ClaudeContentBlock: Codable {
//     /// The type of content, e.g., "text" or "image".
//     let type: String
//     /// The textual data, if `type` is "text".
//     let text: String?
//     // Add other fields for different content types like image sources.
// }

/// The request body for the Anthropic Claude Messages API.
private struct ClaudeMessagesRequest: Codable {
    /// The identifier of the Claude model to use (e.g., "claude-3-5-sonnet-20240620").
    let model: String
    /// An optional system prompt to guide the model's behavior or persona.
    let system: String?
    /// An array of ``ClaudeMessage`` objects representing the conversation history.
    let messages: [ClaudeMessage]
    /// The maximum number of tokens to generate in the response.
    let max_tokens: Int
    // Optional parameters like temperature, top_p, top_k could be added here.
    // let temperature: Double?
}

/// Represents a text block within the content array of a Claude API response.
private struct ClaudeTextBlock: Decodable {
    /// The type of the content block, expected to be "text".
    let type: String
    /// The actual text content of the block.
    let text: String
}

/// The response structure from the Anthropic Claude Messages API.
private struct ClaudeMessagesResponse: Decodable {
    // let id: String // Unique identifier for the message.
    // let type: String // Type of object, typically "message".
    /// The role of the responder, expected to be "assistant".
    let role: String
    /// An array of content blocks, typically containing one ``ClaudeTextBlock``.
    let content: [ClaudeTextBlock]
    // let model: String // The model that generated the response.
    // let stop_reason: String? // Reason the model stopped, e.g., "end_turn", "max_tokens".
    // let stop_sequence: String? // If a custom stop sequence was triggered.
    // /// Token usage statistics for the request.
    // struct Usage: Decodable {
    //     let input_tokens: Int
    //     let output_tokens: Int
    // }
    // let usage: Usage
}

// MARK: - ClaudeProvider Implementation

/// An ``LLMProvider`` implementation for interacting with Anthropic's Claude API.
///
/// This class handles formatting requests for the Claude Messages API,
/// sending them with the required headers (`x-api-key`, `anthropic-version`),
/// and parsing the responses.
///
/// ## Configuration
/// The provider is initialized with an API key and an optional model name, endpoint URL,
/// and Anthropic API version string.
/// - Default model: `"claude-3-5-sonnet-20240620"`
/// - Default endpoint: `"https://api.anthropic.com/v1/messages"`
/// - Default Anthropic version: `"2023-06-01"` (users should verify the latest recommended version).
///
/// ## Topics
/// ### Initializers
/// - ``init(apiKey:modelName:endpoint:anthropicVersion:)``
/// - ``init(apiKey:modelName:endpoint:)``
/// ### Conforming to LLMProvider
/// - ``sendMessage(_:systemPrompt:)``
final class ClaudeProvider: LLMProvider {
    private let apiKey: String
    private let modelName: String
    private let endpointURL: URL
    private let anthropicVersion: String
    private let logger: Logger
    private let urlSession: URLSession // Added URLSession property

    /// The default API endpoint for Claude messages.
    private static let defaultEndpoint = "https://api.anthropic.com/v1/messages"
    /// The default Claude model used if none is specified.
    private static let defaultModel = "claude-3-5-sonnet-20240620"
    /// The default Anthropic API version header value. Users should check Anthropic's
    /// documentation for the latest recommended version.
    private static let defaultAnthropicVersion = "2023-06-01"

    /// Designated initializer for `ClaudeProvider` allowing full configuration.
    /// - Parameters:
    ///   - apiKey: The API key for Anthropic Claude.
    ///   - modelName: Optional. The specific Claude model to use. Defaults to ``defaultModel``.
    ///   - endpoint: Optional. A custom endpoint URL. Defaults to ``defaultEndpoint``.
    ///   - anthropicVersion: Optional. The `anthropic-version` header value. Defaults to ``defaultAnthropicVersion``.
    ///   - urlSession: Optional. The URLSession instance to use. Defaults to `URLSession.shared`.
    init(apiKey: String, modelName: String? = nil, endpoint: String? = nil, anthropicVersion: String? = nil, urlSession: URLSession = .shared) { // Designated initializer
        self.apiKey = apiKey
        self.modelName = modelName ?? ClaudeProvider.defaultModel
        self.anthropicVersion = anthropicVersion ?? ClaudeProvider.defaultAnthropicVersion
        self.urlSession = urlSession // Store the session
        
        let urlString = endpoint ?? ClaudeProvider.defaultEndpoint
        guard let url = URL(string: urlString) else {
            fatalError("Invalid Claude endpoint URL constructed: \(urlString). This indicates a programming error with the default URL string or a malformed custom endpoint.")
        }
        self.endpointURL = url
        
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ChattyChannelsApp",
                             category: "ClaudeProvider")
        logger.info("ClaudeProvider initialized. Model: '\(self.modelName)', API Version: '\(self.anthropicVersion)', Endpoint: '\(self.endpointURL.absoluteString)'")
    }
    
    /// Required initializer to conform to ``LLMProvider``.
    ///
    /// This initializer uses the ``defaultAnthropicVersion`` for the `anthropic-version` header.
    /// For custom `anthropicVersion`, use ``init(apiKey:modelName:endpoint:anthropicVersion:)``.
    /// - Parameters:
    ///   - apiKey: The API key for Anthropic Claude.
    ///   - modelName: Optional. The specific Claude model to use. Defaults to ``defaultModel``.
    ///   - endpoint: Optional. A custom endpoint URL for the Claude API. Defaults to ``defaultEndpoint``.
    convenience required init(apiKey: String, modelName: String?, endpoint: String?) {
        self.init(apiKey: apiKey, modelName: modelName, endpoint: endpoint, anthropicVersion: nil, urlSession: .shared) // Call designated init
    }


    /// Sends a message to the Claude Messages API.
    ///
    /// Constructs a request including the system prompt (as a top-level `system` field),
    /// user input, and required headers. It then sends the request to the configured
    /// Claude model and endpoint, and processes the response.
    ///
    /// - Parameters:
    ///   - input: The user's text message.
    ///   - systemPrompt: The system prompt to guide the AI's behavior.
    /// - Returns: The assistant's reply as a `String`.
    /// - Throws: A ``NetworkError`` if the request fails at any stage.
    func sendMessage(_ input: String, systemPrompt: String) async throws -> String {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        // Note: Some beta features or newer models might require an `anthropic-beta` header.
        // This implementation relies on the `anthropic-version` header as standard.

        let claudeRequest = ClaudeMessagesRequest(
            model: self.modelName,
            system: systemPrompt, // Claude API uses a dedicated 'system' field for system prompts
            messages: [ClaudeMessage(role: "user", content: input)],
            max_tokens: 2048 // A common default; consider making this configurable
            // temperature: 0.7 // Example of an optional parameter
        )

        do {
            let encoder = JSONEncoder()
            // The Claude API generally expects snake_case keys. If issues arise, uncomment:
            // encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(claudeRequest)
            logger.debug("Sending request to Claude. Body: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Could not decode body for logging")")
        } catch {
            logger.error("Failed to encode Claude request: \(error.localizedDescription)")
            throw NetworkError.requestFailed("Encoding request for Claude failed: \(error.localizedDescription)")
        }
        
        logger.info("🔼 Claude: Sending to model '\(self.modelName)'. User input: \"\(input, privacy: .public)\"")

        do {
            // Use the injected urlSession instance
            let (data, response) = try await self.urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("No HTTPURLResponse received from Claude.")
                throw NetworkError.invalidResponse(0, "No HTTP response received from Claude.")
            }

            let rawResponseBody = String(data: data, encoding: .utf8) ?? "«empty or non-UTF8 response body»"
            logger.debug("Claude raw response. Status: \(httpResponse.statusCode). Body: \(rawResponseBody, privacy: .sensitive)")

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("Claude API returned an error. Status: \(httpResponse.statusCode). Body: \(rawResponseBody)")
                throw NetworkError.invalidResponse(httpResponse.statusCode, "Claude API Error: \(rawResponseBody)")
            }

            let decodedResponse: ClaudeMessagesResponse
            do {
                let decoder = JSONDecoder()
                // If API returns snake_case keys and they aren't mapping, uncomment:
                // decoder.keyDecodingStrategy = .convertFromSnakeCase
                decodedResponse = try decoder.decode(ClaudeMessagesResponse.self, from: data)
            } catch {
                logger.error("Failed to decode Claude JSON response: \(error.localizedDescription). Raw body for context: \(rawResponseBody)")
                throw NetworkError.decodingFailed("Decoding Claude JSON response failed: \(error.localizedDescription). Response: \(rawResponseBody)")
            }

            // The response content is an array of blocks; we expect at least one text block.
            guard let firstTextBlock = decodedResponse.content.first(where: { $0.type == "text" }) else {
                logger.error("No 'text' type content block found in Claude response. Content blocks received: \(decodedResponse.content.count).")
                throw NetworkError.decodingFailed("No text content block in Claude response. Check API response structure.")
            }
            
            let replyContent = firstTextBlock.text
            let trimmedReply = replyContent.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("🔽 Claude: Received reply from model '\(self.modelName)'. Assistant: \"\(trimmedReply, privacy: .public)\"")
            return trimmedReply

        } catch let error as NetworkError {
            throw error
        } catch let urlError as URLError {
            logger.error("Claude URLSession error: \(urlError.localizedDescription), Code: \(urlError.code.rawValue)")
            throw NetworkError.networkUnreachable("Network communication error with Claude: \(urlError.localizedDescription) (Code: \(urlError.code.rawValue))")
        } catch {
            logger.error("An unknown error occurred during the Claude request: \(error.localizedDescription)")
            throw NetworkError.requestFailed("An unknown error occurred with Claude: \(error.localizedDescription)")
        }
    }
}