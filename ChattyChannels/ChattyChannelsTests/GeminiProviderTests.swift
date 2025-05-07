// ChattyChannels/ChattyChannelsTests/GeminiProviderTests.swift

import XCTest
@testable import ChattyChannels

@MainActor
final class GeminiProviderTests: XCTestCase {

    var mockSession: URLSession!
    var provider: GeminiProvider!
    let dummyApiKey = "test-gemini-key"
    let defaultModel = "gemini-1.5-pro-latest" // Match default in GeminiProvider
    let googleAIBaseURL = "https://generativelanguage.googleapis.com/v1beta/models" // Hardcode base URL for test
    var defaultEndpoint: URL! // Constructed in setUp

    override func setUpWithError() throws {
        mockSession = MockURLProtocol.createMockSession()
        MockURLProtocol.resetMocks()
        
        // Construct the expected default endpoint URL using the hardcoded base URL
        defaultEndpoint = URL(string: "\(googleAIBaseURL)/\(defaultModel):generateContent")!
        
        // Initialize provider with the mock session
        provider = GeminiProvider(apiKey: dummyApiKey, urlSession: mockSession)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.resetMocks()
        mockSession = nil
        provider = nil
        defaultEndpoint = nil
    }

    // Helper to encode request body
    private func encodeRequest(_ requestBody: GeminiGenerateContentRequest) throws -> Data {
        return try JSONEncoder().encode(requestBody)
    }
    
    // Helper to create mock response data
    private func createMockResponseData(content: String) throws -> Data {
        let response = GeminiGenerateContentResponse(candidates: [
            .init(content: .init(parts: [.init(text: content)], role: "model"), finishReason: "STOP")
        ])
        return try JSONEncoder().encode(response)
    }
 
    func testSendMessage_ApiError() async throws {
        // Arrange
        let input = "Test error"
        let systemPrompt = "System instruction"
        let errorStatusCode = 400
        let errorResponseBody = #"{"error": {"message": "Invalid request", "status": "INVALID_ARGUMENT"}}"#
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
            XCTAssertTrue(body.contains("Invalid request"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testSendMessage_NetworkError() async throws {
        // Arrange
        let input = "Test network error"
        let systemPrompt = "System instruction"
        let expectedError = URLError(.timedOut)

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
        let malformedJsonData = "{\"candidates\": [{\"content\": {\"parts\": [{\"text\":\"Hello\"}]".data(using: .utf8)! // Malformed

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

private enum GeminiRole: String, Codable { case user, model }
private struct GeminiPart: Codable, Equatable { let text: String }
private struct GeminiContent: Codable, Equatable { let role: String; let parts: [GeminiPart] }

// Mirroring provider's DTOs for safety and generation config
private struct GeminiSafetySetting: Codable, Equatable {
    let category: String
    let threshold: String
}

private struct GeminiGenerationConfig: Codable, Equatable {
    let temperature: Double?
    let topP: Double?
    let topK: Int?
    let maxOutputTokens: Int?
}

private struct GeminiGenerateContentRequest: Codable, Equatable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiContent?
    let safetySettings: [GeminiSafetySetting]?
    let generationConfig: GeminiGenerationConfig?
    
    static func == (lhs: GeminiGenerateContentRequest, rhs: GeminiGenerateContentRequest) -> Bool {
        return lhs.contents == rhs.contents &&
               lhs.systemInstruction == rhs.systemInstruction &&
               lhs.safetySettings == rhs.safetySettings &&
               lhs.generationConfig == rhs.generationConfig
    }
}
private struct GeminiCandidate: Codable {
    struct CandidateContent: Codable { let parts: [GeminiPart]; let role: String? }
    let content: CandidateContent?
    let finishReason: String?
}
private struct GeminiGenerateContentResponse: Codable { let candidates: [GeminiCandidate]? } // Changed Decodable to Codable