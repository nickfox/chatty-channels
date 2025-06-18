/*
  ==============================================================================

    AudioMetrics.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Audio measurement and analysis component for AIplayer plugin.
    Handles RMS calculations and other audio metrics with thread safety.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"
#include <atomic>

namespace AIplayer {

/**
 * @class AudioMetrics
 * @brief Calculates and stores audio measurements including RMS and peak levels
 * 
 * Thread-safe audio analysis component that can be called from both
 * audio thread (for updating) and other threads (for reading).
 */
class AudioMetrics
{
public:
    /**
     * @brief Default constructor
     */
    AudioMetrics();
    
    /**
     * @brief Destructor
     */
    ~AudioMetrics() = default;
    
    /**
     * @brief Calculates the RMS value from an audio buffer
     * 
     * Can be called from any thread. Does not modify internal state.
     * 
     * @param buffer The audio buffer to calculate RMS from
     * @return The calculated RMS value (linear, not dB)
     */
    float calculateRMS(const juce::AudioBuffer<float>& buffer) const;
    
    /**
     * @brief Updates internal metrics based on the provided audio buffer
     * 
     * Should be called from the audio thread during processBlock.
     * Updates currentRMS and peakLevel atomically.
     * 
     * @param buffer The audio buffer to analyze
     */
    void updateMetrics(const juce::AudioBuffer<float>& buffer);
    
    /**
     * @brief Gets the current RMS level
     * 
     * Thread-safe getter for the most recent RMS value.
     * 
     * @return Current RMS level (linear, not dB)
     */
    float getCurrentRMS() const { return currentRMS.load(); }
    
    /**
     * @brief Gets the current peak level
     * 
     * Thread-safe getter for the most recent peak value.
     * 
     * @return Current peak level (linear, not dB)
     */
    float getPeakLevel() const { return peakLevel.load(); }
    
    /**
     * @brief Resets all metrics to zero
     * 
     * Can be called from any thread.
     */
    void reset();
    
private:
    /// Current RMS level (atomic for thread safety)
    std::atomic<float> currentRMS{0.0f};
    
    /// Current peak level (atomic for thread safety)
    std::atomic<float> peakLevel{0.0f};
    
    /// Buffer for thread-safe metric calculations
    juce::AudioBuffer<float> metricsBuffer;
    
    /// Lock for protecting metricsBuffer access
    mutable juce::CriticalSection bufferLock;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AudioMetrics)
};

} // namespace AIplayer
