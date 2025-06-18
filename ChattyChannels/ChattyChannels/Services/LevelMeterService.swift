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
    
    /// Dedicated published property for TR1 (kick drum) to ensure VU meter updates
    @Published public var tr1Level = AudioLevel(id: "TR1", rmsValue: 0.0, peakRmsValue: 0.0, trackName: "Kick")
    
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
        audioLevels["TR1"] = tr1Level // Initialize TR1 in the dictionary
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
        var level = audioLevels[logicTrackUUID] ?? AudioLevel(id: logicTrackUUID, rmsValue: 0.0, peakRmsValue: 0.0, trackName: logicTrackUUID)
        
        level.rmsValue = max(0.0, min(1.0, rmsValue)) // Clamp value
        
        if let peakOverride = peakRmsValueOverride {
            level.peakRmsValue = max(level.peakRmsValue, max(0.0, min(1.0, peakOverride)))
        } else {
            level.peakRmsValue = max(level.peakRmsValue, level.rmsValue)
        }
        level.lastUpdateTime = Date()
        
        audioLevels[logicTrackUUID] = level
        
        // CRITICAL FIX: Update the dedicated TR1 property when TR1 data arrives
        if logicTrackUUID == "TR1" {
            tr1Level = level
            // Commented out to reduce console spam at 24 Hz
            // logger.info("Updated TR1 dedicated property: RMS \(level.rmsValue, privacy: .public), Peak \(level.peakRmsValue, privacy: .public)")
        }
        
        // Force SwiftUI to detect the change by replacing the entire dictionary
        let newDict = audioLevels
        audioLevels = newDict
        
        // Force objectWillChange to fire to ensure SwiftUI updates
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        // If this is the master bus, update the current track name for UI compatibility
        if logicTrackUUID == masterBusUUID {
            if let trackName = level.trackName {
                currentTrack = trackName
            }
            
            // Update v0.6 compatibility properties immediately for the master bus
            updateCompatibilityChannels(from: level)
        }
        
        // Commented out verbose logging to reduce console spam at 24 Hz
        // logger.info("Updated level for \(logicTrackUUID, privacy: .public): RMS \(level.rmsValue, privacy: .public), Peak \(level.peakRmsValue, privacy: .public)")
        
    }
    
    /// Updates the band energies for a specific track (FFT data).
    /// This method stores the band energy data without updating the UI.
    /// - Parameters:
    ///   - logicTrackUUID: The unique identifier of the track.
    ///   - bandEnergies: Array of 4 band energy values in dB.
    public func updateBandEnergies(logicTrackUUID: String, bandEnergies: [Float]) {
        guard bandEnergies.count == 4 else {
            logger.error("Invalid band energies array: expected 4 values, got \(bandEnergies.count)")
            return
        }
        
        // Get or create the audio level for this track
        var level = audioLevels[logicTrackUUID] ?? AudioLevel(id: logicTrackUUID, rmsValue: 0.0, peakRmsValue: 0.0, trackName: logicTrackUUID)
        
        // Update band energies
        level.bandEnergies = bandEnergies
        
        // Store back in dictionary
        audioLevels[logicTrackUUID] = level
        
        // Update TR1 dedicated property if needed
        if logicTrackUUID == "TR1" {
            tr1Level.bandEnergies = bandEnergies
        }
        
        // Commented out to reduce console spam at 24 Hz
        // logger.info("Band energies for \(logicTrackUUID): Low=\(bandEnergies[0])dB, Low-Mid=\(bandEnergies[1])dB, High-Mid=\(bandEnergies[2])dB, High=\(bandEnergies[3])dB")
        
        // Note: We're not triggering objectWillChange here because we don't want
        // to update the UI yet. Band energies are stored for future use in v0.9+
    }
    
    /// Updates the v0.6 compatibility channel properties from the master bus data
    private func updateCompatibilityChannels(from masterLevel: AudioLevel) {
        leftChannel = AudioLevel(id: "LEFT", rmsValue: masterLevel.rmsValue, peakRmsValue: masterLevel.peakRmsValue, trackName: masterLevel.trackName)
        rightChannel = AudioLevel(id: "RIGHT", rmsValue: masterLevel.rmsValue, peakRmsValue: masterLevel.peakRmsValue, trackName: masterLevel.trackName)
    }
    
    /// Updates the master bus level with the sum of all track levels
    private func updateMasterBusLevel() {
        // Calculate RMS sum of all tracks (excluding master bus itself)
        var sumOfSquares: Float = 0.0
        var peakValue: Float = 0.0
        var trackCount = 0
        
        for (uuid, level) in audioLevels {
            if uuid != masterBusUUID {
                // RMS values are summed as power (squared values)
                sumOfSquares += level.rmsValue * level.rmsValue
                peakValue = max(peakValue, level.peakRmsValue)
                trackCount += 1
            }
        }
        
        // Calculate combined RMS (square root of sum of squares)
        let combinedRMS = trackCount > 0 ? sqrt(sumOfSquares) : 0.0
        
        // Apply 10x amplification and clamp to valid range
        let amplifiedRMS = min(1.0, combinedRMS * 10.0)
        let amplifiedPeak = min(1.0, peakValue * 10.0)
        
        // Update master bus level
        var masterLevel = audioLevels[masterBusUUID] ?? AudioLevel(id: masterBusUUID, rmsValue: 0.0, peakRmsValue: 0.0, trackName: "Master Bus")
        masterLevel.rmsValue = amplifiedRMS
        masterLevel.peakRmsValue = max(masterLevel.peakRmsValue, amplifiedPeak)
        masterLevel.lastUpdateTime = Date()
        
        audioLevels[masterBusUUID] = masterLevel
        
        // Update compatibility channels
        updateCompatibilityChannels(from: masterLevel)
    }
    
    /// Starts a timer to update the v0.6 compatibility properties from the master bus data
    private func startCompatibilityTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0/24.0, repeats: true) { [weak self] _ in
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
            
            // If this is TR1, also update the dedicated property
            if logicTrackUUID == "TR1", let level = audioLevels[logicTrackUUID] {
                tr1Level = level
            }
            
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
        peakDecayTimer = Timer.scheduledTimer(withTimeInterval: 1.0/24.0, repeats: true) { [weak self] _ in
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
                            
                            // Update TR1 dedicated property if needed
                            if uuid == "TR1" {
                                strongSelf.tr1Level = level
                            }
                            
                            // Update master bus level after individual track decay
                            if uuid != strongSelf.masterBusUUID {
                                strongSelf.updateMasterBusLevel()
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
