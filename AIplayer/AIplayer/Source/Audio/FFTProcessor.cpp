/*
  ==============================================================================

    FFTProcessor.cpp
    Created: 18 Jun 2025
    Author:  Nick Fox

    Implementation of FFT processing component.

  ==============================================================================
*/

#include "FFTProcessor.h"

namespace AIplayer {

FFTProcessor::FFTProcessor(int order)
    : fftOrder(order)
    , fftSize(1 << order)
    , fft(order)
    , window(fftSize, juce::dsp::WindowingFunction<float>::hann)
{
    // Initialize buffers
    circularBuffer.setSize(1, fftSize * 2); // Double size for circular buffer
    circularBuffer.clear();
    
    // Resize FFT data arrays
    fftData.resize(fftSize * 2); // Complex FFT needs 2x size
    magnitudeData.resize(fftSize / 2);
    
    // Clear arrays
    std::fill(fftData.begin(), fftData.end(), 0.0f);
    std::fill(magnitudeData.begin(), magnitudeData.end(), 0.0f);
}

void FFTProcessor::processAudioBlock(const juce::AudioBuffer<float>& buffer, double sampleRate)
{
    currentSampleRate.store(sampleRate);
    binWidth.store(static_cast<float>(sampleRate / fftSize));
    
    const int numSamples = buffer.getNumSamples();
    const int numChannels = buffer.getNumChannels();
    
    if (numChannels == 0 || numSamples == 0)
        return;
    
    // Mix to mono and write to circular buffer
    auto* circularData = circularBuffer.getWritePointer(0);
    const int bufferSize = circularBuffer.getNumSamples();
    
    for (int sample = 0; sample < numSamples; ++sample)
    {
        float monoSample = 0.0f;
        
        // Sum all channels
        for (int channel = 0; channel < numChannels; ++channel)
        {
            monoSample += buffer.getSample(channel, sample);
        }
        
        // Average for mono
        monoSample /= static_cast<float>(numChannels);
        
        // Write to circular buffer
        const int writePos = writePosition.load();
        circularData[writePos] = monoSample;
        
        // Update write position (circular)
        writePosition.store((writePos + 1) % bufferSize);
    }
    
    // Update samples available
    int currentAvailable = samplesAvailable.load();
    samplesAvailable.store(std::min(currentAvailable + numSamples, fftSize));
}

bool FFTProcessor::computeFFT()
{
    // Check if we have enough samples
    if (samplesAvailable.load() < fftSize)
        return false;
    
    const juce::ScopedLock sl(fftLock);
    
    // Copy from circular buffer to FFT input with proper ordering
    auto* circularData = circularBuffer.getReadPointer(0);
    const int bufferSize = circularBuffer.getNumSamples();
    int readPos = (writePosition.load() - fftSize + bufferSize) % bufferSize;
    
    // Fill FFT data array (real part only, imaginary part is zero)
    for (int i = 0; i < fftSize; ++i)
    {
        fftData[i] = circularData[readPos];
        fftData[i + fftSize] = 0.0f; // Imaginary part
        readPos = (readPos + 1) % bufferSize;
    }
    
    // Apply window function to real part only
    window.multiplyWithWindowingTable(fftData.data(), fftSize);
    
    // Perform FFT
    fft.performFrequencyOnlyForwardTransform(fftData.data());
    
    // Calculate magnitude spectrum
    // Note: For real input, we only need the first half of the spectrum
    for (int i = 0; i < fftSize / 2; ++i)
    {
        const float real = fftData[i];
        const float imag = fftData[i + fftSize];
        const float magnitude = std::sqrt(real * real + imag * imag);
        
        // Normalize by FFT size
        magnitudeData[i] = magnitude / static_cast<float>(fftSize / 2);
    }
    
    // Mark FFT as ready
    fftReady.store(true);
    
    // Reset samples available for next FFT
    samplesAvailable.store(0);
    
    return true;
}

} // namespace AIplayer