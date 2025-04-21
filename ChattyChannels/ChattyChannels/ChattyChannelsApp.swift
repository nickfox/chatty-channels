//
//  ChattyChannelsApp.swift
//  ChattyChannels
//
//  Created by Nick on 4/1/25.
//

/// ChattyChannels is a desktop application that serves as a control room to connect
/// remote AI services with Logic Pro plugins. It enables natural language control
/// of audio parameters through an intelligent communication bridge.

import SwiftUI
import Combine // Needed for managing subscriptions
import OSLog    // For logging

/// A struct representing parameter control commands from the AI.
///
/// This structure defines the expected format for parameter control commands
/// that are decoded from AI responses. It's used when the AI determines
/// that the user is requesting a parameter change in Logic Pro.
///
/// ```json
/// {
///     "command": "set_parameter",
///     "parameter_id": "GAIN",
///     "value": -6.0
/// }
/// ```
struct ParameterCommand: Decodable {
    /// The type of command, typically "set_parameter".
    let command: String
    
    /// The identifier of the parameter to modify (e.g., "GAIN").
    let parameter_id: String // Matches JSON key
    
    /// The new value to set for the parameter (e.g., -6.0 for -6dB).
    let value: Float         // Matches JSON key
}

/// The main application entry point for ChattyChannels.
///
/// This app acts as a control room that bridges AI services with Logic Pro plugins. 
/// It manages communication between OSC-based plugins and remote AI services,
/// enabling natural language control of audio parameters.
@main
struct ChattyChannelsApp: App {
    /// The OSC service responsible for communication with Logic Pro plugins.
    @StateObject private var oscService = OSCService()
    
    /// The network service for communicating with AI APIs.
    @StateObject private var networkService = NetworkService()

    /// System logger for application-level events.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "App")

    /// Storage for active Combine subscriptions to prevent premature cancellation.
    @State private var cancellables = Set<AnyCancellable>()

    /// The main scene configuration for the app.
    ///
    /// Sets up the primary window and injects the network service into the view hierarchy.
    /// Also initiates the service subscription setup when the view appears.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(networkService) // Inject the service
                .task { // Use .task for async setup tied to the Scene lifecycle
                    setupServiceSubscription()
                }
        }
    }

    /// Sets up the subscription pipeline between OSC and Network services.
    ///
    /// This method establishes a Combine pipeline that processes OSC messages from Logic Pro plugins,
    /// sends them to the AI service, and handles the responses. It's responsible for:
    /// - Routing chat messages between the plugin and AI
    /// - Parsing parameter commands from AI responses
    /// - Sending parameter changes back to Logic Pro
    /// - Providing feedback to the user
    private func setupServiceSubscription() {
        logger.info("Setting up OSCService to NetworkService subscription.")

        oscService.chatRequestPublisher
            .sink { request in // Remove [weak self] for struct
                // No need for guard let self = self with structs
                self.logger.info("Received chat request via OSC: ID=\(request.instanceID), Msg='\(request.userMessage)'")

                // Call NetworkService asynchronously
                Task {
                    do {
                        self.logger.debug("Sending message to NetworkService...")
                        let aiResponse = try await self.networkService.sendMessage(request.userMessage)
                        self.logger.info("Received AI response: '\(aiResponse)'")

                        // --- Attempt to parse AI response as a command ---
                        // Strip Markdown fences and whitespace before parsing
                        let cleanedResponse = aiResponse
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "```json", with: "")
                            .replacingOccurrences(of: "```", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        var commandSent = false
                        if let responseData = cleanedResponse.data(using: .utf8) {
                            do {
                                let decoder = JSONDecoder()
                                let parsedCommand = try decoder.decode(ParameterCommand.self, from: responseData)

                                // Check if it's the command we expect
                                if parsedCommand.command == "set_parameter" {
                                    // Use the parameter ID directly from the parsed command
                                    let targetParameterID = parsedCommand.parameter_id
                                    self.logger.info("Parsed parameter command: ID=\(targetParameterID), Value=\(parsedCommand.value)")
                                    // Send the specific parameter change command via OSC
                                    self.oscService.sendParameterChange(parameterID: targetParameterID, value: parsedCommand.value)
                                    commandSent = true // Mark that we handled it as a command

                                    // ALSO send a confirmation message back to the chat UI
                                    let confirmationMessage = "OK, setting \(targetParameterID) to \(String(format: "%.1f", parsedCommand.value)) dB."
                                    self.logger.info("Sending confirmation message to plugin chat: \(confirmationMessage)")
                                    self.oscService.sendResponse(message: confirmationMessage)

                                } else {
                                     self.logger.debug("Parsed JSON, but command was not 'set_parameter': \(parsedCommand.command)")
                                }

                            } catch let decodingError {
                                // JSON decoding failed, likely not a command response
                                self.logger.debug("AI response is not a valid ParameterCommand JSON: \(decodingError.localizedDescription). Treating as plain text.")
                            }
                        } else {
                             self.logger.warning("Could not convert AI response string to data.")
                        }

                        // If it wasn't parsed and sent as a command (and we didn't already send a confirmation), send the original AI response as a regular chat message
                        if !commandSent {
                            self.logger.debug("Sending original AI response as plain text chat message.")
                            self.oscService.sendResponse(message: aiResponse) // Send original AI response if not a command
                        }
                        // --- End Command Parsing ---

                    } catch {
                        self.logger.error("Error during AI request or OSC response: \(error.localizedDescription)")
                        // Optionally send an error message back via OSC
                        self.oscService.sendResponse(message: "Error: Could not process request.")
                    }
                }
            }
            .store(in: &cancellables) // Store subscription to keep it alive

        logger.info("Subscription setup complete.")
    }
}
