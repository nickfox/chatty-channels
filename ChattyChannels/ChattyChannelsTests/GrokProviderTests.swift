// ChattyChannels/ChattyChannelsTests/GrokProviderTests.swift

import XCTest
@testable import ChattyChannels

@MainActor
final class GrokProviderTests: XCTestCase {

    var mockSession: URLSession!
    var provider: GrokProvider!
    let dummyApiKey = "test-grok-key"
    let defaultModel = "grok-1" // Match default in GrokProvider
    let defaultEndpoint = URL(string: "https://api.x.ai/v1/chat/completions")! // Assumed endpoint

    override func setUpWithError() throws {
        mockSession = MockURLProtocol.createMockSession()
        MockURLProtocol.resetMocks()
        
        // Initialize provider with the mock session
        provider = GrokProvider(apiKey: dummyApiKey, urlSession: mockSession)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.resetMocks()
        mockSession = nil
        provider = nil
    }

    // Helper to encode request body
    private func encodeRequest(_ requestBody: GrokChatRequest) throws -> Data {
        return try JSONEncoder().encode(requestBody)
    }
    
    // Helper to create mock response data (assuming OpenAI structure)
    private func createMockResponseData(content: String) throws -> Data {
        let response = GrokChatResponse(choices: [
            .init(message: .init(role: "assistant", content: content))
        ])
        return try JSONEncoder().encode(response)
    }

    func testSendMessage_ApiError() async throws {
        // Arrange
        let input = "Trigger Grok error"
        let systemPrompt = "System instruction"
        let errorStatusCode = 403 // Example error code
        let errorResponseBody = #"{"error": {"message": "Permission denied", "code": "permission_denied"}}"# // Example error body
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
            XCTAssertTrue(body.contains("Permission denied"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSendMessage_NetworkError() async throws {
        // Arrange
        let input = "Test network error"
        let systemPrompt = "System instruction"
        let expectedError = URLError(.cannotConnectToHost)

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
        // Malformed: choices is not an array
        let malformedJsonData = "{\"choices\": {\"message\": {\"content\": \"hello\"}}}".data(using: .utf8)!

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

private struct GrokChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

private struct GrokChatRequest: Codable, Equatable {
    let model: String
    let messages: [GrokChatMessage]
}

private struct GrokChatResponse: Codable { // Changed Decodable to Codable
    struct Choice: Codable { // Changed Decodable to Codable
        struct ChoiceMessage: Codable { // Changed Decodable to Codable
            let role: String?
            let content: String?
        }
        let message: ChoiceMessage
    }
    let choices: [Choice]
}