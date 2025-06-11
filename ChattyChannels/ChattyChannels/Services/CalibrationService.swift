// ChattyChannels/ChattyChannels/Services/CalibrationService.swift
import Foundation
import Combine
import OSLog
import Darwin

@MainActor
class CalibrationService: ObservableObject {
    private let trackMappingService: TrackMappingService
    private let appleScriptService: AppleScriptServiceProtocol // Use protocol for testability
    private let oscService: OSCService
    private let accessibilityService = AccessibilityTrackDiscoveryService()
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "CalibrationService")

    @Published var calibrationState: CalibrationState = .idle
    @Published var calibrationProgress: Double = 0.0 // 0.0 to 1.0
    @Published var identifiedMappings: [String: String] = [:] // [tempInstanceID: logicTrackUUID]
    @Published var currentProbingTrackInfo: (name: String, uuid: String)? = nil
    @Published var lastCalibrationError: String? = nil

    enum CalibrationState: CustomStringConvertible, Equatable {
        case idle
        case fetchingTracks
        case probing(trackName: String, trackUUID: String)
        case processingProbe(trackName: String, trackUUID: String)
        case assigning(trackName: String, tempID: String, trackUUID: String)
        case completed(mappedCount: Int, totalTracks: Int)
        case failed(error: String)

        var description: String {
            switch self {
            case .idle: return "Idle"
            case .fetchingTracks: return "Fetching tracks from Logic Pro..."
            case .probing(let trackName, _): return "Probing: \(trackName)..."
            case .processingProbe(let trackName, _): return "Processing probe for: \(trackName)..."
            case .assigning(let trackName, _, _): return "Assigning ID to plugin on: \(trackName)..."
            case .completed(let mappedCount, let totalTracks): return "Calibration Complete. Mapped \(mappedCount) of \(totalTracks) tracks."
            case .failed(let error): return "Calibration Failed: \(error)"
            }
        }
        
        var isWorking: Bool {
            switch self {
            case .idle, .completed, .failed:
                return false
            default:
                return true
            }
        }
    }

    init(trackMappingService: TrackMappingService, 
         appleScriptService: AppleScriptServiceProtocol, 
         oscService: OSCService) {
        self.trackMappingService = trackMappingService
        self.appleScriptService = appleScriptService
        self.oscService = oscService
    }

    /// Test input gain movement detection - validates core concept
    func testInputGainMovement() async {
        guard !calibrationState.isWorking else {
            logger.warning("Cannot run input gain test while calibration is in progress")
            return
        }
        
        logger.info("Starting input gain movement test...")
        calibrationState = .idle // Ensure we're in a clean state
        
        do {
            try await appleScriptService.testInputGainMovementChannel1(oscService: oscService)
            logger.info("Input gain movement test completed successfully")
        } catch {
            logger.error("Input gain movement test failed: \(error.localizedDescription)")
        }
    }

    /// Starts oscillator-based calibration by generating a single test tone and identifying plugins through systematic unmuting
    func startOscillatorBasedCalibration() async {
        guard !calibrationState.isWorking else {
            logger.warning("Calibration already in progress. Ignoring request.")
            return
        }
        
        logger.info("Starting oscillator-based calibration")
        
        calibrationState = .fetchingTracks
        identifiedMappings = [:]
        calibrationProgress = 0.0
        currentProbingTrackInfo = nil
        lastCalibrationError = nil
        var successfullyMappedCount = 0

        do {
            // 1. Discover tracks using accessibility APIs - ALWAYS discover fresh for calibration
            logger.info("Discovering all tracks fresh for calibration (ignoring cache)")
            let accessibilityService = AccessibilityTrackDiscoveryService()
            let trackMappings = try accessibilityService.discoverTracks()
            
            guard !trackMappings.isEmpty else {
                let errorMsg = "No tracks found in Logic Pro for calibration."
                logger.error("\(errorMsg)")
                calibrationState = .failed(error: errorMsg)
                lastCalibrationError = errorMsg
                return
            }
            
            logger.info("Fresh discovery found \(trackMappings.count) tracks: \(trackMappings.keys.sorted())")
            
            // 2. Mute all tracks first
            logger.info("Muting all tracks...")
            for trackName in trackMappings.keys {
                try await muteTrack(byName: trackName)
            }
            
            // 3. Send single 137Hz tone to all plugins
            logger.info("Broadcasting 137Hz calibration tone to all plugins...")
            try await oscService.startToneGeneration(frequency: 137.0, amplitude: -10.0)
            
            // Wait for tone to stabilize and plugins to start generating
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            logger.info("Calibration tone stabilized")
            
            // 4. Systematically unmute tracks one by one and identify plugins
            let mappings = try await identifyPluginsByUnmuting(trackMappings)
            
            // 5. Stop all tones
            try await stopAllTones()
            
            // 6. Send assignments to identified plugins
            successfullyMappedCount = try await updateTrackMappings(mappings)
            
            logger.info("Oscillator calibration completed successfully. Mapped \(successfullyMappedCount) of \(trackMappings.count) tracks.")
            calibrationState = .completed(mappedCount: successfullyMappedCount, totalTracks: trackMappings.count)
            
        } catch {
            logger.error("Oscillator calibration process failed: \(error.localizedDescription, privacy: .public)")
            calibrationState = .failed(error: error.localizedDescription)
            lastCalibrationError = error.localizedDescription
            currentProbingTrackInfo = nil
            
            // Ensure tones are stopped on failure
            try? await stopAllTones()
        }
    }

    
    /// Identifies plugins by systematically unmuting tracks one by one and checking RMS
    private func identifyPluginsByUnmuting(_ trackMappings: [String: String]) async throws -> [String: String] {
        var identifiedMappings: [String: String] = [:] // [pluginID: simpleID]
        var assignedPlugins = Set<String>() // Track already assigned plugins
        
        // Process each track in order
        let sortedTracks = trackMappings.sorted { $0.value < $1.value } // Sort by simpleID (TR1, TR2, etc.)
        
        for (trackName, simpleID) in sortedTracks {
            currentProbingTrackInfo = (name: trackName, uuid: simpleID)
            calibrationState = .probing(trackName: trackName, trackUUID: simpleID)
            logger.info("Testing track: \(trackName) (\(simpleID))")
            
            // Unmute only this track
            try await unmuteTrack(byName: trackName)
            
            // Wait for audio to settle
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Query all plugins for RMS
            let activeRMS = try await getAllPluginRMSData()
            
            // Find the plugin with RMS > threshold (that hasn't been assigned yet)
            if let activePluginID = findActivePlugin(rmsData: activeRMS, excludingPlugins: assignedPlugins) {
                identifiedMappings[activePluginID] = simpleID
                assignedPlugins.insert(activePluginID)
                logger.info("Identified mapping: Plugin \(activePluginID) -> Track \(trackName) (\(simpleID))")
            } else {
                logger.warning("No active plugin found for track \(trackName)")
            }
            
            // Mute the track again before testing the next one
            try await muteTrack(byName: trackName)
            
            // Brief pause between tracks
            try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
            
            // Update progress
            calibrationProgress = Double(identifiedMappings.count) / Double(trackMappings.count)
        }
        
        return identifiedMappings
    }
    
    /// Finds the plugin with active RMS (above threshold)
    private func findActivePlugin(rmsData: [String: Float], excludingPlugins: Set<String>) -> String? {
        let activeThreshold: Float = -60.0 // dBFS threshold for "active"
        
        // Log all RMS values for debugging
        logger.info("Current RMS values:")
        for (pluginID, rms) in rmsData {
            let db = rms > 0 ? 20 * log10(rms) : -120.0
            logger.info("  Plugin \(pluginID): \(String(format: "%.6f", rms)) (\(String(format: "%.1f", db))dB)")
        }
        
        var bestCandidate: (pluginID: String, rms: Float, db: Float)? = nil
        
        for (pluginID, rms) in rmsData {
            // Skip already assigned plugins
            if excludingPlugins.contains(pluginID) {
                logger.debug("Skipping already assigned plugin: \(pluginID)")
                continue
            }
            
            let db = rms > 0 ? 20 * log10(rms) : -120.0
            
            // Check if this plugin is above the threshold
            if db > activeThreshold {
                // Track the plugin with the highest RMS
                if bestCandidate == nil || rms > bestCandidate!.rms {
                    bestCandidate = (pluginID: pluginID, rms: rms, db: db)
                }
            }
        }
        
        if let candidate = bestCandidate {
            logger.info("Found active plugin \(candidate.pluginID) with RMS \(String(format: "%.6f", candidate.rms)) (\(String(format: "%.1f", candidate.db))dB)")
            return candidate.pluginID
        }
        
        return nil
    }
    
    /// Gets current RMS data from all plugins
    private func getAllPluginRMSData() async throws -> [String: Float] {
        let queryID = UUID().uuidString
        oscService.broadcastRMSQuery(queryID: queryID)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for responses
        let responses = oscService.getCurrentQueryResponses()
        oscService.clearCurrentQuery()
        return responses
    }
    
    /// Stops all tone generation
    private func stopAllTones() async throws {
        logger.info("Stopping all tone generation...")
        try await oscService.stopAllTones()
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for tones to stop
        logger.info("All tones stopped")
    }
    
    /// Updates track mappings and sends assignments to plugins
    private func updateTrackMappings(_ mappings: [String: String]) async throws -> Int {
        var successCount = 0
        
        for (pluginID, simpleID) in mappings {
            // Get the port assigned to this plugin
            if let pluginPort = oscService.getPluginPort(pluginID) {
                // Send UUID assignment to the specific plugin's port
                oscService.sendUUIDAssignment(
                    toPluginIP: "127.0.0.1",
                    port: Int(pluginPort),
                    tempInstanceID: pluginID,
                    logicTrackUUID: simpleID
                )
                
                // Store in our identified mappings
                identifiedMappings[pluginID] = simpleID
                
                // Clear from unidentified cache
                oscService.clearSpecificUnidentifiedRMS(tempID: pluginID)
                
                successCount += 1
                logger.info("Assigned plugin \(pluginID) to track ID \(simpleID) on port \(pluginPort)")
            } else {
                logger.warning("Could not find port for plugin \(pluginID) - skipping assignment")
            }
        }
        
        return successCount
    }
    
    /// Mutes a track by name using accessibility APIs
    private func muteTrack(byName trackName: String) async throws {
        logger.debug("Muting track: \(trackName)")
        
        // Use accessibility APIs to mute the track
        try accessibilityService.muteTrack(byName: trackName)
        
        logger.info("Successfully requested mute for track: \(trackName)")
    }
    
    /// Unmutes a track by name using accessibility APIs
    private func unmuteTrack(byName trackName: String) async throws {
        logger.debug("Unmuting track: \(trackName)")
        
        // Use accessibility APIs to unmute the track
        try accessibilityService.unmuteTrack(byName: trackName)
        
        logger.info("Successfully requested unmute for track: \(trackName)")
    }
}
