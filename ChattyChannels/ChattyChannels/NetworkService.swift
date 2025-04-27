//
//  NetworkService.swift
//  ChattyChannels
//
//  Created : 2024-03-14
//  Revised : 2025-04-27 – switched backend from Google Gemini to OpenAI o3
//
//  ────────────────────────────────────────────────────────────────────────────
//  Production-quality network layer for Chatty Channels.
//
//  ‣ Purpose
//      Handles all communication with OpenAI's Chat Completion endpoint.
//      • Securely loads the API key from Config.plist
//      • Sends system + user messages to the o3 model
//      • Performs exhaustive error handling and logging
//      • Decodes the assistant's reply into a plain String
//
//  ‣ Usage
//      let reply = try await networkService.sendMessage("Hello, world!")
//
//  ‣ Threading
//      This type is an @MainActor ObservableObject so it is safe to inject
//      into SwiftUI views. All network work happens off the main thread via
//      URLSession; the public API returns to the caller on the main actor.
//

import Foundation
import Combine
import os.log

// MARK: - Error definition
// ---------------------------------------------------------------------------

/// Errors thrown by ``NetworkService``.
///
/// These granular cases allow the UI to present actionable feedback.
///
/// ## Cases
/// - `invalidURL`: The supplied API URL is malformed or invalid
/// - `requestFailed`: General request preparation or execution failure
/// - `invalidResponse`: Server responded with non-success status code
/// - `decodingFailed`: Response data could not be decoded into expected format
/// - `networkUnreachable`: Network connectivity issues prevented request completion
///
/// ## Example Usage
/// ```swift
/// do {
///     let response = try await networkService.sendMessage("Hello")
/// } catch let error as NetworkError {
///     switch error {
///     case .invalidResponse(let statusCode, let details):
///         print("Server error \(statusCode): \(details)")
///     case .networkUnreachable:
///         print("Check your internet connection")
///     default:
///         print("Error: \(error.localizedDescription)")
///     }
/// }
/// ```
enum NetworkError: Error, LocalizedError {

    /// The supplied URL is malformed.
    case invalidURL

    /// Something went wrong before we received an HTTP response.
    case requestFailed(String)

    /// The server answered, but with a non-2xx status code.
    case invalidResponse(Int, String)

    /// We received data, but failed to decode it.
    case decodingFailed(String)

    /// No Internet connection or TLS/transport failure.
    case networkUnreachable(String)

    // : LocalizedError -------------------------------------------------------
    var errorDescription: String? {
        switch self {
        case .invalidURL:                                "Invalid API URL"
        case .requestFailed(let message):                "Request failed: \(message)"
        case .invalidResponse(let code, let details):    "Server error (HTTP \(code)): \(details)"
        case .decodingFailed(let details):               "Failed to decode response: \(details)"
        case .networkUnreachable(let message):           "Network error: \(message)"
        }
    }
}

// MARK: - OpenAI DTOs
// ---------------------------------------------------------------------------

/// A single chat message in the OpenAI Chat API format.
///
/// Represents one message in a conversation, with a role (system, user, or assistant)
/// and the message content.
private struct OAChatMessage: Codable {
    /// The role of the message sender (system, user, assistant)
    let role: String
    
    /// The actual content of the message
    let content: String
}

/// Request body for the OpenAI Chat Completion API.
///
/// Contains the model identifier and an array of messages representing the conversation history.
private struct OAChatRequest: Encodable {
    /// The model identifier to use for completion (e.g., "o3")
    let model: String
    
    /// An array of messages representing the conversation history
    let messages: [OAChatMessage]
}

/// Decodable wrapper for the OpenAI Chat API response.
///
/// This structure models the expected response format from the API, focusing
/// on extracting the message content from the assistant.
private struct OAChatResponse: Decodable {
    /// A choice returned by the API, containing a message
    struct Choice: Decodable {
        /// The message part of a choice
        struct ChoiceMessage: Decodable { 
            /// The content of the message
            let content: String 
        }
        /// The message from the assistant
        let message: ChoiceMessage
    }
    /// Array of choices returned by the API
    let choices: [Choice]
}

// MARK: - Network service
// ---------------------------------------------------------------------------

/// Service responsible for talking to OpenAI's **o3** model.
///
/// The NetworkService class handles all communication with OpenAI's Chat Completion API endpoint.
/// It provides a clean, robust interface for sending user messages to the AI model and receiving
/// formatted responses for audio parameter control.
///
/// - Important: This service requires a valid API key stored in Config.plist under the key `openaiApiKey`.
///
/// ## Features
/// - Securely loads API credentials from Config.plist
/// - Formats requests according to the OpenAI API specifications
/// - Handles parameter change requests like gain adjustments
/// - Performs comprehensive error handling with detailed diagnostics
/// - Thread-safe design with async/await support
///
/// ## Usage Example
/// ```swift
/// // Create a service
/// let networkService = NetworkService()
///
/// // Use in an async context
/// Task {
///     do {
///         let response = try await networkService.sendMessage("Set gain to -3dB")
///         print("AI responded: \(response)")
///     } catch {
///         print("Error: \(error)")
///     }
/// }
/// ```
///
/// ## Threading
/// This type is an `@MainActor ObservableObject` so it is safe to inject
/// into SwiftUI views. All network operations happen off the main thread via
/// URLSession; the public API returns to the caller on the main actor.
@MainActor
final class NetworkService: ObservableObject {

    // MARK: Configuration ----------------------------------------------------

    /// Subsystem logger for diagnostics visible in Console.app.
    ///
    /// Uses the app's bundle identifier as the subsystem and "NetworkService" as the category
    /// for efficient filtering in Console.app.
    private let logger  = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ChattyChannels",
                                 category:  "NetworkService")

    /// Model to be used for all requests. Adjust here if you upgrade.
    ///
    /// Currently set to "o3", OpenAI's efficient language model optimized for
    /// interaction tasks.
    private let modelName = "o4-mini"

    /// Stable Chat Completion endpoint.
    ///
    /// This is the standard OpenAI chat completions endpoint that works with various models.
    private let endpoint  = "https://api.openai.com/v1/chat/completions"

    // MARK: Initialisation ---------------------------------------------------

    /// Initializes a new NetworkService instance.
    ///
    /// No parameters are required as the service loads its configuration from Config.plist.
    init() {}

    /// Reads the OpenAI key from *Config.plist* (key: **openaiApiKey**).
    ///
    /// Securely retrieves the API key from the app's configuration file.
    /// Fails if the key is missing or empty.
    ///
    /// - Returns: The secret key as a `String`.
    /// - Throws: ``NetworkError.requestFailed(_:)`` when the key is missing or invalid.
    private func loadApiKey() throws -> String {
        guard
            let path   = Bundle.main.path(forResource: "Config", ofType: "plist"),
            let config = NSDictionary(contentsOfFile: path),
            let key    = config["openaiApiKey"] as? String,
            !key.isEmpty
        else {
            logger.error("Missing or invalid OpenAI API key in Config.plist")
            throw NetworkError.requestFailed("Missing or invalid API key")
        }
        return key
    }

    // MARK: Public API -------------------------------------------------------

    /// Sends a user message to **o3** and returns the assistant's reply.
    ///
    /// This method provides the primary interface for sending messages to the AI model.
    /// It handles the entire request lifecycle:
    /// 1. Validates input and prepares the request
    /// 2. Performs the network request asynchronously
    /// 3. Validates the HTTP response
    /// 4. Decodes the JSON response
    /// 5. Returns the extracted message content
    ///
    /// The system prompts the AI to respond with JSON parameter commands for audio controls,
    /// particularly for gain/volume adjustments.
    ///
    /// - Parameter input: End-user text message to send to the AI.
    /// - Returns: The assistant's text reply, which may be JSON for parameter changes or plain text.
    /// - Throws: ``NetworkError`` for connectivity, HTTP or decoding failures.
    @discardableResult
    func sendMessage(_ input: String) async throws -> String {

        //----------------------------------------------------------------------
        // 1. Assemble request
        //----------------------------------------------------------------------

        // First, ensure input is not empty to prevent sending an empty command
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("Attempted to send empty message")
            throw NetworkError.requestFailed("Cannot send empty message")
        }

        let apiKey = try loadApiKey()
        guard let url = URL(string: endpoint) else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)",  forHTTPHeaderField: "Authorization")

        // System instruction remains identical to the previous Gemini version.
        let systemInstruction = """
        You are an AI assistant integrated into a music production environment.
        When the user asks you to change the main gain, volume, or level parameter, respond ONLY with a JSON object in the following format, ALWAYS using "GAIN" as the parameter_id:
        {"command": "set_parameter", "parameter_id": "GAIN", "value": <float_value>}
        Replace <float_value> with the numerical value requested.
        For example, if the user says "Set gain to -6dB", respond with:
        {"command": "set_parameter", "parameter_id": "GAIN", "value": -6.0}
        If the user asks to reduce or decrease gain by a specific amount, subtract that amount from the current value.
        If the user asks to increase gain by a specific amount, add that amount to the current value.
        If the user asks to change a *different* specific parameter (that isn't gain/volume/level), use its correct ID if you know it.
        If the user asks a general question or makes a request you cannot fulfil with a parameter change, respond normally in plain text.
        """

        // Encode request body using Codable for type safety.
        let chatRequest = OAChatRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: systemInstruction),
                .init(role: "user",   content: input)
            ],
        )
        request.httpBody = try JSONEncoder().encode(chatRequest)

        logger.info("🔼 Sending to \(self.modelName): \"\(input, privacy: .public)\"")


        //----------------------------------------------------------------------
        // 2. Perform request
        //----------------------------------------------------------------------

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            //------------------------------------------------------------------
            // 3. HTTP-level validation
            //------------------------------------------------------------------

            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse(0, "No HTTP response")
            }
            let raw = String(data: data, encoding: .utf8) ?? "«empty body»"

            guard (200...299).contains(http.statusCode) else {
                logger.error("OpenAI responded with \(http.statusCode): \(raw)")
                throw NetworkError.invalidResponse(http.statusCode, raw)
            }

            //------------------------------------------------------------------
            // 4. Decode JSON
            //------------------------------------------------------------------

            let chatResponse: OAChatResponse
            do {
                chatResponse = try JSONDecoder().decode(OAChatResponse.self, from: data)
            } catch {
                logger.error("Decoding failed: \(error.localizedDescription)")
                throw NetworkError.decodingFailed(raw)
            }

            guard let reply = chatResponse.choices.first?.message.content else {
                throw NetworkError.decodingFailed("No choices in response.")
            }

            logger.info("🔽 Received from \(self.modelName): \"\(reply, privacy: .public)\"")
            return reply.trimmingCharacters(in: .whitespacesAndNewlines)

        // Network / transport errors -----------------------------------------
        } catch let urlError as URLError {
            throw NetworkError.networkUnreachable(
                "\(urlError.localizedDescription) (code \(urlError.code.rawValue))"
            )
        }
    }
}
