/*
  ==============================================================================

    Logger.cpp
    Created: 16 Jun 2025
    Author:  Nick Fox

    Implementation of the centralized logging system.

  ==============================================================================
*/

#include "Logger.h"
#include "../../JuceLibraryCode/JuceHeader.h"

namespace AIplayer {

Logger::Logger(const juce::File& logFile)
{
    // Ensure the parent directory exists
    logFile.getParentDirectory().createDirectory();
    
    // Try to create/open the log file for appending
    logStream = logFile.createOutputStream();
    
    if (logStream != nullptr)
    {
        // Move to end of file for appending
        logStream->setPosition(logFile.getSize());
        
        // Write startup message
        log(Level::Info, "=== Logger initialized ===");
        log(Level::Info, "Log file: " + logFile.getFullPathName());
    }
    else
    {
        // Fall back to debug output
        DBG("Logger: Failed to open log file: " + logFile.getFullPathName());
    }
}

Logger::~Logger()
{
    if (logStream != nullptr)
    {
        log(Level::Info, "=== Logger shutting down ===");
        logStream->flush();
    }
}

void Logger::log(Level level, const juce::String& message)
{
    // Check if message meets minimum level requirement
    if (static_cast<int>(level) < static_cast<int>(minimumLevel.load()))
    {
        return;
    }
    
    // Format the message with timestamp and level
    juce::String timestamp = juce::Time::getCurrentTime().toString(true, true, true, true);
    juce::String levelStr = getLevelString(level);
    juce::String formattedMessage = timestamp + " | " + levelStr + " | " + message + juce::newLine;
    
    // Thread-safe writing
    const juce::ScopedLock sl(logLock);
    
    if (logStream != nullptr)
    {
        writeToFile(formattedMessage);
    }
    else
    {
        // Fallback to debug output
        DBG(levelStr + " | " + message);
    }
}

void Logger::setMinimumLevel(Level level)
{
    minimumLevel.store(level);
}

juce::String Logger::getLevelString(Level level) const
{
    switch (level)
    {
        case Level::Debug:   return "DEBUG";
        case Level::Info:    return "INFO";
        case Level::Warning: return "WARNING";
        case Level::Error:   return "ERROR";
        default:            return "UNKNOWN";
    }
}

void Logger::writeToFile(const juce::String& message)
{
    // This method assumes logLock is already held
    jassert(logStream != nullptr);
    
    // Write the message
    logStream->writeText(message, false, false, nullptr);
    
    // Flush immediately for debugging purposes
    // In production, you might want to flush less frequently for performance
    logStream->flush();
}

} // namespace AIplayer
