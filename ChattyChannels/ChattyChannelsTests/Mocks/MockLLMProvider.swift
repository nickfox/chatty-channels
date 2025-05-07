// ChattyChannels/ChattyChannelsTests/Mocks/MockLLMProvider.swift

import Foundation
@testable import ChattyChannels // Import the main module to access LLMProvider

/// A mock implementation of `LLMProvider` for testing purposes.
///
/// Allows controlling the response or error returned by `sendMessage` and
/// tracking whether the method was called and with what arguments.
class MockLLMProvider: LLMProvider {

    // MARK: - Test Configuration
    
    /// The response string to return upon a successful `sendMessage` call.
    var mockResponse: String?
    
    /// The error to throw upon a failed `sendMessage` call.
    var mockError: Error?

    // MARK: - Call Tracking
    
    /// Indicates whether `sendMessage` was called.
    private(set) var sendMessageCalled = false
    
    /// Stores the `input` argument received by the last call to `sendMessage`.
    private(set) var lastInputReceived: String?
    
    /// Stores the `systemPrompt` argument received by the last call to `sendMessage`.
    private(set) var lastSystemPromptReceived: String?

    // MARK: - LLMProvider Conformance

    /// Required initializer. Does not need specific implementation for the mock.
    required init(apiKey: String, modelName: String?, endpoint: String?) {
        // No specific setup needed for the mock based on these params,
        // but we need to conform to the protocol.
    }
    
    /// Simulates sending a message.
    ///
    /// Based on the `mockResponse` and `mockError` properties, this method will
    /// either return the configured response or throw the configured error.
    /// It also records that it was called and captures the arguments.
    func sendMessage(_ input: String, systemPrompt: String) async throws -> String {
        sendMessageCalled = true
        lastInputReceived = input
        lastSystemPromptReceived = systemPrompt

        if let error = mockError {
            throw error
        }
        
        if let response = mockResponse {
            return response
        }
        
        // Default behavior if neither response nor error is set
        throw NetworkError.requestFailed("MockLLMProvider was called but not configured with a response or error.")
    }
    
    /// Resets the call tracking properties.
    func reset() {
        sendMessageCalled = false
        lastInputReceived = nil
        lastSystemPromptReceived = nil
        mockResponse = nil
        mockError = nil
    }
}