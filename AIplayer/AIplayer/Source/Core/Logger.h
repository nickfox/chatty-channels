/*
  ==============================================================================

    Logger.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Centralized logging system for AIplayer plugin.
    Thread-safe file logging with fallback to debug output.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"
#include <memory>

namespace AIplayer {

/**
 * @class Logger
 * @brief Thread-safe logging system with file output and severity levels
 * 
 * Provides centralized logging for the AIplayer plugin with:
 * - Multiple severity levels (Debug, Info, Warning, Error)
 * - Thread-safe file writing
 * - Automatic timestamps
 * - Fallback to debug console if file unavailable
 */
class Logger
{
public:
    /**
     * @brief Severity levels for log messages
     */
    enum class Level
    {
        Debug,      ///< Detailed information for debugging
        Info,       ///< General informational messages
        Warning,    ///< Warning messages for potentially problematic situations
        Error       ///< Error messages for failures
    };
    
    /**
     * @brief Constructs a Logger that writes to the specified file
     * 
     * @param logFile The file to write logs to. If the file cannot be opened,
     *                logging will fall back to debug console output.
     */
    explicit Logger(const juce::File& logFile);
    
    /**
     * @brief Destructor - ensures file stream is properly closed
     */
    ~Logger();
    
    /**
     * @brief Logs a message with the specified severity level
     * 
     * Thread-safe method that writes timestamped messages to the log file.
     * If file writing fails, falls back to debug console output.
     * 
     * @param level The severity level of the message
     * @param message The message to log
     */
    void log(Level level, const juce::String& message);
    
    /**
     * @brief Sets the minimum severity level for messages to be logged
     * 
     * Messages below this level will be filtered out.
     * 
     * @param level The minimum level to log
     */
    void setMinimumLevel(Level level);
    
    /**
     * @brief Gets the current minimum logging level
     * 
     * @return The current minimum level
     */
    Level getMinimumLevel() const { return minimumLevel; }
    
    /**
     * @brief Checks if logging is currently active (file is open)
     * 
     * @return true if log file is open and writable
     */
    bool isLogging() const { return logStream != nullptr; }
    
private:
    /**
     * @brief Converts a log level to its string representation
     * 
     * @param level The level to convert
     * @return String representation (e.g., "INFO", "ERROR")
     */
    juce::String getLevelString(Level level) const;
    
    /**
     * @brief Writes a formatted message to the log file
     * 
     * Must be called with logLock held.
     * 
     * @param message The formatted message to write
     */
    void writeToFile(const juce::String& message);
    
    /// File output stream for writing logs
    std::unique_ptr<juce::FileOutputStream> logStream;
    
    /// Critical section for thread-safe access
    mutable juce::CriticalSection logLock;
    
    /// Minimum level for messages to be logged
    std::atomic<Level> minimumLevel{Level::Info};
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Logger)
};

} // namespace AIplayer
