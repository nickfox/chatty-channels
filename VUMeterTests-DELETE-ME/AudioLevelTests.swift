// AudioLevelTests.swift
// Tests for the AudioLevel model

import XCTest
@testable import ChattyChannels

final class AudioLevelTests: XCTestCase {
    
    // Test initialization with default values
    func testInitialization() {
        let level = AudioLevel(channel: .left)
        
        XCTAssertEqual(level.value, 0.0, "Default value should be 0.0")
        XCTAssertEqual(level.peakValue, 0.0, "Default peak value should be 0.0")
        XCTAssertEqual(level.channel, AudioLevel.AudioChannel.left, "Channel should be set correctly")
        XCTAssertEqual(level.trackName, "", "Default track name should be empty string")
    }
    
    // Test dB value conversion
    func testDBConversion() {
        var level = AudioLevel(channel: .left)
        
        // Test 0.0 (minimum value, should use 0.0001 to avoid -Infinity)
        level.value = 0.0
        XCTAssertEqual(level.dbValue, -80.0, accuracy: 0.01, "0.0 should convert to around -80 dB")
        
        // Test 0.0001 (minimal non-zero value)
        level.value = 0.0001
        XCTAssertEqual(level.dbValue, -80.0, accuracy: 0.01, "0.0001 should convert to around -80 dB")
        
        // Test 0.001 (-60 dB)
        level.value = 0.001
        XCTAssertEqual(level.dbValue, -60.0, accuracy: 0.01, "0.001 should convert to -60 dB")
        
        // Test 0.01 (-40 dB)
        level.value = 0.01
        XCTAssertEqual(level.dbValue, -40.0, accuracy: 0.01, "0.01 should convert to -40 dB")
        
        // Test 0.1 (-20 dB)
        level.value = 0.1
        XCTAssertEqual(level.dbValue, -20.0, accuracy: 0.01, "0.1 should convert to -20 dB")
        
        // Test 0.5 (-6 dB)
        level.value = 0.5
        XCTAssertEqual(level.dbValue, -6.02, accuracy: 0.01, "0.5 should convert to around -6 dB")
        
        // Test 1.0 (0 dB)
        level.value = 1.0
        XCTAssertEqual(level.dbValue, 0.0, accuracy: 0.01, "1.0 should convert to 0 dB")
    }
    
    // Test peak detection
    func testPeakDetection() {
        var level = AudioLevel(channel: .right)
        
        // Test below peak threshold
        level.value = 0.5  // -6 dB, should not peak
        XCTAssertFalse(level.isPeaking, "Value of 0.5 (-6 dB) should not trigger peak")
        
        // Test at peak threshold
        level.value = 1.0  // 0 dB, should peak
        XCTAssertTrue(level.isPeaking, "Value of 1.0 (0 dB) should trigger peak")
        
        // Test above peak threshold
        level.value = 1.5  // +3.5 dB, should peak
        XCTAssertTrue(level.isPeaking, "Value of 1.5 (+3.5 dB) should trigger peak")
    }
    
    // Test setting track name
    func testTrackName() {
        var level = AudioLevel(channel: .left)
        
        // Default value test
        XCTAssertEqual(level.trackName, "", "Default track name should be empty string")
        
        // Setting track name
        level.trackName = "Kick Drum"
        XCTAssertEqual(level.trackName, "Kick Drum", "Track name should be updated correctly")
    }
}
