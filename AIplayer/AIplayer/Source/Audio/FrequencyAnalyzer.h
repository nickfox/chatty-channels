/*
  ==============================================================================

    FrequencyAnalyzer.h
    Created: 18 Jun 2025
    Author:  Nick Fox

    High-level frequency analysis coordinator that manages FFT processing
    and band energy extraction for the AIplayer plugin.

  ==============================================================================
*/

#pragma once

#include <JuceHeader.h>
#include "FFTProcessor.h"
#include "BandEnergyAnalyzer.h"
#include "../Core/Logger.h"
#include <memory>
#include <atomic>

namespace AIplayer {

/**
 * @class FrequencyAnalyzer
 * @brief Coordinates FFT processing and band energy analysis
 * 
 * This class provides a high-level interface for frequency analysis:
 * - Manages FFT processor and band analyzer components
 * - Implements lazy computation to minimize CPU usage
 * - Provides thread-safe access to analysis results
 * - Configurable update rates and FFT parameters
 */
class FrequencyAnalyzer : public juce::Timer
{
public:
    /**
     * @brief Configuration for frequency analysis
     */
    struct Config
    {
        int fftOrder;                         // FFT size = 2^fftOrder
        int updateRateHz;                     // How often to compute FFT
        bool enableAWeighting;                // Apply A-weighting to bands
        bool autoStart;                       // Start analysis automatically
        const float* customBandLimits;        // Custom frequency bands
        
        Config() : fftOrder(10), updateRateHz(10), enableAWeighting(false), 
                   autoStart(true), customBandLimits(nullptr) {}
    };
    
    /**
     * @brief Construct frequency analyzer with configuration
     * @param logger Reference to logger for diagnostics
     * @param config Analysis configuration
     */
    explicit FrequencyAnalyzer(Logger& logger, const Config& config = Config());
    ~FrequencyAnalyzer() override;
    
    /**
     * @brief Process audio block and trigger analysis if needed
     * @param buffer Audio buffer to analyze
     * @param sampleRate Current sample rate
     */
    void processBlock(const juce::AudioBuffer<float>& buffer, double sampleRate);
    
    /**
     * @brief Start frequency analysis
     */
    void startAnalysis();
    
    /**
     * @brief Stop frequency analysis
     */
    void stopAnalysis();
    
    /**
     * @brief Check if analysis is currently running
     * @return true if analyzer is active
     */
    bool isAnalyzing() const { return isTimerRunning(); }
    
    /**
     * @brief Get current band energies in dB
     * @return Array of 4 band energy values
     */
    std::array<float, 4> getBandEnergies() const;
    
    /**
     * @brief Get energy for a specific band
     * @param band Band index (0-3)
     * @return Energy in dB
     */
    float getBandEnergy(int band) const;
    
    /**
     * @brief Force immediate FFT computation
     * @return true if FFT was computed successfully
     */
    bool computeNow();
    
    /**
     * @brief Get performance statistics
     * @return Average FFT computation time in milliseconds
     */
    float getAverageComputeTime() const { return averageComputeTime.load(); }
    
    /**
     * @brief Get FFT configuration
     * @return Current FFT order (size = 2^order)
     */
    int getFFTOrder() const { return fftProcessor->getFFTSize(); }
    
    /**
     * @brief Enable/disable A-weighting
     * @param enable true to enable A-weighting
     */
    void setAWeighting(bool enable);
    
    /**
     * @brief Set analysis update rate
     * @param hz Update rate in Hz (1-100)
     */
    void setUpdateRate(int hz);

private:
    // Timer callback for lazy computation
    void timerCallback() override;
    
    // Components
    std::unique_ptr<FFTProcessor> fftProcessor;
    std::unique_ptr<BandEnergyAnalyzer> bandAnalyzer;
    Logger& logger;
    
    // Configuration
    Config config;
    std::atomic<bool> shouldCompute{false};
    std::atomic<int> computeCounter{0};
    
    // Performance monitoring
    std::atomic<float> averageComputeTime{0.0f};
    std::atomic<int> computeCount{0};
    double totalComputeTime{0.0};
    
    // Thread safety
    mutable juce::CriticalSection analysisLock;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(FrequencyAnalyzer)
};

} // namespace AIplayer