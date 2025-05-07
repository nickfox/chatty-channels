// ChattyChannels/ChattyChannels/NetworkService.swift

import Foundation
import Combine
import os.log

/// Defines errors that can occur during network operations with LLM providers.
///
/// These errors provide specific details about failures, aiding in debugging and
/// user feedback.
///
/// ## Topics
/// ### Error Cases
/// - ``NetworkError/invalidURL``
/// - ``NetworkError/requestFailed(_:)``
/// - ``NetworkError/invalidResponse(_:_:)``
/// - ``NetworkError/decodingFailed(_:)``
/// - ``NetworkError/networkUnreachable(_:)``
/// ### Error Descriptions
/// - ``LocalizedError/errorDescription``
enum NetworkError: Error, LocalizedError {
    /// Indicates that the API endpoint URL is malformed or invalid.
    case invalidURL
    /// A general failure occurred during request preparation or execution, before a response was received.
    case requestFailed(String)
    /// The server responded, but with a non-2xx HTTP status code, indicating an API error.
    case invalidResponse(Int, String)
    /// The server's response data could not be decoded into the expected format.
    case decodingFailed(String)
    /// A network connectivity issue (e.g., no internet, DNS failure, TLS error) prevented the request.
    case networkUnreachable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:                                "Invalid API URL."
        case .requestFailed(let message):                "Request failed: \(message)."
        case .invalidResponse(let code, let details):    "Server error (HTTP \(code)): \(details)."
        case .decodingFailed(let details):               "Failed to decode response: \(details)."
        case .networkUnreachable(let message):           "Network error: \(message)."
        }
    }
}

/// Manages communication with a configured Large Language Model (LLM) provider.
///
/// `NetworkService` acts as the primary interface for the application to send messages
/// to an LLM and receive responses. It is designed to be an `@MainActor ObservableObject`,
/// making it suitable for use in SwiftUI views.
///
/// ## Overview
/// The service performs the following key functions:
/// - **Configuration Loading:** On initialization, it reads `Config.plist` to determine
///   the active LLM provider (e.g., OpenAI, Gemini) and its associated API key and
///   model name.
/// - **Provider Abstraction:** It uses an instance conforming to the ``LLMProvider``
///   protocol to handle the specifics of API communication. This allows `NetworkService`
///   to remain agnostic to the details of individual LLM provider APIs.
/// - **Message Sending:** Provides a ``sendMessage(_:)`` method to send user input
///   to the active LLM provider, along with a predefined system prompt.
/// - **Error Handling:** Propagates errors (typically ``NetworkError``) from the
///   underlying provider or its own operations.
/// - **Logging:** Uses `os.log` for detailed diagnostic logging.
///
/// ## Configuration (`Config.plist`)
/// `NetworkService` relies on a `Config.plist` file in the main bundle for its setup.
/// The following keys are expected:
/// - `activeLLMProvider` (String): The name of the LLM provider to use (e.g., "OpenAI", "Gemini", "Claude", "Grok"). Defaults to "OpenAI" if missing or empty.
/// - `[providerName]ApiKey` (String): The API key for the respective provider. For example, `openaiApiKey`, `geminiApiKey`.
/// - `[providerName]ModelName` (String, Optional): The specific model to use for the provider. For example, `openaiModelName`, `geminiModelName`. If omitted, the provider will use its internal default model.
///
/// ## Usage
/// ```swift
/// @MainActor
/// class MyViewModel: ObservableObject {
///     private let networkService = NetworkService()
///     @Published var aiResponse: String = ""
///     @Published var errorMessage: String?
///
///     func askAI(prompt: String) async {
///         do {
///             self.aiResponse = try await networkService.sendMessage(prompt)
///             self.errorMessage = nil
///         } catch let error as NetworkError {
///             self.errorMessage = error.localizedDescription
///             // Handle specific NetworkError cases if needed
///         } catch {
///             self.errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
///         }
///     }
/// }
/// ```
///
/// ## Topics
/// ### Initializers
/// - ``init()``
/// ### Sending Messages
/// - ``sendMessage(_:)``
/// ### Error Handling
/// - ``NetworkError``
@MainActor
final class NetworkService: ObservableObject {

    // MARK: Configuration
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ChattyChannelsApp", // More specific subsystem
                               category: "NetworkService")

    /// The currently active LLM provider instance.
    /// This is determined during initialization based on `Config.plist`.
    private var activeProvider: LLMProvider!
    
    /// The system instruction sent to the LLM with every user message.
    /// This prompt guides the LLM's behavior, such as its persona or response format,
    /// particularly for generating JSON commands for audio parameter control.
    private let systemInstruction = """
        you are soundsmith (always lowercase, also answers to smitty), a world-class music producer with decades of experience crafting multi-platinum records across genres. you're currently in a real-time studio session with the musician. your communication style should be confident, decisive, and efficient - like a top producer who values clarity and results.

        core capabilities:
        1. parameter adjustments via json commands
        2. musical analysis and creative direction
        3. professional workflow management
        4. genre expertise across the musical spectrum

        parameter control system:
        when the musician requests parameter changes, respond ONLY with properly formatted json:

        1. for main gain/volume/level adjustments:
           {"command": "set_parameter", "parameter_id": "GAIN", "value": <float_value>}

        2. for other parameter adjustments (when id is known):
           {"command": "set_parameter", "parameter_id": "<known_parameter_id>", "value": <float_value>}

        parameter adjustment guidelines:
        - for exact value requests (e.g., "set gain to -6db"): use the specified value
        - for relative adjustments (e.g., "increase gain by 3db"): calculate from current value
        - for qualitative requests (e.g., "make it louder"): use professional judgment to select appropriate increment (+3db for "louder", +6db for "much louder")
        - if parameter id is unknown or request is unclear: ask for clarification on specific parameter

        analysis responses:
        when providing feedback on audio, structure your response:
        1. initial impression (immediate reaction to what you're hearing)
        2. technical assessment (mix balance, frequency issues, dynamics)
        3. creative direction (specific suggestions for improvement)
        4. next steps (clear actionable recommendations)

        conversational guidelines:
        - keep responses concise and actionable - studio time is valuable
        - use technical terminology appropriate for professional musicians
        - focus on solutions rather than problems
        - reference relevant professional standards and techniques
        - when appropriate, mention specific artists/productions as reference points
        - always maintain focus on delivering a commercially competitive final product

        memory:
        - maintain awareness of the current project state
        - remember previous adjustments and their impact
        - track overall direction and musician's preferences
        - adapt recommendations based on established project goals

        if the musician asks a question unrelated to parameter control, respond conversationally but efficiently, maintaining your role as their collaborative producer focused on creating a hit record. Be fun, but not overbearing.
        """

    // MARK: Initialisation
    /// Initializes a new `NetworkService` instance.
    ///
    /// The initializer reads `Config.plist` to determine the active LLM provider
    /// (specified by `activeLLMProvider` key, defaulting to "openai"). It then loads the
    /// corresponding API key (e.g., `openaiApiKey`) and an optional model name
    /// (e.g., `openaiModelName`).
    ///
    /// If `Config.plist` is missing, or if the API key for the active provider cannot be
    /// loaded, `activeProvider` will remain `nil`, and subsequent calls to
    /// ``sendMessage(_:)`` will fail with a ``NetworkError/requestFailed(_:)`` error.
    /// It logs critical errors if initialization of the active provider fails.
    init() {
        guard let config = loadConfigPlist() else {
            logger.critical("CRITICAL: Config.plist not found or unreadable. NetworkService will not function.")
            return
        }

        let providerNameFromConfig = config["activeLLMProvider"] as? String
        let providerNameToUse = (providerNameFromConfig?.isEmpty ?? true) ? "openai" : providerNameFromConfig!

        if providerNameFromConfig == nil || providerNameFromConfig!.isEmpty {
            logger.warning("'activeLLMProvider' in Config.plist is missing or empty. Defaulting to 'openai'.")
        }
        
        logger.info("Attempting to initialize with LLM Provider: \(providerNameToUse)")

        var providerInitialized = false

        // Helper to load model name for the current provider's configuration key (e.g., "openai" -> "openaiModelName")
        func loadModelName(forProviderPlistKey providerKey: String) -> String? {
            let modelConfigKey = "\(providerKey.lowercased())ModelName" // e.g., "openaiModelName"
            if let modelName = config[modelConfigKey] as? String, !modelName.isEmpty {
                logger.info("Using model '\(modelName)' for \(providerKey) from Config.plist (key: \(modelConfigKey)).")
                return modelName
            } else {
                logger.info("No specific model name found for \(providerKey) in Config.plist (key: \(modelConfigKey)). Provider will use its default model.")
                return nil
            }
        }

        switch providerNameToUse.lowercased() {
            case "openai":
                let apiKeyConfigKey = "openaiApiKey"
                do {
                    let apiKey = try loadApiKey(from: config, forProviderConfigKey: apiKeyConfigKey)
                    let modelName = loadModelName(forProviderPlistKey: "openai")
                    self.activeProvider = OpenAIProvider(apiKey: apiKey, modelName: modelName)
                    logger.info("Successfully initialized with OpenAIProvider.")
                    providerInitialized = true
                } catch {
                    logger.error("Failed to initialize OpenAIProvider: \(error.localizedDescription)")
                }
            case "gemini":
                let apiKeyConfigKey = "geminiApiKey"
                do {
                    let apiKey = try loadApiKey(from: config, forProviderConfigKey: apiKeyConfigKey)
                    let modelName = loadModelName(forProviderPlistKey: "gemini")
                    // GeminiProvider's init has a default model if modelName is nil
                    self.activeProvider = GeminiProvider(apiKey: apiKey, modelName: modelName)
                    logger.info("Successfully initialized with GeminiProvider.")
                    providerInitialized = true
                } catch {
                    logger.error("Failed to initialize GeminiProvider: \(error.localizedDescription)")
                }
            case "claude":
                let apiKeyConfigKey = "claudeApiKey"
                do {
                    let apiKey = try loadApiKey(from: config, forProviderConfigKey: apiKeyConfigKey)
                    let modelName = loadModelName(forProviderPlistKey: "claude")
                    self.activeProvider = ClaudeProvider(apiKey: apiKey, modelName: modelName)
                    logger.info("Successfully initialized with ClaudeProvider.")
                    providerInitialized = true
                } catch {
                    logger.error("Failed to initialize ClaudeProvider: \(error.localizedDescription)")
                }
            case "grok":
                let apiKeyConfigKey = "grokApiKey"
                do {
                    let apiKey = try loadApiKey(from: config, forProviderConfigKey: apiKeyConfigKey)
                    let modelName = loadModelName(forProviderPlistKey: "grok")
                    self.activeProvider = GrokProvider(apiKey: apiKey, modelName: modelName)
                    logger.info("Successfully initialized with GrokProvider.")
                    providerInitialized = true
                } catch {
                    logger.error("Failed to initialize GrokProvider: \(error.localizedDescription)")
                }
            default:
                logger.error("Unsupported provider '\(providerNameToUse)' in Config.plist or default. NetworkService may not function.")
        }

        if !providerInitialized {
            logger.critical("CRITICAL: Active LLM provider '\(providerNameToUse)' could not be initialized. Check API key ('\(providerNameToUse.lowercased())ApiKey') and model name ('\(providerNameToUse.lowercased())ModelName') in Config.plist. NetworkService will not function.")
        }
    }
    
    /// Internal initializer for testing purposes.
    /// Allows injecting a specific `LLMProvider` instance, bypassing `Config.plist` loading.
    /// - Parameter provider: The `LLMProvider` instance to use for this service.
    internal init(provider: LLMProvider) {
        self.activeProvider = provider
        logger.info("NetworkService initialized with injected provider: \(String(describing: type(of: provider)))")
    }

    /// Loads the `Config.plist` file from the main bundle.
    /// - Returns: An `NSDictionary` representing the plist content, or `nil` if not found.
    private func loadConfigPlist() -> NSDictionary? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist") else {
            logger.error("Config.plist not found in the main bundle.")
            return nil
        }
        return NSDictionary(contentsOfFile: path)
    }

    /// Loads an API key from the provided configuration dictionary.
    /// - Parameters:
    ///   - config: The `NSDictionary` loaded from `Config.plist`.
    ///   - keyName: The key for the API key string in the plist (e.g., "openaiApiKey").
    /// - Returns: The API key as a `String`.
    /// - Throws: ``NetworkError/requestFailed(_:)`` if the key is missing or the value is empty.
    private func loadApiKey(from config: NSDictionary, forProviderConfigKey keyName: String) throws -> String {
        guard let key = config[keyName] as? String, !key.isEmpty else {
            logger.error("Missing or invalid API key for '\(keyName)' in Config.plist.")
            throw NetworkError.requestFailed("Missing or invalid API key for '\(keyName)' in Config.plist.")
        }
        return key
    }

    // MARK: Public API
    /// Sends a user message to the currently active LLM provider and returns the assistant's reply.
    ///
    /// This method first checks if an ``activeProvider`` has been successfully initialized.
    /// It then ensures the input message is not empty before delegating the call to the
    /// `sendMessage(_:systemPrompt:)` method of the ``activeProvider``.
    /// The predefined ``systemInstruction`` is passed along with the user's input.
    ///
    /// - Parameter input: The end-user's text message to be sent to the LLM.
    /// - Returns: The LLM assistant's text reply, typically trimmed of whitespace.
    /// - Throws: A ``NetworkError`` if:
    ///   - The `activeProvider` is not initialized (due to configuration issues).
    ///   - The `input` string is empty after trimming whitespace.
    ///   - The underlying call to the `activeProvider`'s `sendMessage` method fails.
    /// - Note: The `@discardableResult` attribute indicates that the caller is not required
    ///         to use the returned `String`.
    @discardableResult
    func sendMessage(_ input: String) async throws -> String {
        guard let provider = activeProvider else {
            logger.critical("CRITICAL: sendMessage called but activeProvider is not initialized. Check Config.plist, API keys, and model names.")
            throw NetworkError.requestFailed("NetworkService not properly initialized. Active provider is missing. Review configuration.")
        }

        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            logger.error("Attempted to send an empty message.")
            throw NetworkError.requestFailed("Cannot send an empty message.")
        }

        let providerType = String(describing: type(of: provider))
        logger.info("🔼 Sending to \(providerType): \"\(trimmedInput, privacy: .public)\"")

        do {
            let reply = try await provider.sendMessage(trimmedInput, systemPrompt: self.systemInstruction)
            logger.info("🔽 Received from \(providerType): \"\(reply, privacy: .public)\"")
            return reply
        } catch let error as NetworkError {
            logger.error("Error received from \(providerType): \(error.localizedDescription)")
            throw error // Re-throw known NetworkError
        } catch {
            logger.error("An unknown error occurred while communicating with \(providerType): \(error.localizedDescription)")
            throw NetworkError.requestFailed("An unknown error occurred with \(providerType): \(error.localizedDescription)")
        }
    }
}
