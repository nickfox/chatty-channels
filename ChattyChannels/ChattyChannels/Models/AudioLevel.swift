// AudioLevel.swift
//
// Model representing audio levels for VU meter display

import Foundation

/// Represents an audio level for a specific channel with associated metadata.
struct AudioLevel {
    /// Raw amplitude value (0.0-1.0)
    var value: Float = 0.0
    
    /// Peak value for peak indicator functionality
    var peakValue: Float = 0.0
    
    /// The audio channel this level represents
    var channel: AudioChannel
    
    /// Name of the currently monitored track
    var trackName: String = ""
    
    /// Audio channel options (left or right)
    enum AudioChannel {
        case left
        case right
    }
    
    /// Convert raw value to dB
    var dbValue: Float {
        return 20 * log10(max(value, 0.0001))
    }
    
    /// Is level above peak threshold? (0dB)
    var isPeaking: Bool {
        return dbValue >= 0.0
    }
}
