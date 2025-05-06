// VUMeterPerformanceTests.swift
// Performance tests for the VU meter implementation

import XCTest
@testable import ChattyChannels

final class VUMeterPerformanceTests: XCTestCase {
    
    var levelService: LevelMeterService!
    var oscService: OSCService!
    
    override func setUp() {
        super.setUp()
        oscService = OSCService()
        levelService = LevelMeterService(oscService: oscService)
    }
    
    override func tearDown() {
        levelService = nil
        oscService = nil
        super.tearDown()
    }
    
    // Test performance of dB conversion calculations
    func testDbConversionPerformance() {
        // Create a test level
        var level = AudioLevel(channel: .left)
        
        // Measure performance of repeated dB conversions
        measure {
            for i in 0..<10000 {
                level.value = Float(i % 100) / 100.0
                _ = level.dbValue
            }
        }
    }
    
    // Test performance of level meter service simulation
    func testLevelMeterServicePerformance() {
        // Measure the performance of the service's level simulation
        // This is just an example - in a real app, you might measure actual OSC processing
        measure {
            for _ in 0..<100 {
                // Simulate 100 update cycles by setting values directly
                for i in 0..<100 {
                    // Update audio levels directly
                    let value = Float(i % 100) / 100.0
                    self.levelService.leftChannel.value = value
                    self.levelService.rightChannel.value = 1.0 - value
                }
            }
        }
    }
    
    // Test memory usage of level meter service
    func testLevelMeterServiceMemoryUsage() {
        // Measure memory impact of creating many level meter services
        var services = [LevelMeterService]()
        
        measure {
            // Create and store 100 services
            for _ in 0..<100 {
                let service = LevelMeterService(oscService: oscService)
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
    func testVUMeterRenderingPerformance() {
        // Create the components needed for the test
        let levelService = LevelMeterService(oscService: OSCService())
        
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
    func testConcurrentUpdates() {
        // This test verifies that concurrent updates to the meter don't cause issues
        
        // Create the service
        let service = LevelMeterService(oscService: OSCService())
        
        // Measure performance of concurrent access
        measure {
            DispatchQueue.concurrentPerform(iterations: 100) { i in
                // Perform concurrent updates from different threads
                if i % 2 == 0 {
                    service.leftChannel.value = Float.random(in: 0...1)
                } else {
                    service.rightChannel.value = Float.random(in: 0...1)
                }
                
                // Also test track name updates
                if i % 10 == 0 {
                    service.setCurrentTrack("Track \(i)")
                }
                
                // Test peak reset
                if i % 25 == 0 {
                    service.resetPeaks()
                }
            }
        }
    }
}


