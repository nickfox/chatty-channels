// LevelMeterServiceTests.swift
// Tests for the LevelMeterService

import XCTest
import Combine
@testable import ChattyChannels

@MainActor
final class LevelMeterServiceTests: XCTestCase {
    
    var service: LevelMeterService!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() async throws {
        try await super.setUp()
        service = LevelMeterService()
    }
    
    override func tearDown() async throws {
        service = nil
        cancellables.removeAll()
        try await super.tearDown()
    }
    
    // Test initialization
    func testInitialization() async {
        XCTAssertEqual(service.leftChannel.id, "LEFT", "Left channel should be initialized correctly")
        XCTAssertEqual(service.rightChannel.id, "RIGHT", "Right channel should be initialized correctly")
        XCTAssertEqual(service.currentTrack, "Master Bus", "Default track name should be 'Master Bus'")
        
        // Check master bus is in audioLevels
        XCTAssertNotNil(service.audioLevels["MASTER_BUS_UUID"], "Master bus should be initialized")
    }
    
    // Test setting current track
    func testSetCurrentTrack() async {
        service.setCurrentTrack("Snare Drum")
        XCTAssertEqual(service.currentTrack, "Snare Drum", "Track name should be updated correctly")
        
        // Check compatibility channels are updated
        XCTAssertEqual(service.leftChannel.trackName, "Snare Drum", "Left channel track name should be updated")
        XCTAssertEqual(service.rightChannel.trackName, "Snare Drum", "Right channel track name should be updated")
    }
    
    // Test updating levels
    func testUpdateLevel() async {
        let testUUID = "TEST_TRACK_UUID"
        let testRMS: Float = 0.5
        let testPeak: Float = 0.8
        
        service.updateLevel(logicTrackUUID: testUUID, rmsValue: testRMS, peakRmsValueOverride: testPeak)
        
        // Check the level was stored
        XCTAssertNotNil(service.audioLevels[testUUID], "Track level should be stored")
        
        if let level = service.audioLevels[testUUID] {
            XCTAssertEqual(level.rmsValue, testRMS, accuracy: 0.001, "RMS value should match")
            XCTAssertEqual(level.peakRmsValue, testPeak, accuracy: 0.001, "Peak value should match")
        }
    }
    
    // Test master bus updates affect compatibility channels
    func testMasterBusUpdatesCompatibilityChannels() async {
        let masterUUID = "MASTER_BUS_UUID"
        let testRMS: Float = 0.6
        
        service.updateLevel(logicTrackUUID: masterUUID, rmsValue: testRMS)
        
        // Give a moment for the compatibility update
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(service.leftChannel.rmsValue, testRMS, accuracy: 0.001, "Left channel should match master RMS")
        XCTAssertEqual(service.rightChannel.rmsValue, testRMS, accuracy: 0.001, "Right channel should match master RMS")
    }
    
    // Test peak reset
    func testResetPeak() async {
        let testUUID = "TEST_TRACK_UUID"
        
        // Set up a level with peak higher than RMS
        service.updateLevel(logicTrackUUID: testUUID, rmsValue: 0.3, peakRmsValueOverride: 0.9)
        
        // Reset the peak
        service.resetPeak(for: testUUID)
        
        // Check peak was reset to RMS value
        if let level = service.audioLevels[testUUID] {
            XCTAssertEqual(level.peakRmsValue, level.rmsValue, accuracy: 0.001, "Peak should be reset to RMS value")
        }
    }
    
    // Test reset all peaks
    func testResetAllPeaks() async {
        // Set up multiple tracks with peaks
        let tracks = ["TRACK1", "TRACK2", "TRACK3"]
        
        for trackUUID in tracks {
            service.updateLevel(logicTrackUUID: trackUUID, rmsValue: 0.2, peakRmsValueOverride: 0.8)
        }
        
        // Reset all peaks
        service.resetAllPeaks()
        
        // Check all peaks were reset
        for trackUUID in tracks {
            if let level = service.audioLevels[trackUUID] {
                XCTAssertEqual(level.peakRmsValue, level.rmsValue, accuracy: 0.001, 
                               "Peak should be reset to RMS value for track \(trackUUID)")
            }
        }
    }
    
    // Test that peak values decay over time
    func testPeakValueDecay() async throws {
        let testUUID = "TEST_TRACK_UUID"
        
        // Set a high peak value
        service.updateLevel(logicTrackUUID: testUUID, rmsValue: 0.1, peakRmsValueOverride: 1.0)
        
        // Wait for decay to occur
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Check that peak has decayed
        if let level = service.audioLevels[testUUID] {
            XCTAssertLessThan(level.peakRmsValue, 1.0, "Peak value should decay over time")
            XCTAssertGreaterThan(level.peakRmsValue, 0.1, "Peak value should still be above RMS")
        }
    }
    
    // Test that the service publishes updates to its properties
    func testPublishedPropertyUpdates() async {
        // Create expectation
        let trackExpectation = XCTestExpectation(description: "Track name update should be published")
        
        // Subscribe to the track name publisher
        service.$currentTrack
            .dropFirst() // Skip the initial value
            .sink { name in
                XCTAssertEqual(name, "Test Track", "Published track name should be updated")
                trackExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger the update
        service.setCurrentTrack("Test Track")
        
        // Wait for the subscription to receive the update
        await fulfillment(of: [trackExpectation], timeout: 1.0)
    }
    
    // Test clamping of values
    func testValueClamping() async {
        let testUUID = "TEST_TRACK_UUID"
        
        // Test values outside valid range
        service.updateLevel(logicTrackUUID: testUUID, rmsValue: -0.5, peakRmsValueOverride: 1.5)
        
        if let level = service.audioLevels[testUUID] {
            XCTAssertEqual(level.rmsValue, 0.0, "Negative RMS should be clamped to 0.0")
            XCTAssertEqual(level.peakRmsValue, 1.0, "Peak above 1.0 should be clamped to 1.0")
        }
    }
}
