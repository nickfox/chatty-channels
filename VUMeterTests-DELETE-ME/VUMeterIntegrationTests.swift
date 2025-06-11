// VUMeterIntegrationTests.swift
// Integration tests for the VU meter with the OSC service

import XCTest
import Combine
@testable import ChattyChannels

@MainActor
final class VUMeterIntegrationTests: XCTestCase {
    
    var levelService: LevelMeterService!
    var oscService: OSCService!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() async throws {
        try await super.setUp()
        levelService = LevelMeterService()
        oscService = OSCService(levelMeterService: levelService)
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        levelService = nil
        oscService = nil
        try await super.tearDown()
    }
    
    // Test that the LevelMeterService properly responds to OSC data
    func testOSCIntegration() async throws {
        // Test that OSC service can update levels through processIdentifiedRMS
        let testUUID = "TEST_TRACK_UUID"
        let testRMS: Float = 0.75
        
        // Process an identified RMS message
        oscService.processIdentifiedRMS(logicTrackUUID: testUUID, rmsValue: testRMS)
        
        // Give it a moment to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Check that the level was updated
        XCTAssertNotNil(levelService.audioLevels[testUUID])
        if let level = levelService.audioLevels[testUUID] {
            XCTAssertEqual(level.rmsValue, testRMS, accuracy: 0.001)
        }
    }
    
    // Test that level changes are properly reflected in published properties
    func testLevelChangePublishing() async {
        // Create an expectation
        let expectation = XCTestExpectation(description: "Level changes should be published")
        
        // Subscribe to master bus level changes
        var received = false
        levelService.$audioLevels
            .dropFirst() // Skip the initial value
            .sink { _ in
                received = true
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Update a level
        levelService.updateLevel(logicTrackUUID: "MASTER_BUS_UUID", rmsValue: 0.5)
        
        // Wait for the expectation
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Verify we received an update
        XCTAssertTrue(received, "Should have received a published update")
    }
    
    // Test VU ballistics integration with level changes
    func testVUBallistics() async throws {
        // Test that rapid level changes are smoothed by the UI ballistics
        let masterUUID = "MASTER_BUS_UUID"
        
        // Send rapid level changes
        for i in 0..<10 {
            let level = Float(i) / 10.0
            levelService.updateLevel(logicTrackUUID: masterUUID, rmsValue: level)
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }
        
        // The actual ballistics smoothing happens in the UI components
        // Here we just verify the service is receiving and storing the values
        XCTAssertNotNil(levelService.audioLevels[masterUUID])
    }
    
    // Test peak handling with simulated peak values
    func testPeakHandling() async throws {
        let testUUID = "PEAK_TEST_UUID"
        
        // Set a high peak value
        levelService.updateLevel(logicTrackUUID: testUUID, rmsValue: 0.5, peakRmsValueOverride: 1.0)
        
        // Check initial peak state
        if let level = levelService.audioLevels[testUUID] {
            XCTAssertEqual(level.peakRmsValue, 1.0, accuracy: 0.001)
            XCTAssertGreaterThan(level.peakRmsValue, level.rmsValue)
        }
        
        // Wait for peak decay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Peak should have decayed
        if let level = levelService.audioLevels[testUUID] {
            XCTAssertLessThan(level.peakRmsValue, 1.0, "Peak value should have decayed")
        }
    }
    
    // Test track name integration
    func testTrackNameIntegration() async {
        // Set a track name
        levelService.setCurrentTrack("Test Track")
        
        // Check that it's reflected in the service
        XCTAssertEqual(levelService.currentTrack, "Test Track", "Track name should be updated")
        
        // Check that compatibility channels are updated
        XCTAssertEqual(levelService.leftChannel.trackName, "Test Track")
        XCTAssertEqual(levelService.rightChannel.trackName, "Test Track")
    }
    
    // Test OSC unidentified RMS caching
    func testUnidentifiedRMSCaching() async {
        let tempID = "temp-plugin-123"
        let rmsValue: Float = 0.8
        
        // Process unidentified RMS
        oscService.processUnidentifiedRMS(
            tempID: tempID,
            rmsValue: rmsValue,
            senderIP: "127.0.0.1",
            senderPort: 9000
        )
        
        // Check cache
        let cachedData = oscService.getUnidentifiedRMSData()
        XCTAssertNotNil(cachedData[tempID])
        XCTAssertEqual((cachedData[tempID]?.rms) ?? 0.0, rmsValue, accuracy: 0.001)
    }
}
