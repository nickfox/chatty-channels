/*
  ==============================================================================

    TelemetryService.cpp
    Created: 16 Jun 2025
    Author:  Nick Fox

    Implementation of telemetry collection and transmission service.

  ==============================================================================
*/

#include "TelemetryService.h"
#include "../Audio/AudioMetrics.h"
#include "../Audio/FrequencyAnalyzer.h"
#include "OSCManager.h"

namespace AIplayer {

TelemetryService::TelemetryService(AudioMetrics& metrics,
                                   FrequencyAnalyzer& freqAnalyzer,
                                   OSCManager& oscManager,
                                   Logger& logger)
    : audioMetrics(metrics)
    , frequencyAnalyzer(freqAnalyzer)
    , oscManager(oscManager)
    , logger(logger)
{
    logger.log(Logger::Level::Info, "TelemetryService initialized");
}

TelemetryService::~TelemetryService()
{
    stopTelemetry();
    logger.log(Logger::Level::Info, "TelemetryService shutdown");
}

void TelemetryService::setTrackID(const juce::String& trackID)
{
    currentTrackID = trackID;
    logger.log(Logger::Level::Info, "TelemetryService track ID set to: " + trackID);
}

void TelemetryService::setInstanceID(const juce::String& instanceID)
{
    currentInstanceID = instanceID;
    logger.log(Logger::Level::Info, "TelemetryService instance ID set to: " + instanceID);
}

void TelemetryService::startTelemetry(int frequencyHz)
{
    if (isTimerRunning())
    {
        stopTimer();
    }
    
    logger.log(Logger::Level::Info, 
              "Starting telemetry at " + juce::String(frequencyHz) + " Hz");
    
    startTimerHz(frequencyHz);
}

void TelemetryService::stopTelemetry()
{
    if (isTimerRunning())
    {
        stopTimer();
        logger.log(Logger::Level::Info, "Telemetry stopped");
    }
}

void TelemetryService::sendTelemetryNow()
{
    if (!oscManager.isSenderConnected())
    {
        logger.log(Logger::Level::Warning, 
                  "Cannot send telemetry - OSC sender not connected");
        return;
    }
    
    TelemetryData data = collectTelemetryData();
    
    if (!data.isValid())
    {
        logger.log(Logger::Level::Warning, 
                  "Invalid telemetry data - skipping send");
        return;
    }
    
    if (!oscManager.sendTelemetry(data))
    {
        logger.log(Logger::Level::Error, "Failed to send telemetry");
    }
}

void TelemetryService::timerCallback()
{
    try
    {
        sendTelemetryNow();
        
        // Log periodically to avoid spam
        int count = updateCounter.fetch_add(1);
        if (count % LOG_FREQUENCY == 0)
        {
            TelemetryData data = collectTelemetryData();
            logger.log(Logger::Level::Debug, 
                      "Telemetry sent: " + data.toString());
            updateCounter.store(0);
        }
    }
    catch (const std::exception& e)
    {
        logger.log(Logger::Level::Error, 
                  "Exception in telemetry timer: " + juce::String(e.what()));
    }
    catch (...)
    {
        logger.log(Logger::Level::Error, 
                  "Unknown exception in telemetry timer");
    }
}

TelemetryData TelemetryService::collectTelemetryData()
{
    TelemetryData data;
    
    // Fill in identification
    data.trackID = currentTrackID;
    data.instanceID = currentInstanceID;
    
    // Get current audio metrics
    data.rmsLevel = audioMetrics.getCurrentRMS();
    data.peakLevel = audioMetrics.getPeakLevel();
    
    // Get band energies from frequency analyzer
    auto bandEnergies = frequencyAnalyzer.getBandEnergies();
    for (int i = 0; i < 4; ++i)
    {
        data.bandEnergies[i] = bandEnergies[i];
    }
    
    // Timestamp is set automatically in constructor
    
    return data;
}

} // namespace AIplayer
