// ChattyChannels/ChattyChannelsTests/ClaudeProviderTests.swift

import XCTest
@testable import ChattyChannels

@MainActor
final class ClaudeProviderTests: XCTestCase {

    var mockSession: URLSession!
    var provider: ClaudeProvider!
    let dummyApiKey = "test-claude-key"
    let defaultModel = "claude-3-5-sonnet-20240620" // Match default in ClaudeProvider
    let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    let defaultVersion = "2023-06-01" // Match default in ClaudeProvider

    override func setUpWithError() throws {
        mockSession = MockURLProtocol.createMockSession()
        MockURLProtocol.resetMocks()
        
        // Initialize provider with the mock session
        provider = ClaudeProvider(apiKey: dummyApiKey, urlSession: mockSession)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.resetMocks()
        mockSession = nil
        provider = nil
    }

    // Helper to encode request body
    private func encodeRequest(_ requestBody: ClaudeMessagesRequest) throws -> Data {
        let encoder = JSONEncoder()
        // If ClaudeProvider uses snake_case encoding, match it here:
        // encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(requestBody)
    }
    
    // Helper to create mock response data
    private func createMockResponseData(content: String) throws -> Data {
        let response = ClaudeMessagesResponse(role: "assistant", content: [.init(type: "text", text: content)])
        let decoder = JSONDecoder()
        // If ClaudeProvider uses snake_case decoding, match it here:
        // decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try JSONEncoder().encode(response) // Use Encoder here, Decoder was incorrect
    }
  
    func testSendMessage_ApiError() async throws {
        // Arrange
        let input = "Trigger Claude error"
        let systemPrompt = "System instruction"
        let errorStatusCode = 401
        let errorResponseBody = #"{"type": "error", "error": {"type": "authentication_error", "message": "Invalid API Key"}}"#
        let errorResponseData = errorResponseBody.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
             guard let response = HTTPURLResponse(url: self.defaultEndpoint, statusCode: errorStatusCode, httpVersion: nil, headerFields: nil) else {
                 XCTFail("Failed to create mock error HTTPURLResponse")
                 throw NetworkError.requestFailed("Mock response creation failed")
             }
            return .success((errorResponseData, response))
        }

        // Act & Assert
        do {
            _ = try await provider.sendMessage(input, systemPrompt: systemPrompt)
            XCTFail("Should have thrown NetworkError.invalidResponse")
        } catch NetworkError.invalidResponse(let statusCode, let body) {
            XCTAssertEqual(statusCode, errorStatusCode)
            XCTAssertTrue(body.contains("Invalid API Key"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSendMessage_NetworkError() async throws {
        // Arrange
        let input = "Test network error"
        let systemPrompt = "System instruction"
        let expectedError = URLError(.badServerResponse)

        MockURLProtocol.requestHandler = { request in
            return .failure(expectedError)
        }

        // Act & Assert
        do {
            _ = try await provider.sendMessage(input, systemPrompt: systemPrompt)
            XCTFail("Should have thrown NetworkError.networkUnreachable")
        } catch NetworkError.networkUnreachable(let message) {
            XCTAssertTrue(message.contains(expectedError.localizedDescription))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSendMessage_DecodingError() async throws {
        // Arrange
        let input = "Test decoding error"
        let systemPrompt = "System instruction"
        // Malformed: missing closing brace for content array
        let malformedJsonData = "{\"role\": \"assistant\", \"content\": [{\"type\":\"text\", \"text\":\"Hello\"}".data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
             guard let response = HTTPURLResponse(url: self.defaultEndpoint, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                 XCTFail("Failed to create mock success HTTPURLResponse")
                 throw NetworkError.requestFailed("Mock response creation failed")
             }
            return .success((malformedJsonData, response))
        }

        // Act & Assert
        do {
            _ = try await provider.sendMessage(input, systemPrompt: systemPrompt)
            XCTFail("Should have thrown NetworkError.decodingFailed")
        } catch NetworkError.decodingFailed(let message) {
            XCTAssertTrue(message.lowercased().contains("decoding"))
            XCTAssertTrue(message.contains(String(data: malformedJsonData, encoding: .utf8)!))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Helper Structs (Mirroring private DTOs)

private struct ClaudeMessage: Codable, Equatable {
    let role: String
    let content: String
}

private struct ClaudeMessagesRequest: Codable, Equatable {
    let model: String
    let system: String?
    let messages: [ClaudeMessage]
    let max_tokens: Int
    
    static func == (lhs: ClaudeMessagesRequest, rhs: ClaudeMessagesRequest) -> Bool {
        return lhs.model == rhs.model &&
               lhs.system == rhs.system &&
               lhs.messages == rhs.messages &&
               lhs.max_tokens == rhs.max_tokens
    }
}

private struct ClaudeTextBlock: Codable { // Changed Decodable to Codable
    let type: String
    let text: String
}

private struct ClaudeMessagesResponse: Codable { // Changed Decodable to Codable
    let role: String
    let content: [ClaudeTextBlock]
}