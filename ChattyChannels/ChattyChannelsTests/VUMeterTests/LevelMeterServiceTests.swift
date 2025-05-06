// LevelMeterServiceTests.swift
// Tests for the LevelMeterService

import XCTest
import Combine
@testable import ChattyChannels

final class LevelMeterServiceTests: XCTestCase {
    
    var service: LevelMeterService!
    var oscService: OSCService!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        oscService = OSCService()
        service = LevelMeterService(oscService: oscService)
    }
    
    override func tearDown() {
        service = nil
        oscService = nil
        cancellables.removeAll()
        super.tearDown()
    }
    
    // Test initialization
    func testInitialization() {
        XCTAssertEqual(service.leftChannel.channel, AudioLevel.AudioChannel.left, "Left channel should be initialized correctly")
        XCTAssertEqual(service.rightChannel.channel, AudioLevel.AudioChannel.right, "Right channel should be initialized correctly")
        XCTAssertEqual(service.currentTrack, "No Track Selected", "Default track name should be 'No Track Selected'")
    }
    
    // Test setting current track
    func testSetCurrentTrack() {
        service.setCurrentTrack("Snare Drum")
        XCTAssertEqual(service.currentTrack, "Snare Drum", "Track name should be updated correctly")
    }
    
    // Test peak reset
    func testResetPeaks() {
        // Set some peak values
        service.leftChannel.peakValue = 0.8
        service.rightChannel.peakValue = 0.9
        
        // Reset them
        service.resetPeaks()
        
        // Check they're reset
        XCTAssertEqual(service.leftChannel.peakValue, 0.0, "Left channel peak should be reset to 0.0")
        XCTAssertEqual(service.rightChannel.peakValue, 0.0, "Right channel peak should be reset to 0.0")
    }
    
    // Test simulated audio levels (observe that they change over time)
    func testSimulatedLevels() {
        // Create an expectation
        let expectation = XCTestExpectation(description: "Audio levels should change over time")
        
        // Capture initial values
        let initialLeftValue = service.leftChannel.value
        let initialRightValue = service.rightChannel.value
        
        // Wait for 0.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Values should have changed from their initial values
            let leftValueChanged = self.service.leftChannel.value != initialLeftValue
            let rightValueChanged = self.service.rightChannel.value != initialRightValue
            
            // If either changed, consider the test passed
            if leftValueChanged || rightValueChanged {
                expectation.fulfill()
            }
        }
        
        // Wait up to 1 second for the expectation to be fulfilled
        wait(for: [expectation], timeout: 1.0)
    }
    
    // Test that peak values are maintained and decayed appropriately
    func testPeakValueBehavior() {
        // Create an expectation
        let expectation = XCTestExpectation(description: "Peak values should be maintained and decay")
        
        // Set initial peak values
        service.leftChannel.peakValue = 1.0
        service.rightChannel.peakValue = 1.0
        
        // After some time, peak values should decay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Check that peak values have decayed (should be less than 1.0)
            XCTAssertLessThan(self.service.leftChannel.peakValue, 1.0, "Left peak should decay")
            XCTAssertLessThan(self.service.rightChannel.peakValue, 1.0, "Right peak should decay")
            
            expectation.fulfill()
        }
        
        // Wait up to 1 second for the expectation to be fulfilled
        wait(for: [expectation], timeout: 1.0)
    }
    
    // Test that the service publishes updates to its properties
    func testPublishedPropertyUpdates() {
        // Create expectations
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
        wait(for: [trackExpectation], timeout: 0.5)
    }
}
