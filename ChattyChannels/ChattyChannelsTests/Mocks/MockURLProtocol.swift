// ChattyChannels/ChattyChannelsTests/Mocks/MockURLProtocol.swift

import Foundation
import XCTest // Needed for XCTFail

/// A custom `URLProtocol` subclass for mocking network responses during testing.
///
/// This protocol intercepts network requests made via `URLSession` configured with it.
/// It allows defining static handlers for specific URLs or request types to return
/// predefined data, responses, or errors, enabling testing of network layer code
/// without actual network interaction.
class MockURLProtocol: URLProtocol {

    /// Dictionary to store mock responses. Key is the URL, value is the result (data, response, error).
    static var mockResponses = [URL: Result<(Data, HTTPURLResponse), Error>]()
    
    /// A general request handler closure that can be used for more complex matching or dynamic responses.
    static var requestHandler: ((URLRequest) throws -> Result<(Data, HTTPURLResponse), Error>)?

    override class func canInit(with request: URLRequest) -> Bool {
        // Handle all requests directed to this protocol.
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        // Required override, return the original request.
        return request
    }

    override func startLoading() {
        // Check if a specific handler exists for the request URL.
        if let url = request.url, let mockResponse = MockURLProtocol.mockResponses[url] {
            handleMockResponse(mockResponse)
            return
        }
        
        // Check if a general request handler is set.
        if let handler = MockURLProtocol.requestHandler {
            do {
                let result = try handler(request)
                handleMockResponse(result)
            } catch {
                // If the handler itself throws an error, report it to the client.
                client?.urlProtocol(self, didFailWithError: error)
                client?.urlProtocolDidFinishLoading(self)
            }
            return
        }

        // If no handler is found, fail the test.
        let error = NSError(domain: "MockURLProtocol", code: -1, userInfo: [NSLocalizedDescriptionKey: "No mock response or handler set for URL: \(request.url?.absoluteString ?? "nil")"])
        client?.urlProtocol(self, didFailWithError: error)
        // Optionally fail the test case immediately
        // XCTFail("No mock response or handler set for URL: \(request.url?.absoluteString ?? "nil")")
        client?.urlProtocolDidFinishLoading(self)

    }

    override func stopLoading() {
        // Required override, nothing needed here for mock.
    }
    
    /// Helper function to send the mock response back to the client.
    private func handleMockResponse(_ result: Result<(Data, HTTPURLResponse), Error>) {
        switch result {
        case .success(let (data, response)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    /// Convenience method to reset mocks between tests.
    static func resetMocks() {
        mockResponses.removeAll()
        requestHandler = nil
    }
    
    /// Creates a `URLSession` configured to use this mock protocol.
    static func createMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    
    /// Sets up a mock response for a specific URL.
    /// - Parameters:
    ///   - url: The URL to mock.
    ///   - data: The data to return. Defaults to empty data.
    ///   - statusCode: The HTTP status code. Defaults to 200.
    ///   - httpVersion: The HTTP version. Defaults to "HTTP/1.1".
    ///   - headerFields: Optional HTTP headers.
    static func setMockResponse(for url: URL, data: Data = Data(), statusCode: Int = 200, httpVersion: String = "HTTP/1.1", headerFields: [String: String]? = nil) {
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: httpVersion, headerFields: headerFields) else {
            fatalError("Failed to create mock HTTPURLResponse for URL: \(url)")
        }
        mockResponses[url] = .success((data, response))
    }
    
    /// Sets up a mock error response for a specific URL.
    /// - Parameters:
    ///   - url: The URL to mock.
    ///   - error: The error to return.
    static func setMockError(for url: URL, error: Error) {
        mockResponses[url] = .failure(error)
    }
}