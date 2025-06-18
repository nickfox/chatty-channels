/*
  ==============================================================================

    CalibrationToneGenerator.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Calibration tone generator for track identification in AIplayer plugin.
    Generates precise sine wave tones for audio track calibration.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"
#include <atomic>

namespace AIplayer {

/**
 * @class CalibrationToneGenerator
 * @brief Generates calibration tones for track identification
 * 
 * Thread-safe tone generator that can be controlled from any thread
 * and processes audio in the audio thread.
 */
class CalibrationToneGenerator
{
public:
    /**
     * @brief Constructor
     */
    CalibrationToneGenerator();
    
    /**
     * @brief Destructor
     */
    ~CalibrationToneGenerator() = default;
    
    /**
     * @brief Prepares the tone generator for playback
     * 
     * Must be called before processing audio, typically in prepareToPlay.
     * 
     * @param sampleRate The sample rate for audio processing
     * @param samplesPerBlock Maximum number of samples per process block
     */
    void prepare(double sampleRate, int samplesPerBlock);
    
    /**
     * @brief Sets the tone frequency and amplitude
     * 
     * Can be called from any thread. Changes take effect immediately.
     * 
     * @param frequency Tone frequency in Hz
     * @param amplitudeDb Tone amplitude in dB (typically negative values)
     */
    void setTone(float frequency, float amplitudeDb);
    
    /**
     * @brief Starts tone generation
     * 
     * Can be called from any thread.
     */
    void startTone();
    
    /**
     * @brief Stops tone generation
     * 
     * Can be called from any thread.
     */
    void stopTone();
    
    /**
     * @brief Processes audio, adding the calibration tone if enabled
     * 
     * Should be called from the audio thread in processBlock.
     * The tone is mixed with existing audio in the buffer.
     * 
     * @param buffer The audio buffer to process
     */
    void processBlock(juce::AudioBuffer<float>& buffer);
    
    /**
     * @brief Checks if tone generation is currently enabled
     * 
     * @return true if tone is being generated
     */
    bool isToneEnabled() const { return toneEnabled.load(); }
    
    /**
     * @brief Gets the current tone frequency
     * 
     * @return Current frequency in Hz
     */
    float getFrequency() const { return frequency.load(); }
    
    /**
     * @brief Gets the current tone amplitude
     * 
     * @return Current amplitude as linear gain (not dB)
     */
    float getAmplitude() const { return amplitude.load(); }
    
    /**
     * @brief Gets the current tone frequency (alias for getFrequency)
     * 
     * @return Current frequency in Hz
     */
    float getCurrentFrequency() const { return frequency.load(); }
    
    /**
     * @brief Gets the current tone amplitude in dB
     * 
     * @return Current amplitude in dB
     */
    float getCurrentAmplitudeDb() const { return juce::Decibels::gainToDecibels(amplitude.load()); }
    
private:
    /// DSP oscillator for tone generation
    juce::dsp::Oscillator<float> oscillator;
    
    /// Process specification for DSP
    juce::dsp::ProcessSpec processSpec;
    
    /// Whether tone generation is enabled
    std::atomic<bool> toneEnabled{false};
    
    /// Tone frequency in Hz
    std::atomic<float> frequency{440.0f};
    
    /// Tone amplitude (linear gain, not dB)
    std::atomic<float> amplitude{0.1f};
    
    /// Flag to indicate if the generator has been prepared
    bool isPrepared{false};
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(CalibrationToneGenerator)
};

} // namespace AIplayer
