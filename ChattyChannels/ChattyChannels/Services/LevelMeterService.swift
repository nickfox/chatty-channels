// LevelMeterService.swift
//
// Service for processing and providing audio level data to the VU meter

import Foundation
import Combine
import SwiftUI
import os.log

/// Service that processes and provides audio level data for multiple tracks,
/// keyed by their Logic Pro Track UUID.
@MainActor
public class LevelMeterService: ObservableObject {
    /// Published dictionary of audio levels, keyed by `logicTrackUUID`.
    @Published public var audioLevels: [String: AudioLevel] = [:]
    
    /// Published current track name for compatibility with v0.6 UI
    @Published public var currentTrack: String = "Master Bus"
    
    /// Compatibility properties for v0.6 UI - mapping between old channel-based and new track-based system
    @Published public var leftChannel = AudioLevel(id: "LEFT", rmsValue: 0.0, peakRmsValue: 0.0, trackName: "Master Bus")
    @Published public var rightChannel = AudioLevel(id: "RIGHT", rmsValue: 0.0, peakRmsValue: 0.0, trackName: "Master Bus")
    
    /// System logger for level meter events.
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "LevelMeterService")
        
    /// Peak decay rate (e.g., 0.99 means 1% decay per update cycle if not refreshed).
    private let peakDecayRate: Float = 0.995
    private var peakDecayTimer: Timer?

    // Master bus UUID - would come from configuration normally
    private let masterBusUUID = "MASTER_BUS_UUID"

    /// Initializes the service.
    public init() {
        logger.info("LevelMeterService initialized")
        // Set up default master bus audio level
        audioLevels[masterBusUUID] = AudioLevel(id: masterBusUUID, rmsValue: 0.0, peakRmsValue: 0.0, trackName: "Master Bus")
        startPeakDecayTimer()
        
        // Start a timer to update the v0.6 compatibility properties from the master bus data
        startCompatibilityTimer()
    }
    
    /// Updates the audio level for a specific track.
    /// This method is intended to be called by `OSCService` when identified RMS data is received.
    /// - Parameters:
    ///   - logicTrackUUID: The unique identifier of the track.
    ///   - rmsValue: The new RMS value (0.0 to 1.0).
    ///   - peakRmsValueOverride: Optional peak value if provided directly by the source.
    public func updateLevel(logicTrackUUID: String, rmsValue: Float, peakRmsValueOverride: Float? = nil) {
        var level = audioLevels[logicTrackUUID] ?? AudioLevel(id: logicTrackUUID)
        
        level.rmsValue = max(0.0, min(1.0, rmsValue)) // Clamp value
        
        if let peakOverride = peakRmsValueOverride {
            level.peakRmsValue = max(level.peakRmsValue, max(0.0, min(1.0, peakOverride)))
        } else {
            level.peakRmsValue = max(level.peakRmsValue, level.rmsValue)
        }
        level.lastUpdateTime = Date()
        
        audioLevels[logicTrackUUID] = level
        
        // If this is the master bus, update the current track name for UI compatibility
        if logicTrackUUID == masterBusUUID {
            if let trackName = level.trackName {
                currentTrack = trackName
            }
            
            // Update v0.6 compatibility properties immediately for the master bus
            updateCompatibilityChannels(from: level)
        }
        
        // Removed excessive debug logging - this was generating thousands of log entries per second
        // logger.debug("Updated level for \(logicTrackUUID, privacy: .public): RMS \(level.rmsValue, privacy: .public), Peak \(level.peakRmsValue, privacy: .public)")
    }
    
    /// Updates the v0.6 compatibility channel properties from the master bus data
    private func updateCompatibilityChannels(from masterLevel: AudioLevel) {
        leftChannel = AudioLevel(id: "LEFT", rmsValue: masterLevel.rmsValue, peakRmsValue: masterLevel.peakRmsValue, trackName: masterLevel.trackName)
        rightChannel = AudioLevel(id: "RIGHT", rmsValue: masterLevel.rmsValue, peakRmsValue: masterLevel.peakRmsValue, trackName: masterLevel.trackName)
    }
    
    /// Starts a timer to update the v0.6 compatibility properties from the master bus data
    private func startCompatibilityTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if let masterLevel = self.audioLevels[self.masterBusUUID] {
                    self.updateCompatibilityChannels(from: masterLevel)
                }
            }
        }
    }
    
    /// Sets the current track name - for compatibility with v0.6 UI
    public func setCurrentTrack(_ name: String) {
        currentTrack = name
        
        // Also update the track name in the master bus AudioLevel
        if var masterLevel = audioLevels[masterBusUUID] {
            masterLevel.trackName = name
            audioLevels[masterBusUUID] = masterLevel
            
            // Also update compatibility channels
            leftChannel.trackName = name
            rightChannel.trackName = name
        } else {
            // Create a new master bus level if it doesn't exist
            audioLevels[masterBusUUID] = AudioLevel(id: masterBusUUID, rmsValue: 0.0, peakRmsValue: 0.0, trackName: name)
        }
        
        logger.info("Track set to: \(name)")
    }
    
    /// Resets the peak value for a specific track.
    /// - Parameter logicTrackUUID: The identifier of the track whose peak should be reset.
    public func resetPeak(for logicTrackUUID: String) {
        if audioLevels[logicTrackUUID] != nil {
            audioLevels[logicTrackUUID]?.peakRmsValue = audioLevels[logicTrackUUID]?.rmsValue ?? 0.0
            logger.info("Peak value reset for track: \(logicTrackUUID, privacy: .public)")
            
            // If this is the master bus, also update the compatibility channels
            if logicTrackUUID == masterBusUUID {
                leftChannel.peakValue = leftChannel.value
                rightChannel.peakValue = rightChannel.value
            }
        }
    }

    /// Resets peak values for all known tracks.
    public func resetAllPeaks() {
        for uuid in audioLevels.keys {
            resetPeak(for: uuid)
        }
        logger.info("All peak values reset.")
    }

    /// Starts a timer to handle peak value decay.
    private func startPeakDecayTimer() {
        peakDecayTimer?.invalidate() // Invalidate existing timer if any
        peakDecayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            
            Task { @MainActor in
                let now = Date()
                for uuid in strongSelf.audioLevels.keys {
                    if var level = strongSelf.audioLevels[uuid] {
                        // Only decay if not recently updated
                        if now.timeIntervalSince(level.lastUpdateTime) > 0.1 { // e.g., if no update in last 100ms
                            level.peakRmsValue *= strongSelf.peakDecayRate
                            if level.peakRmsValue < 0.001 { // Prevent denormals or tiny values
                                level.peakRmsValue = 0.0
                            }
                            strongSelf.audioLevels[uuid] = level
                            
                            // If this is the master bus, also update compatibility channels
                            if uuid == strongSelf.masterBusUUID {
                                strongSelf.leftChannel.peakValue *= strongSelf.peakDecayRate
                                strongSelf.rightChannel.peakValue *= strongSelf.peakDecayRate
                                if strongSelf.leftChannel.peakValue < 0.001 {
                                    strongSelf.leftChannel.peakValue = 0.0
                                }
                                if strongSelf.rightChannel.peakValue < 0.001 {
                                    strongSelf.rightChannel.peakValue = 0.0
                                }
                            }
                        }
                    }
                }
            }
        }
        logger.info("Peak decay timer started.")
    }
    
    /// Cleans up resources when the service is deallocated.
    deinit {
        peakDecayTimer?.invalidate()
        logger.info("LevelMeterService deallocated and peak decay timer stopped.")
    }
}
