/*
  ==============================================================================

    TelemetryData.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Data structure for telemetry information sent via OSC.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"

namespace AIplayer {

/**
 * @struct TelemetryData
 * @brief Contains all telemetry information for a single update
 * 
 * This structure holds all the data that needs to be sent
 * periodically to ChattyChannels for VU meter display and monitoring.
 */
struct TelemetryData
{
    /// Track identifier (e.g., "TR1", "TR2", "TR3")
    juce::String trackID;
    
    /// Current RMS level (linear, not dB)
    float rmsLevel{0.0f};
    
    /// Current peak level (linear, not dB)
    float peakLevel{0.0f};
    
    /// Plugin instance ID (UUID)
    juce::String instanceID;
    
    /// Timestamp of the measurement
    juce::Time timestamp{juce::Time::getCurrentTime()};
    
    /**
     * @brief Checks if the telemetry data is valid
     * 
     * @return true if all required fields are populated
     */
    bool isValid() const
    {
        return !trackID.isEmpty() && 
               !instanceID.isEmpty() &&
               rmsLevel >= 0.0f &&
               peakLevel >= 0.0f;
    }
    
    /**
     * @brief Converts the telemetry data to a string for logging
     * 
     * @return String representation of the telemetry data
     */
    juce::String toString() const
    {
        return juce::String::formatted("TelemetryData[track=%s, rms=%.4f, peak=%.4f, instance=%s]",
                                      trackID.toRawUTF8(),
                                      rmsLevel,
                                      peakLevel,
                                      instanceID.toRawUTF8());
    }
};

} // namespace AIplayer
