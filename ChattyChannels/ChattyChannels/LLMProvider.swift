// ChattyChannels/ChattyChannels/LLMProvider.swift

import Foundation

/// A protocol defining the interface for a Large Language Model (LLM) provider.
///
/// Implementations of this protocol are responsible for handling all aspects of
/// communication with a specific LLM's API, such as OpenAI, Google Gemini,
/// Anthropic Claude, or xAI Grok. This includes:
/// - Managing API-specific Data Transfer Objects (DTOs).
/// - Constructing requests for the correct API endpoints.
/// - Handling authentication (typically via an API key).
/// - Parsing responses and extracting meaningful data.
///
/// The main purpose is to abstract the complexities of different LLM APIs behind
/// a consistent interface, allowing `NetworkService` to interact with them uniformly.
///
/// ## Topics
/// ### Initializers
/// - ``init(apiKey:modelName:endpoint:)``
/// ### Sending Messages
/// - ``sendMessage(_:systemPrompt:)``
protocol LLMProvider {
    /// Initializes a new instance of an LLM provider.
    ///
    /// Each provider implementation will use this initializer to configure itself
    /// with the necessary API key and optionally a specific model name or API endpoint.
    /// If `modelName` or `endpoint` are not provided, the implementation should
    /// use sensible defaults.
    ///
    /// - Parameters:
    ///   - apiKey: The API key required for authenticating with the LLM provider's service.
    ///   - modelName: An optional string specifying the particular model to be used
    ///                (e.g., "gpt-4o-mini", "gemini-1.5-pro-latest"). If `nil`, the provider
    ///                will use its default model.
    ///   - endpoint: An optional string specifying a custom API endpoint URL.
    ///               If `nil`, the provider will use its default endpoint.
    init(apiKey: String, modelName: String?, endpoint: String?)

    /// Asynchronously sends a user-provided message and a system prompt to the LLM.
    ///
    /// This function is the core of the provider's functionality. It constructs
    /// the appropriate request for the specific LLM API, sends it, and then
    /// parses the response to extract the assistant's reply.
    ///
    /// - Parameters:
    ///   - input: The text message from the user to be sent to the LLM.
    ///   - systemPrompt: A system-level instruction that guides the LLM's behavior,
    ///                   persona, or response format.
    /// - Returns: A `String` containing the LLM assistant's reply, typically trimmed of
    ///            leading and trailing whitespace.
    /// - Throws: An error, usually an instance of `NetworkError`, if any part of the
    ///           communication fails. This can include issues with:
    ///           - Request encoding.
    ///           - Network connectivity (`NetworkError.networkUnreachable`).
    ///           - Invalid API URL (`NetworkError.invalidURL`).
    ///           - Non-successful HTTP status codes from the API (`NetworkError.invalidResponse`).
    ///           - Problems decoding the API's JSON response (`NetworkError.decodingFailed`).
    ///           - Other general request failures (`NetworkError.requestFailed`).
    func sendMessage(_ input: String, systemPrompt: String) async throws -> String
}