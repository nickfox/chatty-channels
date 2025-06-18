/*
  ==============================================================================

    AudioMetrics.cpp
    Created: 16 Jun 2025
    Author:  Nick Fox

    Implementation of audio measurement and analysis component.

  ==============================================================================
*/

#include "AudioMetrics.h"

namespace AIplayer {

AudioMetrics::AudioMetrics()
{
    // Initialize metrics buffer with a reasonable size
    // This will be resized as needed in updateMetrics
    metricsBuffer.setSize(2, 512, false, true, false);
}

float AudioMetrics::calculateRMS(const juce::AudioBuffer<float>& buffer) const
{
    const int numChannels = buffer.getNumChannels();
    const int numSamples = buffer.getNumSamples();
    
    // If no data, return minimum value
    if (numChannels == 0 || numSamples == 0)
        return 0.0001f;
    
    // Total number of samples across all channels
    const int totalSamples = numChannels * numSamples;
    
    // Sum of squared samples
    float sum = 0.0f;
    
    // Process 4 samples at a time where possible for better performance
    const int numQuads = numSamples / 4;
    
    // Sum squared samples across all channels
    for (int channel = 0; channel < numChannels; ++channel)
    {
        const float* channelData = buffer.getReadPointer(channel);
        
        // Process 4 samples at a time for most of the buffer
        for (int quad = 0; quad < numQuads; ++quad)
        {
            const int sampleIdx = quad * 4;
            const float s1 = channelData[sampleIdx];
            const float s2 = channelData[sampleIdx + 1];
            const float s3 = channelData[sampleIdx + 2];
            const float s4 = channelData[sampleIdx + 3];
            
            sum += s1 * s1 + s2 * s2 + s3 * s3 + s4 * s4;
        }
        
        // Process any remaining samples
        for (int sample = numQuads * 4; sample < numSamples; ++sample)
        {
            const float value = channelData[sample];
            sum += value * value;
        }
    }
    
    // Calculate the mean of all squared samples
    const float meanSquare = sum / static_cast<float>(totalSamples);
    
    // Take the square root to get the RMS value
    // Add small epsilon to avoid denormals
    return std::sqrt(meanSquare + 1.0e-10f);
}

void AudioMetrics::updateMetrics(const juce::AudioBuffer<float>& buffer)
{
    // Calculate current RMS
    const float rms = calculateRMS(buffer);
    currentRMS.store(rms);
    
    // Calculate peak level
    float peak = 0.0f;
    
    for (int channel = 0; channel < buffer.getNumChannels(); ++channel)
    {
        const float channelPeak = buffer.getMagnitude(channel, 0, buffer.getNumSamples());
        if (channelPeak > peak)
            peak = channelPeak;
    }
    
    peakLevel.store(peak);
    
    // Optionally store a copy of the buffer for later analysis
    // This is only needed if we want to calculate metrics outside the audio thread
    {
        const juce::ScopedLock sl(bufferLock);
        
        // Resize if needed
        if (metricsBuffer.getNumChannels() != buffer.getNumChannels() ||
            metricsBuffer.getNumSamples() != buffer.getNumSamples())
        {
            metricsBuffer.setSize(buffer.getNumChannels(), 
                                 buffer.getNumSamples(), 
                                 false, false, true);
        }
        
        // Copy the buffer
        for (int channel = 0; channel < buffer.getNumChannels(); ++channel)
        {
            metricsBuffer.copyFrom(channel, 0, buffer, channel, 0, buffer.getNumSamples());
        }
    }
}

void AudioMetrics::reset()
{
    currentRMS.store(0.0f);
    peakLevel.store(0.0f);
    
    const juce::ScopedLock sl(bufferLock);
    metricsBuffer.clear();
}

} // namespace AIplayer
