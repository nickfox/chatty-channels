// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/LogicParameterService.swift

import Foundation
import OSLog
import Combine

/// Represents the current state of a parameter adjustment operation.
///
/// This enum is used to track and communicate the status of parameter
/// change operations to the UI or other components.
public enum ParameterAdjustmentState {
    /// No parameter adjustment is currently in progress.
    case idle
    
    /// A parameter adjustment operation is in progress.
    /// - Parameter trackName: The name of the track being adjusted.
    /// - Parameter parameterID: The ID of the parameter being adjusted.
    case adjusting(trackName: String, parameterID: String)
    
    /// A parameter adjustment operation has completed successfully.
    /// - Parameter result: The result of the adjustment operation.
    case completed(result: LogicParameterService.AdjustmentResult)
    
    /// A parameter adjustment operation has failed.
    /// - Parameter error: The error that occurred.
    /// - Parameter trackName: The name of the track that was being adjusted.
    /// - Parameter parameterID: The ID of the parameter that was being adjusted.
    case failed(error: Error, trackName: String, parameterID: String)
}

/// Service that connects AI command processing with Logic Pro parameter control via AppleScript.
///
/// This service bridges between the network/OSC command layer and the AppleScript execution layer,
/// handling parameter change requests from natural language commands and executing the appropriate
/// actions in Logic Pro.
///
/// It conforms to `ObservableObject` to support SwiftUI integration and publishes state changes
/// during parameter adjustment operations.
///
/// ## Features
/// - Processes parameter commands from AI or direct user input
/// - Uses PID controller for precise convergence of volume settings
/// - Manages track mapping between user-friendly names and Logic's track names
/// - Provides feedback on command execution status
/// - Publishes state changes for UI integration
///
/// ## Usage Example
/// ```swift
/// // Create the service
/// let parameterService = LogicParameterService()
///
/// // Process a parameter change command
/// Task {
///     do {
///         let result = try await parameterService.adjustParameter(
///             trackName: "Kick", 
///             parameterID: "GAIN", 
///             valueChange: -3.0
///         )
///         print("New volume: \(result.newValue) dB")
///     } catch {
///         print("Parameter change failed: \(error)")
///     }
/// }
/// ```
public final class LogicParameterService: ObservableObject {
    /// Logger for parameter service operations.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ChattyChannels",
                                category: "LogicParameterService")
    
    /// AppleScript service for interacting with Logic Pro.
    private let appleScriptService: AppleScriptServiceProtocol
    
    /// The current state of parameter adjustment operations.
    @Published public var currentState: ParameterAdjustmentState = .idle
    
    /// Initializes the LogicParameterService.
    ///
    /// - Parameter appleScriptService: Service for AppleScript execution.
    ///   Defaults to a new instance with a playback-safe process runner.
    public init(appleScriptService: AppleScriptServiceProtocol = AppleScriptService()) {
        self.appleScriptService = appleScriptService
    }
    
    /// Result of a parameter adjustment operation.
    public struct AdjustmentResult {
        /// The parameter ID that was adjusted.
        public let parameterID: String
        
        /// The track name that was adjusted.
        public let trackName: String
        
        /// The new parameter value after adjustment.
        public let newValue: Float
        
        /// Number of PID iterations required to converge.
        public let iterations: Int
        
        /// Final error (difference between target and actual) in dB.
        public let finalError: Float
    }
    
    /// Adjusts a parameter on a specified track.
    ///
    /// This method handles the complete process of changing a parameter value:
    /// 1. Maps the user-friendly track name to Logic's internal name
    /// 2. Gets or creates a dedicated controller for the track
    /// 3. Executes the parameter change with PID feedback loop
    /// 4. Returns the result of the operation
    ///
    /// - Parameters:
    ///   - trackName: User-friendly track name (e.g., "Kick").
    ///   - parameterID: Parameter to adjust (e.g., "GAIN").
    ///   - valueChange: The amount to change the parameter by.
    ///     For GAIN, positive values increase volume, negative values decrease.
    ///   - absolute: Whether valueChange is absolute (true) or relative (false).
    ///     Default is false (relative change).
    ///
    /// - Returns: Result of the adjustment operation.
    /// - Throws: AppleScriptError if communication with Logic fails.
    public func adjustParameter(
        trackName: String,
        parameterID: String,
        valueChange: Float,
        absolute: Bool = false
    ) async throws -> AdjustmentResult {
        
        // For v0.5, we only support GAIN parameter and Kick track
        guard parameterID == "GAIN" else {
            logger.error("Unsupported parameter ID: \(parameterID). Only GAIN is supported in v0.5")
            let error = NSError(domain: "LogicParameterService", code: 1, 
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported parameter: \(parameterID)"])
            await MainActor.run {
                self.currentState = .failed(error: error, trackName: trackName, parameterID: parameterID)
            }
            throw error
        }
        
        // Map user-friendly name to Logic track name (v0.5: simple mapping)
        let logicTrackName = mapTrackName(trackName)
        logger.info("Adjusting \(parameterID) for track '\(logicTrackName)' by \(valueChange) dB")
        
        // Update state to adjusting
        await MainActor.run {
            self.currentState = .adjusting(trackName: logicTrackName, parameterID: parameterID)
        }
        
        do {
            // Determine target value
            let currentValue = try appleScriptService.getVolume(trackName: logicTrackName)
            let targetValue = absolute ? valueChange : currentValue + valueChange
            logger.info("Current value: \(currentValue) dB, Target value: \(targetValue) dB")
            
            // Execute control loop (max 5 iterations for safety)
            var iterations = 0
            var finalValue = currentValue
            var approximateTarget = false
            
            // Create a PID controller directly
            let pid = PIDController(gain: PIDGain(kp: 0.8)) // Kp = 0.8 for slight damping
            let volumeController = KickVolumeController(
                pid: pid,
                appleScriptService: appleScriptService,
                trackName: logicTrackName
            )
            
            // In v0.5, we're limiting to max 2 iterations for simplicity
            // First iteration
            finalValue = try volumeController.controlOnce(target: targetValue)
            iterations += 1
            logger.info("Iteration \(iterations): New value = \(finalValue) dB")
            
            // Check if we're close enough to target (within 0.1 dB)
            var error = abs(finalValue - targetValue)
            if error <= 0.1 {
                logger.info("Converged after \(iterations) iterations with error \(error) dB")
                approximateTarget = true
            } else {
                // Only do second iteration if needed and not close enough yet
                // Slight delay between iterations to allow Logic to process
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                
                // Second iteration
                finalValue = try volumeController.controlOnce(target: targetValue)
                iterations += 1
                logger.info("Iteration \(iterations): New value = \(finalValue) dB")
                
                // Check convergence again
                error = abs(finalValue - targetValue)
                if error <= 0.1 {
                    logger.info("Converged after \(iterations) iterations with error \(error) dB")
                    approximateTarget = true
                }
            }
            
            // If we didn't converge within 2 iterations, log a warning
            if !approximateTarget {
                logger.warning("Did not converge after \(iterations) iterations. Final value: \(finalValue) dB")
            }
            
            // Create the result
            let result = AdjustmentResult(
                parameterID: parameterID,
                trackName: logicTrackName,
                newValue: finalValue,
                iterations: iterations,
                finalError: abs(finalValue - targetValue)
            )
            
            // Update state to completed
            await MainActor.run {
                self.currentState = .completed(result: result)
            }
            
            return result
        } catch {
            // Update state to failed
            await MainActor.run {
                self.currentState = .failed(error: error, trackName: logicTrackName, parameterID: parameterID)
            }
            throw error
        }
    }
    
    /// Maps a user-friendly track name to Logic Pro's internal track name.
    ///
    /// - Parameter trackName: User-friendly track name.
    /// - Returns: Logic Pro track name.
    private func mapTrackName(_ trackName: String) -> String {
        // In v0.5, we only support simple mapping
        // For "kick" variations, return "Kick"
        if trackName.lowercased().contains("kick") {
            return "Kick"
        }
        
        // Otherwise, return the original name (may not exist in Logic)
        return trackName
    }
}
