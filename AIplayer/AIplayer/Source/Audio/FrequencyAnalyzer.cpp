/*
  ==============================================================================

    FrequencyAnalyzer.cpp
    Created: 18 Jun 2025
    Author:  Nick Fox

    Implementation of frequency analysis coordinator.

  ==============================================================================
*/

#include "FrequencyAnalyzer.h"

namespace AIplayer {

FrequencyAnalyzer::FrequencyAnalyzer(Logger& log, const Config& cfg)
    : logger(log)
    , config(cfg)
{
    // Create FFT processor
    fftProcessor = std::make_unique<FFTProcessor>(config.fftOrder);
    
    // Create band analyzer
    bandAnalyzer = std::make_unique<BandEnergyAnalyzer>(config.customBandLimits);
    bandAnalyzer->setAWeighting(config.enableAWeighting);
    
    logger.log(Logger::Level::Info, 
              "FrequencyAnalyzer initialized with FFT order " + juce::String(config.fftOrder) +
              " (size: " + juce::String(fftProcessor->getFFTSize()) + ")");
    
    // Start analysis if configured
    if (config.autoStart)
    {
        startAnalysis();
    }
}

FrequencyAnalyzer::~FrequencyAnalyzer()
{
    stopAnalysis();
    logger.log(Logger::Level::Info, "FrequencyAnalyzer shutdown");
}

void FrequencyAnalyzer::processBlock(const juce::AudioBuffer<float>& buffer, double sampleRate)
{
    // Feed audio to FFT processor
    fftProcessor->processAudioBlock(buffer, sampleRate);
    
    // Mark that we should compute on next timer callback
    shouldCompute.store(true);
}

void FrequencyAnalyzer::startAnalysis()
{
    if (!isTimerRunning())
    {
        logger.log(Logger::Level::Info, 
                  "Starting frequency analysis at " + juce::String(config.updateRateHz) + " Hz");
        startTimerHz(config.updateRateHz);
    }
}

void FrequencyAnalyzer::stopAnalysis()
{
    if (isTimerRunning())
    {
        stopTimer();
        logger.log(Logger::Level::Info, "Frequency analysis stopped");
    }
}

std::array<float, 4> FrequencyAnalyzer::getBandEnergies() const
{
    const juce::ScopedLock sl(analysisLock);
    return bandAnalyzer->getAllBandEnergies();
}

float FrequencyAnalyzer::getBandEnergy(int band) const
{
    const juce::ScopedLock sl(analysisLock);
    return bandAnalyzer->getBandEnergy(band);
}

bool FrequencyAnalyzer::computeNow()
{
    if (!shouldCompute.load())
        return false;
    
    auto startTime = juce::Time::getMillisecondCounterHiRes();
    
    // Compute FFT
    if (!fftProcessor->computeFFT())
    {
        return false;
    }
    
    // Analyze bands
    {
        const juce::ScopedLock sl(analysisLock);
        
        bandAnalyzer->analyzeBands(
            fftProcessor->getMagnitudeSpectrum(),
            fftProcessor->getMagnitudeSpectrumSize(),
            fftProcessor->getBinWidth(),
            44100.0 // This will be updated with actual sample rate
        );
    }
    
    // Update performance metrics
    auto endTime = juce::Time::getMillisecondCounterHiRes();
    float computeTime = static_cast<float>(endTime - startTime);
    
    // Update running average
    computeCount++;
    totalComputeTime += computeTime;
    averageComputeTime.store(static_cast<float>(totalComputeTime / computeCount));
    
    // Reset flags
    shouldCompute.store(false);
    fftProcessor->resetFFTReady();
    bandAnalyzer->resetAnalysisReady();
    
    // Log performance periodically
    if (computeCount % 100 == 0)
    {
        logger.log(Logger::Level::Debug,
                  "FFT average compute time: " + juce::String(averageComputeTime.load(), 2) + " ms");
    }
    
    return true;
}

void FrequencyAnalyzer::timerCallback()
{
    // Lazy computation - only compute if new data is available
    if (shouldCompute.load())
    {
        computeNow();
        
        // Increment counter for diagnostics
        computeCounter++;
        
        // Log band energies periodically for debugging
        if (computeCounter % 10 == 0)
        {
            auto energies = getBandEnergies();
            logger.log(Logger::Level::Debug,
                      juce::String::formatted("Band Energies: Low=%.1f dB, LowMid=%.1f dB, "
                                            "HighMid=%.1f dB, High=%.1f dB",
                                            energies[0], energies[1], energies[2], energies[3]));
        }
    }
}

void FrequencyAnalyzer::setAWeighting(bool enable)
{
    bandAnalyzer->setAWeighting(enable);
    config.enableAWeighting = enable;
    logger.log(Logger::Level::Info, 
              juce::String("A-weighting ") + (enable ? "enabled" : "disabled"));
}

void FrequencyAnalyzer::setUpdateRate(int hz)
{
    hz = juce::jlimit(1, 100, hz);
    config.updateRateHz = hz;
    
    if (isTimerRunning())
    {
        stopTimer();
        startTimerHz(hz);
        logger.log(Logger::Level::Info, 
                  "Update rate changed to " + juce::String(hz) + " Hz");
    }
}

} // namespace AIplayer