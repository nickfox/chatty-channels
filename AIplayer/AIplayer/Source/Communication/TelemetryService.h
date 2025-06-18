/*
  ==============================================================================

    TelemetryService.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Telemetry collection and transmission service for AIplayer plugin.
    Manages periodic sending of audio metrics to ChattyChannels.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"
#include "../Core/Logger.h"
#include "../Core/Constants.h"
#include "../Models/TelemetryData.h"

namespace AIplayer {

// Forward declarations
class AudioMetrics;
class FrequencyAnalyzer;
class OSCManager;

/**
 * @class TelemetryService
 * @brief Collects and sends telemetry data at regular intervals
 * 
 * This service runs on a timer and periodically collects audio metrics
 * and sends them to ChattyChannels for VU meter display.
 */
class TelemetryService : public juce::Timer
{
public:
    /**
     * @brief Constructor
     * 
     * @param metrics Reference to audio metrics component
     * @param freqAnalyzer Reference to frequency analyzer component
     * @param oscManager Reference to OSC manager for sending data
     * @param logger Reference to logger for debugging
     */
    TelemetryService(AudioMetrics& metrics,
                     FrequencyAnalyzer& freqAnalyzer,
                     OSCManager& oscManager,
                     Logger& logger);
    
    /**
     * @brief Destructor
     */
    ~TelemetryService();
    
    /**
     * @brief Sets the track ID for telemetry
     * 
     * @param trackID The track identifier (e.g., "TR1", "TR2")
     */
    void setTrackID(const juce::String& trackID);
    
    /**
     * @brief Sets the instance ID for telemetry
     * 
     * @param instanceID The plugin instance UUID
     */
    void setInstanceID(const juce::String& instanceID);
    
    /**
     * @brief Starts sending telemetry at the specified rate
     * 
     * @param frequencyHz Update frequency in Hz (default 24Hz)
     */
    void startTelemetry(int frequencyHz = Constants::TELEMETRY_RATE_HZ);
    
    /**
     * @brief Stops sending telemetry
     */
    void stopTelemetry();
    
    /**
     * @brief Checks if telemetry is currently active
     * 
     * @return true if timer is running
     */
    bool isActive() const { return isTimerRunning(); }
    
    /**
     * @brief Gets the current track ID
     * 
     * @return Current track ID
     */
    juce::String getTrackID() const { return currentTrackID; }
    
    /**
     * @brief Gets the current instance ID
     * 
     * @return Current instance ID
     */
    juce::String getInstanceID() const { return currentInstanceID; }
    
    /**
     * @brief Manually triggers a telemetry update
     * 
     * Useful for testing or forced updates.
     */
    void sendTelemetryNow();
    
private:
    /// Reference to audio metrics
    AudioMetrics& audioMetrics;
    
    /// Reference to frequency analyzer
    FrequencyAnalyzer& frequencyAnalyzer;
    
    /// Reference to OSC manager
    OSCManager& oscManager;
    
    /// Reference to logger
    Logger& logger;
    
    /// Current track ID
    juce::String currentTrackID;
    
    /// Current instance ID
    juce::String currentInstanceID;
    
    /// Counter for logging frequency reduction
    std::atomic<int> updateCounter{0};
    
    /// Log every Nth update to reduce log spam
    static constexpr int LOG_FREQUENCY = 24; // Log once per second at 24Hz
    
    /**
     * @brief Timer callback - called at regular intervals
     * 
     * Collects telemetry data and sends it via OSC.
     */
    void timerCallback() override;
    
    /**
     * @brief Collects current telemetry data
     * 
     * @return Populated telemetry data structure
     */
    TelemetryData collectTelemetryData();
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(TelemetryService)
};

} // namespace AIplayer
