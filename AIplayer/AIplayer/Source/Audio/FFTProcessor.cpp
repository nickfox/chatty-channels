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

/**
 * @brief Performs FFT computation on accumulated audio samples
 * 
 * @details This method implements the complete FFT processing pipeline:
 * 1. Validates sufficient samples are available (must have fftSize samples)
 * 2. Extracts oldest fftSize samples from circular buffer in correct order
 * 3. Applies Hann windowing to reduce spectral leakage
 * 4. Performs forward FFT transform using JUCE's optimized FFT
 * 5. Converts complex FFT output to magnitude spectrum
 * 6. Normalizes magnitude values for consistent scaling
 * 
 * The circular buffer read algorithm ensures temporal continuity by calculating
 * the correct starting position based on current write position.
 * 
 * @return true if FFT was computed successfully, false if insufficient samples
 * 
 * @note This method is thread-safe using fftLock to prevent concurrent access
 *       during FFT computation. The magnitude spectrum contains only positive
 *       frequencies (DC to Nyquist) as negative frequencies are redundant for real signals.
 * 
 * @warning The method resets samplesAvailable to 0 after computation, requiring
 *          new audio data before the next FFT can be performed.
 * 
 * @see processAudioBlock() for sample accumulation
 * @see getMagnitudeSpectrum() for accessing results
 */
bool FFTProcessor::computeFFT()
{
    // Check if we have accumulated enough samples for FFT computation
    if (samplesAvailable.load() < fftSize)
        return false;
    
    const juce::ScopedLock sl(fftLock); // Ensure thread-safe access to FFT data
    
    // Extract samples from circular buffer in correct chronological order
    auto* circularData = circularBuffer.getReadPointer(0);
    const int bufferSize = circularBuffer.getNumSamples();
    int readPos = (writePosition.load() - fftSize + bufferSize) % bufferSize;
    
    // Prepare FFT input data (interleaved real/imaginary format)
    for (int i = 0; i < fftSize; ++i)
    {
        fftData[i] = circularData[readPos];      // Real part: audio sample
        fftData[i + fftSize] = 0.0f;             // Imaginary part: zero for real input
        readPos = (readPos + 1) % bufferSize;    // Advance with wrap-around
    }
    
    // Apply Hann window to reduce spectral leakage and improve frequency resolution
    window.multiplyWithWindowingTable(fftData.data(), fftSize);
    
    // Perform forward FFT transform (time domain → frequency domain)
    fft.performFrequencyOnlyForwardTransform(fftData.data());
    
    // Convert complex FFT output to magnitude spectrum
    // For real input signals, only positive frequencies (0 to Nyquist) are meaningful
    for (int i = 0; i < fftSize / 2; ++i)
    {
        const float real = fftData[i];
        const float imag = fftData[i + fftSize];
        const float magnitude = std::sqrt(real * real + imag * imag);
        
        // Normalize magnitude by half FFT size for consistent scaling
        magnitudeData[i] = magnitude / static_cast<float>(fftSize / 2);
    }
    
    // Signal that new FFT data is available for consumption
    fftReady.store(true);
    
    // Reset sample counter to accumulate samples for next FFT
    samplesAvailable.store(0);
    
    return true;
}

} // namespace AIplayer