// ChattyChannels/ChattyChannels/OSCService.swift

import Foundation
import OSCKit
import Combine
import OSLog

/// Represents a chat request received via OSC.
struct OSCChatRequest {
    let instanceID: Int
    let userMessage: String
}

/// Service responsible for handling OSC communication (sending/receiving) using OSCKit.
final class OSCService: ObservableObject {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "OSCService")

    // OSC Server for receiving messages
    private var oscServer: OSCServer?
    // OSC Client for sending messages
    private let oscClient = OSCClient()

    // Publisher for incoming chat requests
    let chatRequestPublisher = PassthroughSubject<OSCChatRequest, Never>()

    // MARK: - Configuration Constants
    private let receivePort: UInt16 = 9001
    private let sendPort: UInt16 = 9000
    private let sendIP = "127.0.0.1" // Localhost for sending back to plugins
    private let expectedAddressPattern: OSCAddressPattern = "/aiplayer/chat/request"
    private let responseAddressPattern: OSCAddressPattern = "/aiplayer/chat/response"

    init() {
        setupServer()
    }

    deinit {
        stop()
    }

    // MARK: - Setup and Control

    private func setupServer() {
        // Initialize OSCServer with port and handler closure, per documentation
        oscServer = OSCServer(port: receivePort) { [weak self] message, timeTag, sourceHost, sourcePort in
            // Strong self reference
            guard let self = self else { return }

            self.logger.debug("Received OSC message: \(message) from \(sourceHost):\(sourcePort)")

            // Check if the address pattern matches what we expect
            guard message.addressPattern == self.expectedAddressPattern else {
                self.logger.debug("Ignoring message with unexpected address: \(message.addressPattern)")
                return
            }

            // (Removed debug logging)

            // Attempt to parse the arguments: Int (instanceID), String (userMessage)
            guard message.values.count == 2,
            // Cast first value to Int32, then convert to Int
                  let instanceID32 = message.values[0] as? Int32,
                  let userMessage = message.values[1] as? String else {
                self.logger.warning("Received malformed OSC message (type mismatch or wrong count) for \(self.expectedAddressPattern): \(message.values)")
                return
            }
            let instanceID = Int(instanceID32) // Convert Int32 to Int

            self.logger.info("Parsed valid chat request: ID=\(instanceID), Message='\(userMessage)'")

            // Create the request object
            let request = OSCChatRequest(instanceID: instanceID, userMessage: userMessage)

            // Publish the request
            self.chatRequestPublisher.send(request)

        } // End of handler closure

        // Optional: Set timeTagMode or receiveQueue if needed, defaults are often sufficient
        // oscServer?.timeTagMode = .serverBased()
        // oscServer?.receiveQueue = .main // Or background

        do {
            try oscServer?.start()
            logger.info("OSC Server started listening on port \(self.receivePort)")
        } catch {
            logger.error("Failed to start OSC Server: \(error.localizedDescription)")
            oscServer = nil // Ensure server is nil if start failed
        }
    }

    /// Stops the OSC server.
    func stop() {
        oscServer?.stop()
        oscServer = nil
        logger.info("OSC Service stopped.")
    }

    // MARK: - Sending OSC Messages

    /// Sends the AI response back to the plugin via OSC.
    /// - Parameter response: The string response from the AI.
    func sendResponse(message: String) {
        logger.debug("Attempting to send OSC response: '\(message)'")
        let oscMessage = OSCMessage(responseAddressPattern, values: [message])

        do {
            // Send using the OSCClient
            try oscClient.send(oscMessage, to: sendIP, port: sendPort)
            logger.info("Sent OSC response to \(self.sendIP):\(self.sendPort)")
        } catch {
            logger.error("Failed to send OSC response: \(error.localizedDescription)")
        }
    }
}