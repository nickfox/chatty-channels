// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/NetworkService.swift

/// NetworkService handles communication with external AI services.
///
/// This service is responsible for connecting to Google's Gemini API,
/// sending user messages, and receiving AI responses. It handles authentication,
/// request formatting, and error handling for the AI communication channel.
import Foundation
import Combine // Needed for ObservableObject
import os.log

/// Error types that can occur during network operations.
///
/// These errors provide specific information about what went wrong during
/// communication with the AI service, allowing for appropriate error handling
/// and user feedback.
enum NetworkError: Error, LocalizedError {
    /// The API URL is malformed or invalid.
    case invalidURL
    
    /// The request failed to be sent or processed.
    /// - Parameter message: Description of what went wrong
    case requestFailed(String)
    
    /// The server returned an unsuccessful status code.
    /// - Parameter code: The HTTP status code
    /// - Parameter details: Additional information about the error
    case invalidResponse(Int, String)
    
    /// The response couldn't be decoded into the expected format.
    /// - Parameter details: Description of the decoding failure
    case decodingFailed(String)
    
    /// The network is unavailable or the connection failed.
    /// - Parameter message: Details about the connectivity issue
    case networkUnreachable(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .requestFailed(let message): return "Request failed: \(message)"
        case .invalidResponse(let code, let details): return "Server error: HTTP \(code) - \(details)"
        case .decodingFailed(let details): return "Failed to decode response: \(details)"
        case .networkUnreachable(let message): return "Network error: \(message)"
        }
    }
}

/// Service for handling communication with the Gemini AI API.
///
/// NetworkService manages all aspects of communicating with Google's Gemini API:
/// - Loading API keys from configuration
/// - Constructing properly formatted requests
/// - Sending requests with system instructions
/// - Processing and parsing responses
/// - Error handling and reporting
///
/// This service is designed to be injected into views via SwiftUI's environment.
final class NetworkService: ObservableObject {
    /// System logger for network-related events.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NetworkService")
    
    /// The Gemini model identifier to use for AI requests.
    private let modelName = "gemini-1.5-flash-latest"

    /// Creates a new NetworkService instance.
    ///
    /// The initializer is empty as the actual configuration is loaded from Config.plist
    /// when needed, rather than at initialization time.
    init() {}
    
    /// Loads the Gemini API key from the configuration file.
    ///
    /// - Returns: The API key as a string.
    /// - Throws: NetworkError.requestFailed if the key is missing or invalid.
    private func loadApiKey() throws -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let apiKey = config["geminiApiKey"] as? String, !apiKey.isEmpty else {
            logger.error("Missing or invalid Gemini API key in Config.plist")
            throw NetworkError.requestFailed("Missing or invalid API key")
        }
        return apiKey
    }
    
    /// Sends a message to the Gemini AI service and receives a response.
    ///
    /// This method handles the full lifecycle of an AI request:
    /// 1. Retrieves the API key
    /// 2. Constructs the API URL
    /// 3. Formats the request with system instructions
    /// 4. Sends the request
    /// 5. Processes and validates the response
    /// 6. Extracts the AI-generated text
    ///
    /// - Parameter input: The user's message to send to the AI
    /// - Returns: The AI's response as a string
    /// - Throws: Various NetworkError types based on what goes wrong
    func sendMessage(_ input: String) async throws -> String {
        let apiKey = try loadApiKey()
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)") else {
            logger.error("Invalid Gemini URL for model: \(self.modelName)")
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // --- System Instruction for AI ---
        let systemInstruction = """
        You are an AI assistant integrated into a music production environment.
        When the user asks you to change the main gain, volume, or level parameter, respond ONLY with a JSON object in the following format, ALWAYS using "GAIN" as the parameter_id:
        {"command": "set_parameter", "parameter_id": "GAIN", "value": <float_value>}
        Replace <float_value> with the numerical value requested.
        For example, if the user says "Set gain to -6dB", respond with:
        {"command": "set_parameter", "parameter_id": "GAIN", "value": -6.0}
        If the user asks to change a *different* specific parameter (that isn't gain/volume/level), use its correct ID if you know it.
        If the user asks a general question or makes a request you cannot fulfill with a parameter change, respond normally in plain text.
        """

        // Combine system instruction with user input
        let fullPrompt = "\(systemInstruction)\n\nUser Request: \(input)"
        // --- End System Instruction ---

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": fullPrompt]]] // Use the combined prompt
            ]
            // TODO: Consider adding system_instruction field if API supports it better
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        logger.info("Sending request to Gemini model \(self.modelName): \(input)")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Response not HTTP")
                throw NetworkError.invalidResponse(0, "No HTTP response")
            }
            
            let responseBody = String(data: data, encoding: .utf8) ?? "No body"
            logger.debug("Raw response: \(responseBody)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("Invalid response: \(httpResponse.statusCode) - \(responseBody)")
                throw NetworkError.invalidResponse(httpResponse.statusCode, responseBody)
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("Failed to parse JSON: \(responseBody)")
                throw NetworkError.decodingFailed(responseBody)
            }
            
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                logger.error("Gemini API error: \(message)")
                throw NetworkError.invalidResponse(httpResponse.statusCode, message)
            }
            
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                logger.error("Failed to decode Gemini response: \(responseBody)")
                throw NetworkError.decodingFailed(responseBody)
            }
            
            logger.info("Received response from \(self.modelName): \(text)")
            return text
        } catch let error as URLError {
            logger.error("Network error: \(error.localizedDescription) - Code: \(error.code.rawValue)")
            throw NetworkError.networkUnreachable("\(error.localizedDescription) (Code: \(error.code.rawValue))")
        } catch {
            logger.error("Unexpected error: \(error.localizedDescription)")
            throw error
        }
    }
}
