// ChattyChannels/ChattyChannels/OSCService.swift

/// OSCService handles communication with Logic Pro plugins via the Open Sound Control protocol.
///
/// This service manages bidirectional communication between the ChattyChannels app and
/// audio plugins in Logic Pro. It can receive chat requests from plugins, publish them
/// to the app, and send responses and parameter changes back to the plugins.
import Foundation
import OSCKit
import Combine
import OSLog

/// Represents a chat request received via OSC from a Logic Pro plugin.
///
/// This structure encapsulates the information received from a plugin when
/// a user wants to send a message to the AI service.
struct OSCChatRequest {
    /// The unique identifier for the plugin instance that sent the request.
    let instanceID: Int
    
    /// The text message that the user input in the plugin interface.
    let userMessage: String
}

/// Service responsible for handling OSC communication with Logic Pro plugins.
///
/// OSCService creates a bidirectional communication channel between the app and plugins:
/// - It receives chat requests from plugins via OSC
/// - It publishes these requests to the app via Combine
/// - It sends responses back to plugins
/// - It sends parameter change commands to plugins
///
/// The service uses OSCKit to handle the low-level OSC protocol details.
final class OSCService: ObservableObject {

    /// System logger for OSC-related events.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "OSCService")

    /// OSC server for receiving messages from plugins.
    private var oscServer: OSCServer?
    
    /// OSC client for sending messages to plugins.
    private let oscClient = OSCClient()

    /// Publisher that emits chat requests received from plugins.
    ///
    /// Subscribers to this publisher will receive OSCChatRequest objects
    /// whenever a chat request is received via OSC from a plugin.
    let chatRequestPublisher = PassthroughSubject<OSCChatRequest, Never>()

    // MARK: - Configuration Constants
    
    /// Port on which to receive OSC messages from plugins.
    private let receivePort: UInt16 = 9001
    
    /// Port on which to send OSC messages to plugins.
    private let sendPort: UInt16 = 9000
    
    /// IP address to which to send OSC messages (localhost).
    private let sendIP = "127.0.0.1"
    
    /// OSC address pattern for receiving chat requests from plugins.
    private let chatRequestAddressPattern: OSCAddressPattern = "/aiplayer/chat/request"
    
    /// OSC address pattern for sending chat responses to plugins.
    private let chatResponseAddressPattern: OSCAddressPattern = "/aiplayer/chat/response"
    
    /// OSC address pattern for sending parameter change commands to plugins.
    private let setParameterAddressPattern: OSCAddressPattern = "/aiplayer/set_parameter"

    /// Initializes the OSC service and starts the OSC server.
    init() {
        setupServer()
    }

    /// Cleans up resources when the service is deallocated.
    deinit {
        stop()
    }

    // MARK: - Setup and Control

    /// Sets up the OSC server to receive messages from plugins.
    ///
    /// This method initializes the OSC server, configures its message handler,
    /// and starts it listening on the specified port. The message handler
    /// parses incoming OSC messages and publishes chat requests.
    private func setupServer() {
        // Initialize OSCServer with port and handler closure, per documentation
        oscServer = OSCServer(port: receivePort) { [weak self] message, timeTag, sourceHost, sourcePort in
            // Strong self reference
            guard let self = self else { return }

            self.logger.debug("Received OSC message: \(message) from \(sourceHost):\(sourcePort)")

            // Check if the address pattern matches the chat request pattern
            guard message.addressPattern == self.chatRequestAddressPattern else {
                self.logger.debug("Ignoring message with unexpected address: \(message.addressPattern)")
                // TODO: Could add handling for other incoming messages here if needed later
                return
            }

            // (Removed debug logging)

            // Attempt to parse the arguments: Int (instanceID), String (userMessage)
            guard message.values.count == 2,
            // Cast first value to Int32, then convert to Int
                  let instanceID32 = message.values[0] as? Int32,
                  let userMessage = message.values[1] as? String else {
                self.logger.warning("Received malformed OSC message (type mismatch or wrong count) for \(self.chatRequestAddressPattern): \(message.values)")
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

    /// Stops the OSC server and cleans up resources.
    ///
    /// This method should be called when the service is no longer needed,
    /// such as when the app is shutting down. It's automatically called in deinit.
    func stop() {
        oscServer?.stop()
        oscServer = nil
        logger.info("OSC Service stopped.")
    }

    // MARK: - Sending OSC Messages

    /// Sends the AI response back to the plugin via OSC.
    ///
    /// This method formats the AI's text response as an OSC message and sends it
    /// to the plugin, where it will be displayed in the chat interface.
    ///
    /// - Parameter message: The string response from the AI.
    func sendResponse(message: String) {
        logger.debug("Attempting to send OSC chat response: '\(message)'")
        let oscMessage = OSCMessage(chatResponseAddressPattern, values: [message])

        do {
            // Send using the OSCClient
            try oscClient.send(oscMessage, to: sendIP, port: sendPort)
            logger.info("Sent OSC chat response to \(self.sendIP):\(self.sendPort)")
        } catch {
            logger.error("Failed to send OSC chat response: \(error.localizedDescription)")
        }
    }

    /// Sends a parameter change command to the plugin via OSC.
    ///
    /// This method sends a command to change a specific parameter in the Logic Pro plugin.
    /// It's typically used when the AI interprets a user request as a parameter change
    /// command, such as "set the gain to -6dB".
    ///
    /// - Parameters:
    ///   - parameterID: The ID of the parameter to change (e.g., "GAIN").
    ///   - value: The new value for the parameter (e.g., -10.0).
    func sendParameterChange(parameterID: String, value: Float) {
        logger.debug("Attempting to send OSC parameter change: ID='\(parameterID)', Value=\(value)")
        // Arguments must match PluginProcessor: String (ID), Float (Value)
        let oscMessage = OSCMessage(setParameterAddressPattern, values: [parameterID, value])

        do {
            // Send using the OSCClient
            try oscClient.send(oscMessage, to: sendIP, port: sendPort)
            logger.info("Sent OSC parameter change (\(parameterID)=\(value)) to \(self.sendIP):\(self.sendPort)")
        } catch {
            logger.error("Failed to send OSC parameter change: \(error.localizedDescription)")
        }
    }
}