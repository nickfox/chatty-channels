// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/NetworkService.swift
import Foundation
import Combine // Needed for ObservableObject
import os.log

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case requestFailed(String)
    case invalidResponse(Int, String)
    case decodingFailed(String)
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

final class NetworkService: ObservableObject { // Make final and conform
    // No longer a singleton
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NetworkService") // Use bundle ID
    private let modelName = "gemini-1.5-flash-latest" // Using a potentially more standard/available model

    // Public initializer
    init() {}
    
    private func loadApiKey() throws -> String {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let apiKey = config["geminiApiKey"] as? String, !apiKey.isEmpty else {
            logger.error("Missing or invalid Gemini API key in Config.plist")
            throw NetworkError.requestFailed("Missing or invalid API key")
        }
        return apiKey
    }
    
    // Renamed function to match call site
    func sendMessage(_ input: String) async throws -> String {
        let apiKey = try loadApiKey()
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)") else {
            logger.error("Invalid Gemini URL for model: \(self.modelName)")
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": input]]]
            ]
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
