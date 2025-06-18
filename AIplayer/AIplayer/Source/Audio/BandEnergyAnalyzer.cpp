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

void BandEnergyAnalyzer::analyzeBands(const float* magnitudeSpectrum, 
                                     int numBins, 
                                     float binWidth,
                                     double sampleRate)
{
    if (magnitudeSpectrum == nullptr || numBins <= 0 || binWidth <= 0.0f)
        return;
    
    // Process each band
    for (int band = 0; band < NUM_BANDS; ++band)
    {
        const float lowFreq = bandLimits[band];
        const float highFreq = bandLimits[band + 1];
        
        // Calculate bin indices for this band
        int startBin = static_cast<int>(lowFreq / binWidth);
        int endBin = static_cast<int>(highFreq / binWidth);
        
        // Clamp to valid range
        startBin = juce::jlimit(0, numBins - 1, startBin);
        endBin = juce::jlimit(0, numBins - 1, endBin);
        
        // Sum energy in band
        float bandEnergy = 0.0f;
        int binCount = 0;
        
        for (int bin = startBin; bin <= endBin; ++bin)
        {
            float magnitude = magnitudeSpectrum[bin];
            
            // Apply A-weighting if enabled
            if (useAWeighting)
            {
                const float frequency = bin * binWidth;
                magnitude *= getAWeightingCoefficient(frequency);
            }
            
            // Accumulate energy (magnitude squared)
            bandEnergy += magnitude * magnitude;
            binCount++;
        }
        
        // Average energy across bins (prevents bias toward bands with more bins)
        if (binCount > 0)
        {
            bandEnergy /= static_cast<float>(binCount);
        }
        
        // Store linear energy
        bandEnergiesLinear[band].store(bandEnergy);
        
        // Convert to dB and store
        const float energyDb = linearToDb(bandEnergy);
        bandEnergiesDb[band].store(energyDb);
    }
    
    // Mark analysis as ready
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