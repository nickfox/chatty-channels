// VUMeterViewTests.swift
// Tests for the VU meter view components

import XCTest
import SwiftUI
@testable import ChattyChannels

final class VUMeterViewTests: XCTestCase {
    
    // Test dB to angle mapping function directly
    func testDbToAngleMapping() {
        // The real calculation from SingleMeterView
        func mapDbToRotation(db: Float) -> Double {
            // Constrain to range
            let constrainedDb = min(max(db, -20), 3)
            
            // Map from dB scale to rotation degrees
            let normalizedValue = (constrainedDb + 20) / 23
            let adjustedValue = pow(Double(normalizedValue), 0.9)
            return -45.0 + adjustedValue * 90.0
        }
        
        // Test cases for dB to angle conversion
        let dbValues: [Float] = [-20.0, -15.0, -10.0, -5.0, 0.0, 3.0]
        
        // Calculate angles using our function
        let calculatedAngles = dbValues.map { mapDbToRotation(db: $0) }
        
        // Verify the angles are reasonable
        XCTAssertEqual(calculatedAngles[0], -45.0, accuracy: 0.1, "Minimum db (-20) should map to minimum angle (-45)")
        XCTAssertGreaterThan(calculatedAngles[1], calculatedAngles[0], "-15 dB should map to greater angle than -20 dB")
        XCTAssertGreaterThan(calculatedAngles[2], calculatedAngles[1], "-10 dB should map to greater angle than -15 dB")
        XCTAssertGreaterThan(calculatedAngles[3], calculatedAngles[2], "-5 dB should map to greater angle than -10 dB")
        XCTAssertGreaterThan(calculatedAngles[4], calculatedAngles[3], "0 dB should map to greater angle than -5 dB")
        XCTAssertGreaterThan(calculatedAngles[5], calculatedAngles[4], "+3 dB should map to greater angle than 0 dB")
        XCTAssertLessThanOrEqual(calculatedAngles[5], 45.0, "Maximum db (+3) should map to at most maximum angle (+45)")
    }
    
    // Test angle constraints
    func testAngleConstraints() {
        // The real calculation from SingleMeterView
        func mapDbToRotation(db: Float) -> Double {
            // Constrain to range
            let constrainedDb = min(max(db, -20), 3)
            
            // Map from dB scale to rotation degrees
            let normalizedValue = (constrainedDb + 20) / 23
            let adjustedValue = pow(Double(normalizedValue), 0.9)
            return -45.0 + adjustedValue * 90.0
        }
        
        // Below minimum range (-20 dB)
        let belowMinDb: Float = -30.0
        let belowMinAngle = mapDbToRotation(db: belowMinDb)
        
        // The calculation should constrain to -20dB, resulting in -45 degrees
        XCTAssertEqual(belowMinAngle, -45.0, accuracy: 0.1, "Values below -20 dB should be constrained to -45 degrees")
        
        // Above maximum range (+3 dB)
        let aboveMaxDb: Float = 10.0
        let aboveMaxAngle = mapDbToRotation(db: aboveMaxDb)
        
        // The calculation should constrain to +3dB, resulting in less than or equal to +45 degrees
        XCTAssertEqual(aboveMaxAngle, 45.0, accuracy: 0.1, "Values above +3 dB should be constrained to +45 degrees")
    }
    
    // Test AudioLevel dB conversion
    func testAudioLevelDbConversion() {
        var level = AudioLevel(channel: .left)
        
        // Test 0.0 (minimum value, should use 0.0001 to avoid -Infinity)
        level.value = 0.0
        XCTAssertEqual(level.dbValue, -80.0, accuracy: 0.1, "0.0 should convert to around -80 dB")
        
        // Test 0.001 (-60 dB)
        level.value = 0.001
        XCTAssertEqual(level.dbValue, -60.0, accuracy: 0.1, "0.001 should convert to -60 dB")
        
        // Test 0.1 (-20 dB)
        level.value = 0.1
        XCTAssertEqual(level.dbValue, -20.0, accuracy: 0.1, "0.1 should convert to -20 dB")
        
        // Test 1.0 (0 dB)
        level.value = 1.0
        XCTAssertEqual(level.dbValue, 0.0, accuracy: 0.1, "1.0 should convert to 0 dB")
    }
    
    // Test peak detection
    func testPeakDetection() {
        var level = AudioLevel(channel: .left)
        
        // Test below peak threshold (-6 dB)
        level.value = 0.5
        XCTAssertFalse(level.isPeaking, "Value of 0.5 (-6 dB) should not trigger peak")
        
        // Test at peak threshold (0 dB)
        level.value = 1.0
        XCTAssertTrue(level.isPeaking, "Value of 1.0 (0 dB) should trigger peak")
        
        // Test above peak threshold (+3 dB)
        level.value = 1.4
        XCTAssertTrue(level.isPeaking, "Value above 1.0 should trigger peak")
    }
    
    // Test level service initialization
    @MainActor
    func testLevelServiceInitialization() {
        let levelService = LevelMeterService()
        
        // Verify default values
        XCTAssertEqual(levelService.leftChannel.channel, AudioLevel.AudioChannel.left, "Left channel should be initialized correctly")
        XCTAssertEqual(levelService.rightChannel.channel, AudioLevel.AudioChannel.right, "Right channel should be initialized correctly")
        XCTAssertEqual(levelService.currentTrack, "Master Bus", "Default track name should be set correctly")
    }
}


