// AudioLevel.swift
//
// Model representing audio levels for VU meter display

import Foundation

/// Represents an audio level for a specific track, identified by its Logic Pro UUID.
public struct AudioLevel: Identifiable {
    /// The unique identifier for this audio level, corresponding to Logic Pro's track UUID.
    public let id: String // This will be the logicTrackUUID

    /// Current RMS amplitude value (0.0-1.0). Renamed from 'value' for clarity.
    public var rmsValue: Float = 0.0
    
    /// Peak RMS value recorded for peak indicator functionality. Renamed from 'peakValue'.
    public var peakRmsValue: Float = 0.0
    
    /// Optional name of the track, can be populated for UI display.
    public var trackName: String? = nil

    /// Timestamp of the last update. Useful for UI or decay logic.
    public var lastUpdateTime: Date = Date()
    
    // MARK: - V0.6 Compatibility Properties and Types
    
    /// Audio channel options for v0.6 compatibility (left or right)
    public enum AudioChannel {
        case left
        case right
    }
    
    /// The audio channel this level represents - for v0.6 compatibility
    public var channel: AudioChannel? = nil
    
    /// V0.6 compatibility - value getter/setter
    public var value: Float {
        get { return rmsValue }
        set { rmsValue = newValue }
    }
    
    /// V0.6 compatibility - peakValue getter/setter
    public var peakValue: Float {
        get { return peakRmsValue }
        set { peakRmsValue = newValue }
    }
    
    /// Initializes a new AudioLevel.
    /// - Parameters:
    ///   - id: The logicTrackUUID.
    ///   - rmsValue: Initial RMS value.
    ///   - peakRmsValue: Initial peak RMS value.
    ///   - trackName: Optional track name.
    public init(id: String, rmsValue: Float = 0.0, peakRmsValue: Float = 0.0, trackName: String? = nil) {
        self.id = id
        self.rmsValue = rmsValue
        self.peakRmsValue = peakRmsValue
        self.trackName = trackName
        self.lastUpdateTime = Date()
    }
    
    /// Initializes a new AudioLevel with v0.6 compatibility
    /// - Parameters:
    ///   - value: Initial value
    ///   - channel: Audio channel
    ///   - trackName: Optional track name
    public init(value: Float = 0.0, peakValue: Float = 0.0, channel: AudioChannel, trackName: String = "") {
        let channelId = channel == .left ? "LEFT" : "RIGHT"
        self.id = channelId
        self.rmsValue = value
        self.peakRmsValue = peakValue
        self.trackName = trackName
        self.channel = channel
        self.lastUpdateTime = Date()
    }
    
    /// Convert current RMS value to dBFS.
    public var dbfsValue: Float {
        guard rmsValue > 0 else { return -120.0 } // Return -120 dB for silence instead of -infinity
        let db = 20 * log10(rmsValue)
        // Clamp to reasonable range to avoid extreme values
        return max(-120.0, min(6.0, db))
    }
    
    /// Convert raw value to dB (v0.6 compatibility)
    public var dbValue: Float {
        return dbfsValue
    }
    
    /// Is current RMS level above a peak threshold (e.g., 0dBFS)?
    public var isPeaking: Bool {
        return dbfsValue >= 0.0
    }
}
