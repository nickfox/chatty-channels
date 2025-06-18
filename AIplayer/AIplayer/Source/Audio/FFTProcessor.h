/*
  ==============================================================================

    FFTProcessor.h
    Created: 18 Jun 2025
    Author:  Nick Fox

    FFT processing component for frequency domain analysis.
    Handles FFT computation with configurable size and windowing.

  ==============================================================================
*/

#pragma once

#include <JuceHeader.h>
#include <array>
#include <atomic>

namespace AIplayer {

/**
 * @class FFTProcessor
 * @brief Handles FFT computation for frequency domain analysis
 * 
 * This class manages FFT processing including:
 * - Circular buffer for continuous audio input
 * - Windowing function application
 * - FFT computation
 * - Magnitude spectrum calculation
 */
class FFTProcessor
{
public:
    static constexpr int DEFAULT_FFT_ORDER = 10; // 2^10 = 1024 samples
    
    /**
     * @brief Construct FFT processor with specified order
     * @param fftOrder Power of 2 for FFT size (e.g., 10 for 1024 samples)
     */
    explicit FFTProcessor(int fftOrder = DEFAULT_FFT_ORDER);
    ~FFTProcessor() = default;
    
    /**
     * @brief Process audio samples and update internal buffer
     * @param buffer Audio buffer to process
     * @param sampleRate Current sample rate for frequency calculations
     */
    void processAudioBlock(const juce::AudioBuffer<float>& buffer, double sampleRate);
    
    /**
     * @brief Perform FFT computation if enough samples are available
     * @return true if FFT was computed, false otherwise
     */
    bool computeFFT();
    
    /**
     * @brief Get the magnitude spectrum from last FFT computation
     * @return Read-only access to magnitude data
     */
    const float* getMagnitudeSpectrum() const { return magnitudeData.data(); }
    
    /**
     * @brief Get the size of the magnitude spectrum (FFT size / 2)
     * @return Number of frequency bins in magnitude spectrum
     */
    int getMagnitudeSpectrumSize() const { return fftSize / 2; }
    
    /**
     * @brief Get the frequency resolution (Hz per bin)
     * @return Frequency width of each FFT bin
     */
    float getBinWidth() const { return binWidth.load(); }
    
    /**
     * @brief Check if FFT data is ready for processing
     * @return true if new FFT data is available
     */
    bool isFFTReady() const { return fftReady.load(); }
    
    /**
     * @brief Reset the FFT ready flag after processing
     */
    void resetFFTReady() { fftReady.store(false); }
    
    /**
     * @brief Get the FFT size
     * @return Current FFT size in samples
     */
    int getFFTSize() const { return fftSize; }

private:
    // FFT configuration
    const int fftOrder;
    const int fftSize;
    juce::dsp::FFT fft;
    juce::dsp::WindowingFunction<float> window;
    
    // Audio buffers
    juce::AudioBuffer<float> circularBuffer;
    std::atomic<int> writePosition{0};
    std::atomic<int> samplesAvailable{0};
    
    // FFT data
    std::vector<float> fftData;
    std::vector<float> magnitudeData;
    std::atomic<bool> fftReady{false};
    
    // Processing state
    std::atomic<float> binWidth{0.0f};
    std::atomic<double> currentSampleRate{44100.0};
    
    // Thread safety
    mutable juce::CriticalSection fftLock;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(FFTProcessor)
};

} // namespace AIplayer