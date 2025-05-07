// ChattyChannels/ChattyChannelsTests/OpenAIProviderTests.swift

import XCTest
@testable import ChattyChannels // Import the main module

@MainActor // Run tests on the main actor if provider interacts with MainActor types (though less critical here)
final class OpenAIProviderTests: XCTestCase {

    var mockSession: URLSession!
    var provider: OpenAIProvider!
    let dummyApiKey = "test-openai-key"
    let defaultModel = "gpt-4o-mini" // Match the default in OpenAIProvider
    let defaultEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    override func setUpWithError() throws {
        // Set up the mock URL session before each test
        mockSession = MockURLProtocol.createMockSession()
        // Reset mocks to ensure clean state for each test
        MockURLProtocol.resetMocks()
        
        // Initialize the provider with the mock session
        provider = OpenAIProvider(apiKey: dummyApiKey, urlSession: mockSession)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.resetMocks()
        mockSession = nil
        provider = nil
    }

    // Helper to encode JSON request body for comparison
    private func encodeRequest(_ requestBody: OAChatRequest) throws -> Data {
        return try JSONEncoder().encode(requestBody)
    }
    
    // Helper to create mock response data
    private func createMockResponseData(content: String) throws -> Data {
        let response = OAChatResponse(choices: [
            .init(message: .init(content: content))
        ])
        return try JSONEncoder().encode(response)
    }
  
    func testSendMessage_ApiError() async throws {
        // Arrange
        let input = "Test prompt for error"
        let systemPrompt = "System instruction"
        let errorStatusCode = 400
        let errorResponseBody = #"{"error": {"message": "Bad request", "type": "invalid_request_error"}}"#
        let errorResponseData = errorResponseBody.data(using: .utf8)!

        // Set up mock error response
        MockURLProtocol.requestHandler = { request in
             guard let response = HTTPURLResponse(url: self.defaultEndpoint, statusCode: errorStatusCode, httpVersion: nil, headerFields: nil) else {
                 XCTFail("Failed to create mock error HTTPURLResponse")
                 throw NetworkError.requestFailed("Mock response creation failed")
             }
            return .success((errorResponseData, response)) // Simulate receiving an error body with non-2xx status
        }

        // Act & Assert
        do {
            _ = try await provider.sendMessage(input, systemPrompt: systemPrompt)
            XCTFail("sendMessage should have thrown a NetworkError.invalidResponse")
        } catch NetworkError.invalidResponse(let statusCode, let body) {
            XCTAssertEqual(statusCode, errorStatusCode, "Status code should match the mock error")
            XCTAssertEqual(body, "OpenAI API Error: \(errorResponseBody)", "Error body should match the mock error, including prefix")
        } catch {
            XCTFail("sendMessage threw an unexpected error type: \(error)")
        }
    }
    
    func testSendMessage_NetworkError() async throws {
        // Arrange
        let input = "Test prompt for network error"
        let systemPrompt = "System instruction"
        let expectedError = URLError(.notConnectedToInternet)

        // Set up mock network error
        MockURLProtocol.requestHandler = { request in
            return .failure(expectedError)
        }

        // Act & Assert
        do {
            _ = try await provider.sendMessage(input, systemPrompt: systemPrompt)
            XCTFail("sendMessage should have thrown a NetworkError.networkUnreachable")
        } catch NetworkError.networkUnreachable(let message) {
            // Check if the underlying error message is included
            XCTAssertTrue(message.contains(expectedError.localizedDescription), "Error message should contain the URLError description")
        } catch {
            XCTFail("sendMessage threw an unexpected error type: \(error)")
        }
    }
    
    func testSendMessage_DecodingError() async throws {
        // Arrange
        let input = "Test prompt for decoding error"
        let systemPrompt = "System instruction"
        let malformedJsonData = "{\"invalid_json\": }".data(using: .utf8)! // Malformed JSON

        // Set up mock response with malformed data but 200 status
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
            XCTFail("sendMessage should have thrown a NetworkError.decodingFailed")
        } catch NetworkError.decodingFailed(let message) {
            // Check if the error message indicates a decoding issue
            XCTAssertTrue(message.lowercased().contains("decoding"), "Error message should indicate decoding failure")
            XCTAssertTrue(message.contains(String(data: malformedJsonData, encoding: .utf8)!), "Error message should contain the raw response body")
        } catch {
            XCTFail("sendMessage threw an unexpected error type: \(error)")
        }
    }
}

// MARK: - Helper Structs (Mirroring private DTOs for encoding tests)
// These need to be defined here because the originals in OpenAIProvider are private.

private struct OAChatMessage: Codable, Equatable {
    let role: String
    let content: String
}
 
private struct OAChatRequest: Codable, Equatable { // Changed from Encodable to Codable
    let model: String
    let messages: [OAChatMessage]
}

private struct OAChatResponse: Codable { // Changed Decodable to Codable
     struct Choice: Codable { // Changed Decodable to Codable
         struct ChoiceMessage: Codable { // Changed Decodable to Codable
             let content: String
         }
         let message: ChoiceMessage
     }
     let choices: [Choice]
 }