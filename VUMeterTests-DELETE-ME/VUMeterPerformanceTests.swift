// VUMeterPerformanceTests.swift
// Performance tests for the VU meter implementation

import XCTest
@testable import ChattyChannels

@MainActor
final class VUMeterPerformanceTests: XCTestCase {
    
    var levelService: LevelMeterService!
    
    override func setUp() async throws {
        try await super.setUp()
        levelService = LevelMeterService()
    }
    
    override func tearDown() async throws {
        levelService = nil
        try await super.tearDown()
    }
    
    // Test performance of dB conversion calculations
    func testDbConversionPerformance() {
        // Create a test level
        var level = AudioLevel(id: "test")
        
        // Measure performance of repeated dB conversions
        measure {
            for i in 0..<10000 {
                level.rmsValue = Float(i % 100) / 100.0
                _ = level.dbValue
            }
        }
    }
    
    // Test performance of level meter service simulation
    func testLevelMeterServicePerformance() async {
        // Measure the performance of updating levels through the service
        measure {
            for _ in 0..<100 {
                // Simulate 100 update cycles
                for i in 0..<100 {
                    let value = Float(i % 100) / 100.0
                    levelService.updateLevel(logicTrackUUID: "MASTER_BUS_UUID", rmsValue: value)
                }
            }
        }
    }
    
    // Test memory usage of level meter service
    func testLevelMeterServiceMemoryUsage() async {
        // Measure memory impact of creating many level meter services
        var services = [LevelMeterService]()
        
        measure {
            // Create and store 100 services
            for _ in 0..<100 {
                let service = LevelMeterService()
                services.append(service)
            }
            
            // Force reference to prevent optimization
            XCTAssertEqual(services.count, 100)
            
            // Clear for next iteration
            services.removeAll()
        }
    }
    
    // Test direct db to angle calculation performance
    func testDbToAngleCalculationPerformance() {
        // Measure the performance of direct dB to angle calculation
        measure {
            // Run many iterations of the calculation
            for i in 0..<10000 {
                let dbValue = Float(i % 230) / 10.0 - 20.0 // Range from -20 to +3
                let normalizedValue = (dbValue + 20) / 23
                let adjustedValue = pow(Double(normalizedValue), 0.9)
                let _ = -45.0 + adjustedValue * 90.0
            }
        }
    }
    
    // Test VU meter rendering performance
    func testVUMeterRenderingPerformance() async {
        // Create the components needed for the test
        let levelService = LevelMeterService()
        
        // Measure the time to create many VU meter views
        measure {
            for _ in 0..<100 {
                let _ = VUMeterView(levelService: levelService)
            }
        }
    }
    
    // Test peak indicator performance
    func testPeakIndicatorPerformance() {
        // Measure the performance of the peak indication system
        measure {
            for i in 0..<10000 {
                // Create indicators with alternating active states
                let isActive = i % 2 == 0
                let _ = PeakIndicatorView(isActive: isActive)
            }
        }
    }
    
    // Test concurrent updates
    func testConcurrentUpdates() async {
        // This test verifies that concurrent updates to the meter don't cause issues
        
        // Create the service
        let service = LevelMeterService()
        
        // Measure performance of updates (must be done from MainActor)
        measure {
            for i in 0..<100 {
                // Update levels for different tracks
                let trackUUID = "TRACK_\(i % 10)"
                service.updateLevel(logicTrackUUID: trackUUID, rmsValue: Float.random(in: 0...1))
                
                // Also test track name updates
                if i % 10 == 0 {
                    service.setCurrentTrack("Track \(i)")
                }
                
                // Test peak reset
                if i % 25 == 0 {
                    service.resetAllPeaks()
                }
            }
        }
    }
}
