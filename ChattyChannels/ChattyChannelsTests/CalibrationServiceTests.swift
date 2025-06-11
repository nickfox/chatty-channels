// CalibrationServiceTests.swift
// Tests for the calibration service's active probing identification

import XCTest
import Combine
@testable import ChattyChannels

/// Tests for the CalibrationService active probing identification system
@MainActor
final class CalibrationServiceTests: XCTestCase {
    
    private var calibrationService: CalibrationService!
    private var trackMappingService: TrackMappingService!
    private var mockAppleScriptService: MockAppleScriptService!
    private var oscService: OSCService!
    private var levelMeterService: LevelMeterService!
    private var cancellables = Set<AnyCancellable>()
    
    override func setUp() async throws {
        try await super.setUp()
        
        levelMeterService = LevelMeterService()
        oscService = OSCService(levelMeterService: levelMeterService)
        
        // Create a mock TrackMappingService instead of using the real one
        trackMappingService = MockTrackMappingService()
        mockAppleScriptService = MockAppleScriptService()
        
        calibrationService = CalibrationService(
            trackMappingService: trackMappingService,
            appleScriptService: mockAppleScriptService,
            oscService: oscService
        )
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        calibrationService = nil
        trackMappingService = nil
        mockAppleScriptService = nil
        oscService = nil
        levelMeterService = nil
        
        try await super.tearDown()
    }
    
    // MARK: - State Transition Tests
    
    func testCalibrationStateTransitions() async throws {
        // Set up mock tracks in the track mapping service
        (trackMappingService as! MockTrackMappingService).mockTracks = [
            "Kick": "KICK-UUID",
            "Snare": "SNARE-UUID"
        ]
        
        // Monitor state changes
        var stateHistory: [CalibrationService.CalibrationState] = []
        
        calibrationService.$calibrationState
            .sink { state in
                stateHistory.append(state)
            }
            .store(in: &cancellables)
        
        // Start calibration
        let calibrationTask = Task {
            await calibrationService.startCalibration(
                probeFrequency: 440.0,
                probeLevel: -12.0,
                probeDuration: 0.1
            )
        }
        
        // Let it run briefly
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Cancel to stop the calibration
        calibrationTask.cancel()
        
        // Verify state transitions
        XCTAssertTrue(stateHistory.contains { 
            if case .idle = $0 { return true }
            return false
        }, "Should start in idle state")
        
        XCTAssertTrue(stateHistory.contains { 
            if case .fetchingTracks = $0 { return true }
            return false
        }, "Should transition to fetching tracks")
        
        XCTAssertTrue(stateHistory.contains { 
            if case .probing = $0 { return true }
            return false
        }, "Should transition to probing")
    }
    
    // MARK: - Probing Tests
    
    func testSuccessfulProbing() async throws {
        // Set up mock tracks in the track mapping service
        (trackMappingService as! MockTrackMappingService).mockTracks = [
            "Kick": "KICK-UUID"
        ]
        
        // Simulate unidentified RMS data appearing during probe
        mockAppleScriptService.onProbeTrack = { uuid, _, _, _ in
            // Simulate plugin sending unidentified RMS during probe
            self.oscService.processUnidentifiedRMS(
                tempID: "plugin-1",
                rmsValue: -10.0, // Strong signal
                senderIP: "127.0.0.1",
                senderPort: 9000
            )
        }
        
        // Start calibration
        await calibrationService.startCalibration(
            probeFrequency: 440.0,
            probeLevel: -12.0,
            probeDuration: 0.1
        )
        
        // Verify mapping was created
        XCTAssertEqual(calibrationService.identifiedMappings.count, 1)
        XCTAssertEqual(calibrationService.identifiedMappings["plugin-1"], "KICK-UUID")
        
        // Verify final state
        if case let .completed(mappedCount, totalTracks) = calibrationService.calibrationState {
            XCTAssertEqual(mappedCount, 1)
            XCTAssertEqual(totalTracks, 1)
        } else {
            XCTFail("Should be in completed state")
        }
    }
    
    func testProbingWithNoResponse() async throws {
        // Set up mock tracks in the track mapping service
        (trackMappingService as! MockTrackMappingService).mockTracks = [
            "Silent Track": "SILENT-UUID"
        ]
        
        // Don't simulate any RMS data - track has no plugin
        
        // Start calibration
        await calibrationService.startCalibration(
            probeFrequency: 440.0,
            probeLevel: -12.0,
            probeDuration: 0.1
        )
        
        // Verify no mapping was created
        XCTAssertEqual(calibrationService.identifiedMappings.count, 0)
        
        // Verify completed with 0 mapped
        if case let .completed(mappedCount, totalTracks) = calibrationService.calibrationState {
            XCTAssertEqual(mappedCount, 0)
            XCTAssertEqual(totalTracks, 1)
        } else {
            XCTFail("Should be in completed state")
        }
    }
    
    func testProbingWithMultipleTracks() async throws {
        // Set up multiple tracks in the track mapping service
        (trackMappingService as! MockTrackMappingService).mockTracks = [
            "Kick": "KICK-UUID",
            "Snare": "SNARE-UUID",
            "Hi-Hat": "HIHAT-UUID"
        ]
        
        mockAppleScriptService.onProbeTrack = { uuid, _, _, _ in
            
            // Simulate different plugins responding to different tracks
            switch uuid {
            case "KICK-UUID":
                self.oscService.processUnidentifiedRMS(
                    tempID: "plugin-kick",
                    rmsValue: -8.0,
                    senderIP: "127.0.0.1",
                    senderPort: 9001
                )
            case "SNARE-UUID":
                self.oscService.processUnidentifiedRMS(
                    tempID: "plugin-snare",
                    rmsValue: -6.0,
                    senderIP: "127.0.0.1",
                    senderPort: 9002
                )
            case "HIHAT-UUID":
                // Hi-hat has no plugin
                break
            default:
                break
            }
        }
        
        // Start calibration
        await calibrationService.startCalibration(
            probeFrequency: 440.0,
            probeLevel: -12.0,
            probeDuration: 0.1
        )
        
        // Verify mappings
        XCTAssertEqual(calibrationService.identifiedMappings.count, 2)
        XCTAssertEqual(calibrationService.identifiedMappings["plugin-kick"], "KICK-UUID")
        XCTAssertEqual(calibrationService.identifiedMappings["plugin-snare"], "SNARE-UUID")
        
        // Verify final state
        if case let .completed(mappedCount, totalTracks) = calibrationService.calibrationState {
            XCTAssertEqual(mappedCount, 2)
            XCTAssertEqual(totalTracks, 3)
        } else {
            XCTFail("Should be in completed state")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testCalibrationWithAppleScriptError() async throws {
        // Set up to fail during track fetching
        (trackMappingService as! MockTrackMappingService).shouldFail = true
        (trackMappingService as! MockTrackMappingService).errorToThrow = AppleScriptError.executionFailed("Mock error")
        
        // Start calibration
        await calibrationService.startCalibration()
        
        // Verify error state
        if case let .failed(error) = calibrationService.calibrationState {
            XCTAssertTrue(error.contains("Mock error"))
        } else {
            XCTFail("Should be in failed state")
        }
        
        XCTAssertNotNil(calibrationService.lastCalibrationError)
    }
    
    func testCalibrationWithProbeError() async throws {
        // Set up mock tracks in the track mapping service
        (trackMappingService as! MockTrackMappingService).mockTracks = [
            "Kick": "KICK-UUID"
        ]
        
        // Fail on probe
        mockAppleScriptService.shouldFailOnProbe = true
        mockAppleScriptService.errorToThrow = AppleScriptError.executionFailed("Probe failed")
        
        // Start calibration
        await calibrationService.startCalibration()
        
        // Verify error state
        if case let .failed(error) = calibrationService.calibrationState {
            XCTAssertTrue(error.contains("Probe failed"))
        } else {
            XCTFail("Should be in failed state")
        }
    }
    
    // MARK: - Progress Tracking Tests
    
    func testCalibrationProgress() async throws {
        // Set up mock tracks in the track mapping service
        (trackMappingService as! MockTrackMappingService).mockTracks = [
            "Track1": "UUID1",
            "Track2": "UUID2",
            "Track3": "UUID3",
            "Track4": "UUID4"
        ]
        
        var progressValues: [Double] = []
        
        calibrationService.$calibrationProgress
            .dropFirst() // Skip initial 0.0
            .sink { progress in
                progressValues.append(progress)
            }
            .store(in: &cancellables)
        
        // Start calibration
        await calibrationService.startCalibration(probeDuration: 0.05)
        
        // Verify progress increments
        XCTAssertFalse(progressValues.isEmpty)
        XCTAssertEqual(progressValues.last ?? 0.0, 1.0, accuracy: 0.01)
        
        // Verify progress was incremental
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(progressValues[i], progressValues[i-1])
        }
    }
}

// MARK: - Mock AppleScript Service

class MockAppleScriptService: AppleScriptServiceProtocol {
    var shouldFailOnProbe = false
    var errorToThrow: Error?
    var onProbeTrack: ((String, Double, Float, Double) throws -> Void)?
    
    func probeTrack(logicTrackUUID: String, frequency: Double, probeLevel: Float, duration: Double) async throws {
        if shouldFailOnProbe {
            throw errorToThrow ?? AppleScriptError.executionFailed("Probe error")
        }
        
        // Call the callback if provided
        try onProbeTrack?(logicTrackUUID, frequency, probeLevel, duration)
        
        // Simulate probe duration
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
    
    func setVolume(trackName: String, db: Float) throws {
        // Not used in calibration tests
    }
    
    func getVolume(trackName: String) throws -> Float {
        // Not used in calibration tests
        return 0.0
    }
}

// MARK: - Mock Track Mapping Service

class MockTrackMappingService: TrackMappingService {
    var mockTracks: [String: String] = [:] // [TrackName: LogicTrackUUID]
    var shouldFail = false
    var errorToThrow: Error?
    
    override func loadMapping() throws -> [String: String] {
        if shouldFail {
            throw errorToThrow ?? AppleScriptError.executionFailed("Mock error")
        }
        return mockTracks
    }
}
