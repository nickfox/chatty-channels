// SimulationService.swift
//
// Service for simulating real-time audio levels for testing

import Foundation
import Combine
import SwiftUI
import os.log

/// Service that simulates real-time audio level data for testing VU meters
/// This is useful for development and testing without actual Logic Pro audio
@MainActor
public class SimulationService: ObservableObject {
    /// The LevelMeterService to update with simulated data
    private let levelMeterService: LevelMeterService
    
    /// The OSCService to send OSC messages through (optional)
    private let oscService: OSCService?
    
    /// System logger
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "SimulationService")
    
    /// Timer for generating simulated data
    private var simulationTimer: Timer?
    
    /// Whether simulation is currently active
    @Published public var isSimulating: Bool = false
    
    /// Master bus track UUID - same as in LevelMeterService
    private let masterBusUUID = "MASTER_BUS_UUID"
    
    /// Initializes the simulation service
    /// - Parameters:
    ///   - levelMeterService: The service to update with simulated data
    ///   - oscService: Optional OSC service to send messages through
    public init(levelMeterService: LevelMeterService, oscService: OSCService? = nil) {
        self.levelMeterService = levelMeterService
        self.oscService = oscService
        self.logger.info("SimulationService initialized")
    }
    
    /// Starts generating simulated audio level data
    /// - Parameter direct: If true, updates LevelMeterService directly; if false, sends via OSC
    public func startSimulation(direct: Bool = true) {
        guard !isSimulating else { return }
        
        simulationTimer?.invalidate()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.generateSimulatedData(direct: direct)
            }
        }
        
        isSimulating = true
        logger.info("Started audio level simulation (mode: \(direct ? "direct" : "OSC"))")
    }
    
    /// Stops generating simulated data
    public func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        isSimulating = false
        logger.info("Stopped audio level simulation")
    }
    
    /// Generates a single frame of simulated audio data
    private func generateSimulatedData(direct: Bool) {
        // Create a slow-moving baseline with some randomness
        let time = Date().timeIntervalSince1970
        let baselineLevel = (sin(time * 0.5) * 0.3) + 0.5
        
        // Add some random fluctuation
        let fluctuation = Double.random(in: -0.1...0.1)
        
        // Ensure values stay in valid range
        let newValue = Float(max(0.0, min(1.0, baselineLevel + fluctuation)))
        
        // Occasional peaks
        let finalValue = Int(time * 10) % 50 == 0 ? Float.random(in: 0.8...1.0) : newValue
        
        if direct {
            // Update LevelMeterService directly
            levelMeterService.updateLevel(logicTrackUUID: masterBusUUID, rmsValue: finalValue)
        } else if let oscService = oscService {
            // Send via OSC for more realistic testing
            oscService.processIdentifiedRMS(logicTrackUUID: masterBusUUID, rmsValue: finalValue)
        }
    }
    
    /// Clean up when deallocated
    deinit {
        simulationTimer?.invalidate()
        logger.info("SimulationService deallocated")
    }
}
