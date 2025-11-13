/*
  ==============================================================================

    BandEnergyAnalyzer.cpp
    Created: 18 Jun 2025
    Author:  Nick Fox

    Implementation of band energy analysis.

  ==============================================================================
*/

#include "BandEnergyAnalyzer.h"
#include <cmath>

namespace AIplayer {

BandEnergyAnalyzer::BandEnergyAnalyzer(const float* customBandLimits)
{
    // Initialize band limits
    if (customBandLimits != nullptr)
    {
        for (int i = 0; i <= NUM_BANDS; ++i)
        {
            bandLimits[i] = customBandLimits[i];
        }
    }
    else
    {
        for (int i = 0; i <= NUM_BANDS; ++i)
        {
            bandLimits[i] = DEFAULT_BAND_LIMITS[i];
        }
    }
    
    // Initialize band energies
    for (int i = 0; i < NUM_BANDS; ++i)
    {
        bandEnergiesDb[i].store(-100.0f);    // Very quiet initial value
        bandEnergiesLinear[i].store(0.0f);
    }
}

/**
 * @brief Analyzes FFT magnitude spectrum and extracts energy levels for each frequency band
 * 
 * @details This method implements frequency band energy analysis:
 * 1. Maps frequency bands to FFT bin ranges using binWidth
 * 2. Accumulates energy within each band (magnitude squared)
 * 3. Applies optional A-weighting for perceptual accuracy
 * 4. Averages energy across bins to prevent bias toward wider bands
 * 5. Stores both linear and dB values for different use cases
 * 
 * The analysis uses 4 mixing-relevant frequency bands:
 * - Low (20-250 Hz): Bass, kick drums
 * - Low-Mid (250-2000 Hz): Vocals, snare, keys
 * - High-Mid (2000-8000 Hz): Presence, clarity
 * - High (8000-20000 Hz): Air, cymbals, brightness
 * 
 * @param magnitudeSpectrum FFT magnitude data from FFTProcessor
 * @param numBins Number of frequency bins in the spectrum
 * @param binWidth Frequency resolution per bin (Hz/bin)
 * @param sampleRate Current sample rate (used for validation)
 * 
 * @note Energy calculation uses magnitude squared (power), not magnitude directly.
 *       Bin averaging prevents bands with more frequency bins from appearing louder.
 *       A-weighting follows ISO 226:2003 perceptual loudness curves when enabled.
 * 
 * @warning Input validation ensures magnitudeSpectrum is non-null and parameters are valid.
 *          Invalid input causes early return without updating band energies.
 * 
 * @see getAWeightingCoefficient() for A-weighting implementation
 * @see linearToDb() for energy conversion details
 */
void BandEnergyAnalyzer::analyzeBands(const float* magnitudeSpectrum, 
                                     int numBins, 
                                     float binWidth,
                                     double sampleRate)
{
    // Validate input parameters
    if (magnitudeSpectrum == nullptr || numBins <= 0 || binWidth <= 0.0f)
        return;
    
    // Analyze energy for each of the 4 frequency bands
    for (int band = 0; band < NUM_BANDS; ++band)
    {
        const float lowFreq = bandLimits[band];
        const float highFreq = bandLimits[band + 1];
        
        // Map frequency range to FFT bin indices
        int startBin = static_cast<int>(lowFreq / binWidth);
        int endBin = static_cast<int>(highFreq / binWidth);
        
        // Clamp bin indices to valid spectrum range
        startBin = juce::jlimit(0, numBins - 1, startBin);
        endBin = juce::jlimit(0, numBins - 1, endBin);
        
        // Accumulate energy across all bins in this frequency band
        float bandEnergy = 0.0f;
        int binCount = 0;
        
        for (int bin = startBin; bin <= endBin; ++bin)
        {
            float magnitude = magnitudeSpectrum[bin];
            
            // Apply A-weighting for perceptual accuracy if enabled
            if (useAWeighting)
            {
                const float frequency = bin * binWidth;
                magnitude *= getAWeightingCoefficient(frequency);
            }
            
            // Accumulate power (energy = magnitude²) not magnitude
            bandEnergy += magnitude * magnitude;
            binCount++;
        }
        
        // Average energy across bins to prevent bias toward bands with more bins
        // (High frequency bands naturally have more bins due to linear spacing)
        if (binCount > 0)
        {
            bandEnergy /= static_cast<float>(binCount);
        }
        
        // Store linear energy value (for mathematical operations)
        bandEnergiesLinear[band].store(bandEnergy);
        
        // Convert to dB scale and store (for display and perceptual use)
        const float energyDb = linearToDb(bandEnergy);
        bandEnergiesDb[band].store(energyDb);
    }
    
    // Signal that new analysis data is available
    analysisReady.store(true);
}

float BandEnergyAnalyzer::getBandEnergy(int band) const
{
    if (band < 0 || band >= NUM_BANDS)
        return -100.0f;
    
    return bandEnergiesDb[band].load();
}

std::array<float, BandEnergyAnalyzer::NUM_BANDS> BandEnergyAnalyzer::getAllBandEnergies() const
{
    std::array<float, NUM_BANDS> energies;
    for (int i = 0; i < NUM_BANDS; ++i)
    {
        energies[i] = bandEnergiesDb[i].load();
    }
    return energies;
}

float BandEnergyAnalyzer::getBandEnergyLinear(int band) const
{
    if (band < 0 || band >= NUM_BANDS)
        return 0.0f;
    
    return bandEnergiesLinear[band].load();
}

const char* BandEnergyAnalyzer::getBandName(int band)
{
    static const char* bandNames[NUM_BANDS] = {
        "Low",
        "Low-Mid",
        "High-Mid",
        "High"
    };
    
    if (band < 0 || band >= NUM_BANDS)
        return "Unknown";
    
    return bandNames[band];
}

void BandEnergyAnalyzer::getBandFrequencyRange(int band, float& lowFreq, float& highFreq) const
{
    if (band < 0 || band >= NUM_BANDS)
    {
        lowFreq = 0.0f;
        highFreq = 0.0f;
        return;
    }
    
    lowFreq = bandLimits[band];
    highFreq = bandLimits[band + 1];
}

float BandEnergyAnalyzer::getAWeightingCoefficient(float frequency) const
{
    // A-weighting curve approximation
    // Based on ISO 226:2003 standard
    if (frequency <= 0.0f)
        return 0.0f;
    
    const float f2 = frequency * frequency;
    const float f4 = f2 * f2;
    
    // A-weighting formula
    const float num = 12194.217f * 12194.217f * f4;
    const float den = (f2 + 20.6f * 20.6f) * 
                     std::sqrt((f2 + 107.7f * 107.7f) * (f2 + 737.9f * 737.9f)) * 
                     (f2 + 12194.217f * 12194.217f);
    
    return num / den;
}

float BandEnergyAnalyzer::linearToDb(float linear)
{
    // Prevent log of zero or negative
    const float minValue = 1e-10f;
    const float clampedLinear = std::max(linear, minValue);
    
    // Convert to dB (20 * log10 for amplitude, 10 * log10 for power)
    // Using 10 * log10 since we're dealing with power (magnitude squared)
    return 10.0f * std::log10(clampedLinear);
}

} // namespace AIplayer