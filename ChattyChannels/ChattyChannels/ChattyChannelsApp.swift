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
/// ## Example JSON
/// ```json
/// {
///     "command": "set_parameter",
///     "parameter_id": "GAIN",
///     "value": -6.0
/// }
/// ```
///
/// The application relies on this specific structure to parse commands from the AI
/// and transform them into OSC messages that can control parameters in Logic Pro.
///
/// ## Usage
/// ```swift
/// // Parse JSON from AI response
/// let decoder = JSONDecoder()
/// let command = try decoder.decode(ParameterCommand.self, from: jsonData)
///
/// // Use the parsed command
/// if command.command == "set_parameter" {
///     oscService.sendParameterChange(
///         parameterID: command.parameter_id,
///         value: command.value
///     )
/// }
/// ```
struct ParameterCommand: Decodable {
    /// The type of command, typically "set_parameter".
    ///
    /// This field indicates what action should be performed. Currently,
    /// the system only supports "set_parameter" commands.
    let command: String
    
    /// The identifier of the parameter to modify (e.g., "GAIN").
    ///
    /// This field matches the JSON key in the AI response and identifies
    /// which audio parameter should be adjusted.
    let parameter_id: String // Matches JSON key
    
    /// The new value to set for the parameter (e.g., -6.0 for -6dB).
    ///
    /// This field contains the numeric value that should be applied to
    /// the specified parameter.
    let value: Float         // Matches JSON key
}

/// The main application entry point for ChattyChannels.
///
/// ChattyChannels serves as a control room that bridges natural language interaction
/// with audio parameter control. It connects AI services (via NetworkService) with
/// audio plugins (via OSCService) to create an intelligent audio production assistant.
///
/// ## Features
///
/// - Natural language control of audio parameters through AI
/// - Automatic parameter command detection and routing
/// - Direct handling of common parameter adjustments like gain changes
/// - Bidirectional communication with Logic Pro plugins
/// - Response caching and optimization for real-time performance
///
/// ## Architecture
///
/// The app follows a modular architecture with clear separation of concerns:
///
/// - `NetworkService`: Handles AI API communication
/// - `OSCService`: Manages low-level Open Sound Control protocol
/// - `ChattyChannelsApp`: Coordinates the flow between services
///
/// ## Components
///
/// The main components interact in a reactive pipeline:
/// 1. User messages arrive via the OSC service
/// 2. Messages are sent to the AI via NetworkService
/// 3. AI responses are parsed for parameter commands
/// 4. Commands are translated to OSC messages and sent to Logic Pro
/// 5. Feedback is provided to the user via the OSC response channel
@main
struct ChattyChannelsApp: App {
    /// The OSC service responsible for communication with Logic Pro plugins.
    @StateObject private var oscService: OSCService
    
    /// The network service for communicating with AI APIs.
    @StateObject private var networkService = NetworkService()
    
    /// The Logic parameter service for controlling Logic Pro via AppleScript.
    @StateObject private var logicParameterService = LogicParameterService()

    // Services for VU Meter and Calibration
    @StateObject private var levelMeterService = LevelMeterService()
    @StateObject private var trackMappingService = TrackMappingService()
    @StateObject private var appleScriptService = AppleScriptService() // Assuming default ProcessRunner
    @StateObject private var calibrationService: CalibrationService
    
    // OSC Listener for receiving RMS data from plugins
    @StateObject private var oscListener: OSCListener
    
    // Simulation Service for testing
    @StateObject private var simulationService: SimulationService

    /// System logger for application-level events.
    ///
    /// Used to record significant application events for debugging and auditing.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "App")

    /// Storage for active Combine subscriptions to prevent premature cancellation.
    ///
    /// Holds references to subscription objects to keep them alive throughout
    /// the application lifecycle.
    @State private var cancellables = Set<AnyCancellable>()

    /// The main scene configuration for the app.
    ///
    /// Sets up the primary window and injects the network service into the view hierarchy.
    /// Also initiates the service subscription setup when the view appears.
    var body: some Scene {
        WindowGroup {
            ContentView() // Back to original ContentView with ZStack wooden strip
                .environmentObject(networkService)
                .environmentObject(oscService)
                .environmentObject(levelMeterService)
                .environmentObject(calibrationService)
                .environmentObject(trackMappingService)
                .environmentObject(oscListener)
                .task { // Use .task for async setup tied to the Scene lifecycle
                    setupServiceSubscription()

                    // Initialize PostgreSQL database
                    do {
                        logger.info("Initializing PostgreSQL database...")
                        try await DatabaseConfiguration.shared.initialize()

                        // Setup default project (you can change this to the actual Logic project name)
                        try await DatabaseConfiguration.shared.setupProject(
                            name: "Default Project",
                            logicProjectPath: nil
                        )

                        logger.info("PostgreSQL database initialized successfully")
                    } catch {
                        logger.error("Failed to initialize PostgreSQL database: \(error.localizedDescription)")
                        logger.warning("Continuing without database - some features may not work")
                    }

                    // Start OSC Listener to receive RMS data from AIPlayer plugins
                    do {
                        try await oscListener.startListening()
                        logger.info("OSC Listener started successfully on port \(oscListener.listenPort)")
                    } catch {
                        logger.error("Failed to start OSC Listener: \(error.localizedDescription)")
                    }

                    // Auto-start simulation for testing - DISABLED for v0.7 OSC integration
                    // Real RMS data should come from AIPlayer plugin via OSC
                    #if DEBUG && false  // Disabled for v0.7
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                        simulationService.startSimulation(direct: true)
                    } catch {
                        logger.error("Error starting simulation: \(error.localizedDescription)")
                    }
                    #endif
                }
        }
        .commands {
            CommandMenu("Tools") {
                Button("Test Input Gain Movement") {
                    Task {
                        await calibrationService.testInputGainMovement()
                    }
                }
                .keyboardShortcut("T", modifiers: [.command, .shift])
                
                Button("Calibrate VU Meters") {
                    Task {
                        await calibrationService.startOscillatorBasedCalibration()
                    }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                
                Divider()
                
                Button(simulationService.isSimulating ? "Stop Simulation" : "Start Simulation") {
                    if simulationService.isSimulating {
                        simulationService.stopSimulation()
                    } else {
                        simulationService.startSimulation()
                    }
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])
            }
        }
    }

    init() {
        // Initialize services that depend on each other
        let lmService = LevelMeterService()
        let oscSvc = OSCService(levelMeterService: lmService) // OSCService now takes LevelMeterService
        let tms = TrackMappingService()
        let asService = AppleScriptService() // Assuming default ProcessRunner

        _levelMeterService = StateObject(wrappedValue: lmService)
        _oscService = StateObject(wrappedValue: oscSvc)
        _trackMappingService = StateObject(wrappedValue: tms)
        _appleScriptService = StateObject(wrappedValue: asService)
        
        // CalibrationService depends on other services
        _calibrationService = StateObject(wrappedValue: CalibrationService(
            trackMappingService: tms,
            appleScriptService: asService,
            oscService: oscSvc
        ))
        
        // Initialize OSC Listener
        _oscListener = StateObject(wrappedValue: OSCListener(oscService: oscSvc, port: 8999))
        
        // Initialize simulation service
        _simulationService = StateObject(wrappedValue: SimulationService(
            levelMeterService: lmService,
            oscService: oscSvc
        ))
        
        // Ensure OSCService has the LevelMeterService instance
        oscSvc.setLevelMeterService(lmService)
    }
    
    /// Handles a parameter change request for Logic Pro.
    ///
    /// This method processes a parameter change command, executes it via the
    /// LogicParameterService, and sends appropriate feedback to the user.
    ///
    /// - Parameters:
    ///   - parameterID: The parameter to change (e.g., "GAIN").
    ///   - value: The value change (positive for increase, negative for decrease).
    ///   - trackName: Target track name. Defaults to "Kick" for v0.5.
    ///   - absolute: Whether value is absolute or relative. Defaults to false (relative).
    ///
    /// - Returns: Whether the command was successfully handled.
    private func handleParameterChange(
        parameterID: String,
        value: Float,
        trackName: String = "Kick",
        absolute: Bool = false
    ) async -> Bool {
        self.logger.info("Processing \(absolute ? "absolute" : "relative") parameter change: \(parameterID)=\(value) for track '\(trackName)'")
        
        do {
            // Execute parameter change via Logic Pro
            let result = try await logicParameterService.adjustParameter(
                trackName: trackName,
                parameterID: parameterID,
                valueChange: value,
                absolute: absolute
            )
            
            // Prepare appropriate confirmation message
            let action = absolute ? "set" : (value >= 0 ? "increased" : "decreased")
            let changeAmount = absolute ? "to" : "by"
            let valueStr = String(format: "%.1f", abs(value))
            let finalValueStr = String(format: "%.1f", result.newValue)
            
            let confirmationMessage = "OK, \(action) \(parameterID) \(changeAmount) \(valueStr) dB on \(trackName) track. " +
                                   "Final value: \(finalValueStr) dB (converged in \(result.iterations) steps)." 
            
            self.logger.info("Parameter change successful: \(confirmationMessage)")
            self.oscService.sendResponse(message: confirmationMessage)
            return true
            
        } catch {
            // Handle errors (track not found, Logic not running, etc.)
            let errorMessage = "Error adjusting \(parameterID): \(error.localizedDescription)"
            self.logger.error("\(errorMessage)")
            self.oscService.sendResponse(message: errorMessage)
            return false
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
    ///
    /// ## Flow
    /// 1. Listen for chat requests coming from OSC
    /// 2. For each request, call the NetworkService to get AI responses
    /// 3. Parse the AI response for parameter commands
    /// 4. Handle special cases like direct gain adjustments
    /// 5. Send appropriate parameter changes or text responses back via OSC
    private func setupServiceSubscription() {
        logger.info("Setting up OSCService to NetworkService subscription.")

        oscService.chatRequestPublisherPublisher
            .compactMap { $0 } // Unwrap optional ChatRequest
            .sink { request in // Remove [weak self] for struct
                let service = self.oscService
                
                // Store the original request message in a local variable to ensure it doesn't get lost
                let userMessageText = request.userMessage
                
                self.logger.info("Received chat request via OSC: ID=\(request.instanceID), Msg='\(userMessageText)'")

                // Call NetworkService asynchronously
                Task {
                    do {
                        // Make a local copy of the user message to ensure it doesn't get lost
                        let safeUserMessage = userMessageText
                        self.logger.debug("Sending message to NetworkService: '\(safeUserMessage)'")
                        
                        // Check if this is a direct command to reduce gain before using NetworkService
                        let lowercasedMessage = safeUserMessage.lowercased()
                        var commandSent = false
                        
                        // Handle direct gain reduction commands
                        if lowercasedMessage.contains("reduce gain") || lowercasedMessage.contains("decrease gain") {
                            // Extract dB value from the message
                            let pattern = "(reduce|decrease)\\s+gain\\s+by\\s+([0-9.]+)\\s*db"
                            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                                let nsString = lowercasedMessage as NSString
                                let matches = regex.matches(in: lowercasedMessage, options: [], range: NSRange(location: 0, length: nsString.length))
                                
                                if let match = matches.first, match.numberOfRanges > 2 {
                                    let dbValueRange = match.range(at: 2)
                                    if dbValueRange.location != NSNotFound,
                                       let dbValue = Float(nsString.substring(with: dbValueRange)) {
                                        // Create a direct parameter command
                                        self.logger.info("Directly handling gain reduction of \(dbValue) dB")
                                        
                                        // Use LogicParameterService to control Logic Pro via AppleScript
                                        commandSent = await self.handleParameterChange(
                                            parameterID: "GAIN",
                                            value: -dbValue, // Negative for reduction
                                            trackName: "Kick"
                                        )
                                        
                                        // If AppleScript control fails, fall back to OSC messaging
                                        if !commandSent {
                                            // Use negative value for reduction
                                            self.oscService.sendParameterChange(parameterID: "GAIN", value: -dbValue)
                                            let confirmationMessage = "OK, reducing GAIN by \(String(format: "%.1f", dbValue)) dB."
                                            self.logger.info("Sending fallback confirmation message: \(confirmationMessage)")
                                            self.oscService.sendResponse(message: confirmationMessage)
                                            commandSent = true
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Only if direct command processing didn't work, try parsing AI response
                        if !commandSent {
                            // Only call the AI if we haven't already handled the command
                            let aiResponse = try await self.networkService.sendMessage(safeUserMessage)
                            self.logger.info("Received AI response: '\(aiResponse)'")
                            
                            // --- Attempt to parse AI response as a command ---
                            // Strip Markdown fences and whitespace before parsing
                            let cleanedResponse = aiResponse
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .replacingOccurrences(of: "```json", with: "")
                                .replacingOccurrences(of: "```", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
    
                            if let responseData = cleanedResponse.data(using: .utf8) {
                                do {
                                    let decoder = JSONDecoder()
                                    let parsedCommand = try decoder.decode(ParameterCommand.self, from: responseData)

                                    // Check if it's the command we expect
                                    if parsedCommand.command == "set_parameter" {
                                        // Use the parameter ID directly from the parsed command
                                        let targetParameterID = parsedCommand.parameter_id
                                        self.logger.info("Parsed parameter command: ID=\(targetParameterID), Value=\(parsedCommand.value)")
                                        
                                        // First try to execute via LogicParameterService (AppleScript)
                                        commandSent = await self.handleParameterChange(
                                            parameterID: targetParameterID,
                                            value: parsedCommand.value,
                                            absolute: true // AI gives absolute values
                                        )
                                        
                                        // If AppleScript control fails, fall back to OSC messaging
                                        if !commandSent {
                                            // Send the specific parameter change command via OSC
                                            self.oscService.sendParameterChange(parameterID: targetParameterID, value: parsedCommand.value)
                                            
                                            // ALSO send a confirmation message back to the chat UI
                                            let confirmationMessage = "OK, setting \(targetParameterID) to \(String(format: "%.1f", parsedCommand.value)) dB."
                                            self.logger.info("Sending fallback confirmation message to plugin chat: \(confirmationMessage)")
                                            self.oscService.sendResponse(message: confirmationMessage)
                                            commandSent = true
                                        }
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
                        }
                        // --- End Command Parsing ---

                    } catch {
                        self.logger.error("Error during AI request or OSC response: \(error.localizedDescription)")
                        // Optionally send an error message back via OSC
                        service.sendResponse(message: "Error: Could not process request.")
                    }
                }
            }
            .store(in: &cancellables) // Store subscription to keep it alive

        logger.info("Subscription setup complete.")
    }
}
