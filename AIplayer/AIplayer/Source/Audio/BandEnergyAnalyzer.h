/*
  ==============================================================================

    BandEnergyAnalyzer.h
    Created: 18 Jun 2025
    Author:  Nick Fox

    Analyzes frequency spectrum and extracts band energies for mixing decisions.

  ==============================================================================
*/

#pragma once

#include <JuceHeader.h>
#include <array>
#include <atomic>

namespace AIplayer {

/**
 * @class BandEnergyAnalyzer
 * @brief Extracts energy levels from frequency bands
 * 
 * Divides the frequency spectrum into 4 bands relevant for mixing:
 * - Band 1 (Low):      20 Hz - 250 Hz    (bass, kick)
 * - Band 2 (Low-Mid):  250 Hz - 2 kHz    (vocals, snare, keys)
 * - Band 3 (High-Mid): 2 kHz - 8 kHz     (presence, clarity)
 * - Band 4 (High):     8 kHz - 20 kHz    (air, cymbals)
 */
class BandEnergyAnalyzer
{
public:
    static constexpr int NUM_BANDS = 4;
    
    // Default frequency band limits in Hz
    static constexpr float DEFAULT_BAND_LIMITS[NUM_BANDS + 1] = {
        20.0f,    // Low start
        250.0f,   // Low-Mid start
        2000.0f,  // High-Mid start
        8000.0f,  // High start
        20000.0f  // High end
    };
    
    /**
     * @brief Construct band energy analyzer with default or custom band limits
     * @param customBandLimits Optional array of 5 frequency limits (nullptr for defaults)
     */
    explicit BandEnergyAnalyzer(const float* customBandLimits = nullptr);
    ~BandEnergyAnalyzer() = default;
    
    /**
     * @brief Analyze magnitude spectrum and extract band energies
     * @param magnitudeSpectrum FFT magnitude data
     * @param numBins Number of frequency bins
     * @param binWidth Frequency width per bin (Hz)
     * @param sampleRate Current sample rate
     */
    void analyzeBands(const float* magnitudeSpectrum, 
                     int numBins, 
                     float binWidth,
                     double sampleRate);
    
    /**
     * @brief Get energy level for a specific band
     * @param band Band index (0-3)
     * @return Energy level in dB
     */
    float getBandEnergy(int band) const;
    
    /**
     * @brief Get all band energies
     * @return Array of band energies in dB
     */
    std::array<float, NUM_BANDS> getAllBandEnergies() const;
    
    /**
     * @brief Get band energy in linear scale (not dB)
     * @param band Band index (0-3)
     * @return Linear energy value
     */
    float getBandEnergyLinear(int band) const;
    
    /**
     * @brief Get descriptive name for a band
     * @param band Band index (0-3)
     * @return Band name (e.g., "Low", "Low-Mid")
     */
    static const char* getBandName(int band);
    
    /**
     * @brief Get frequency range for a band
     * @param band Band index (0-3)
     * @param lowFreq Output: low frequency limit
     * @param highFreq Output: high frequency limit
     */
    void getBandFrequencyRange(int band, float& lowFreq, float& highFreq) const;
    
    /**
     * @brief Enable/disable A-weighting for perceptual accuracy
     * @param enable true to enable A-weighting
     */
    void setAWeighting(bool enable) { useAWeighting = enable; }
    
    /**
     * @brief Check if new band energy data is available
     * @return true if new analysis has been performed
     */
    bool isAnalysisReady() const { return analysisReady.load(); }
    
    /**
     * @brief Reset the analysis ready flag
     */
    void resetAnalysisReady() { analysisReady.store(false); }

private:
    // Band configuration
    std::array<float, NUM_BANDS + 1> bandLimits;
    
    // Band energy storage (atomic for thread safety)
    std::array<std::atomic<float>, NUM_BANDS> bandEnergiesDb;
    std::array<std::atomic<float>, NUM_BANDS> bandEnergiesLinear;
    
    // Processing state
    std::atomic<bool> analysisReady{false};
    bool useAWeighting{false};
    
    // A-weighting coefficients
    float getAWeightingCoefficient(float frequency) const;
    
    // Helper to convert linear energy to dB
    static float linearToDb(float linear);
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(BandEnergyAnalyzer)
};

} // namespace AIplayer