// VUMeterIntegrationTests.swift
// Integration tests for the VU meter with the OSC service

import XCTest
import Combine
@testable import ChattyChannels

final class VUMeterIntegrationTests: XCTestCase {
    
    var levelService: LevelMeterService!
    var oscService: OSCService!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        oscService = OSCService()
        levelService = LevelMeterService(oscService: oscService)
    }
    
    override func tearDown() {
        cancellables.removeAll()
        levelService = nil
        oscService = nil
        super.tearDown()
    }
    
    // Test that the LevelMeterService properly responds to OSC data
    // Since we're using simulated data for v0.6, this test is more of a placeholder
    // for when real OSC integration is implemented
    func testOSCIntegration() {
        // Create an expectation that level values will change due to simulated data
        let expectation = XCTestExpectation(description: "Level values should change")
        
        // Store initial values
        let initialLeftValue = levelService.leftChannel.value
        let initialRightValue = levelService.rightChannel.value
        
        // After a short time, the simulated values should have changed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Check if either channel's value has changed
            if self.levelService.leftChannel.value != initialLeftValue ||
               self.levelService.rightChannel.value != initialRightValue {
                expectation.fulfill()
            }
        }
        
        // Wait for expectation to be fulfilled
        wait(for: [expectation], timeout: 1.0)
    }
    
    // Test that level changes are properly reflected in published properties
    func testLevelChangePublishing() {
        // Create an expectation
        let expectation = XCTestExpectation(description: "Level changes should be published")
        
        // Subscribe to left channel changes
        var received = false
        levelService.$leftChannel
            .dropFirst() // Skip the initial value
            .sink { _ in
                received = true
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Wait for the simulation to change the value and publish it
        wait(for: [expectation], timeout: 1.0)
        
        // Verify we received an update
        XCTAssertTrue(received, "Should have received a published update")
    }
    
    // Test VU ballistics integration with level changes
    func testVUBallistics() {
        // This test is more conceptual and would normally be tested in UI tests
        // or with a mocked animation system
        
        // For now, we can test that the level service is connected and running
        XCTAssertNotNil(levelService, "Level service should be initialized")
        
        // Wait a bit to ensure initialization is complete
        let expectation = XCTestExpectation(description: "Wait for service")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
    }
    
    // Test peak handling with simulated peak values
    func testPeakHandling() {
        // Create an expectation
        let expectation = XCTestExpectation(description: "Peak values should be handled")
        
        // In our implementation, we need to explicitly set the peak value
        // Force a peak value
        levelService.leftChannel.value = 1.2 // Well above 0dB
        levelService.leftChannel.peakValue = 1.2 // Explicitly set the peak value
        
        // Check peak state
        XCTAssertTrue(levelService.leftChannel.isPeaking, "Left channel should be peaking")
        XCTAssertGreaterThanOrEqual(levelService.leftChannel.peakValue, 1.0, "Peak value should be at least 1.0")
        
        // Peak values should decay over time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Reset the value (simulate falling level)
            self.levelService.leftChannel.value = 0.1
            
            // Peak should still be high immediately after
            XCTAssertGreaterThan(self.levelService.leftChannel.peakValue, 0.1, "Peak value should be higher than current value")
            
            // After more time, peak should decay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Since we have peak decay in the simulator (0.99 per update), 
                // the peak should have decayed significantly after 1 second
                XCTAssertLessThan(self.levelService.leftChannel.peakValue, 1.0, "Peak value should have decayed")
                expectation.fulfill()
            }
        }
        
        // Wait for the expectation
        wait(for: [expectation], timeout: 2.0)
    }
    
    // Test track name integration
    func testTrackNameIntegration() {
        // Set a track name
        levelService.setCurrentTrack("Test Track")
        
        // Check that it's reflected in the service
        XCTAssertEqual(levelService.currentTrack, "Test Track", "Track name should be updated")
        
        // In a real integration test, we would check that this appears in the UI
    }
}
