/*
  ==============================================================================

    CalibrationToneGenerator.cpp
    Created: 16 Jun 2025
    Author:  Nick Fox

    Implementation of calibration tone generator component.

  ==============================================================================
*/

#include "CalibrationToneGenerator.h"

namespace AIplayer {

CalibrationToneGenerator::CalibrationToneGenerator()
{
    // Initialize the oscillator with a sine wave function
    oscillator.initialise([](float x) { return std::sin(x); });
}

void CalibrationToneGenerator::prepare(double sampleRate, int samplesPerBlock)
{
    // Store the process specification
    processSpec.sampleRate = sampleRate;
    processSpec.maximumBlockSize = static_cast<juce::uint32>(samplesPerBlock);
    processSpec.numChannels = 2; // Default to stereo
    
    // Prepare the oscillator
    oscillator.prepare(processSpec);
    oscillator.setFrequency(frequency.load());
    
    isPrepared = true;
}

void CalibrationToneGenerator::setTone(float freq, float amplitudeDb)
{
    // Store frequency
    frequency.store(freq);
    
    // Convert dB to linear gain and store
    const float linearGain = juce::Decibels::decibelsToGain(amplitudeDb);
    amplitude.store(linearGain);
    
    // Update oscillator frequency if prepared
    if (isPrepared)
    {
        oscillator.setFrequency(freq);
    }
}

void CalibrationToneGenerator::startTone()
{
    if (isPrepared)
    {
        // Reset the oscillator phase for a clean start
        oscillator.reset();
        
        // Update frequency in case it changed
        oscillator.setFrequency(frequency.load());
    }
    
    // Enable tone generation
    toneEnabled.store(true);
}

void CalibrationToneGenerator::stopTone()
{
    toneEnabled.store(false);
}

void CalibrationToneGenerator::processBlock(juce::AudioBuffer<float>& buffer)
{
    // Check if tone generation is enabled
    if (!toneEnabled.load() || !isPrepared)
        return;
    
    // Get current amplitude
    const float currentAmplitude = amplitude.load();
    
    // Update oscillator frequency in case it changed
    oscillator.setFrequency(frequency.load());
    
    // Create a temporary buffer for the tone
    juce::AudioBuffer<float> toneBuffer(buffer.getNumChannels(), buffer.getNumSamples());
    toneBuffer.clear();
    
    // Create audio block and process context for the tone buffer
    juce::dsp::AudioBlock<float> toneBlock(toneBuffer);
    juce::dsp::ProcessContextReplacing<float> context(toneBlock);
    
    // Generate the tone
    oscillator.process(context);
    
    // Mix the tone with the existing audio
    for (int channel = 0; channel < buffer.getNumChannels(); ++channel)
    {
        buffer.addFrom(channel, 0, toneBuffer, channel, 0, 
                      buffer.getNumSamples(), currentAmplitude);
    }
}

} // namespace AIplayer
