/*
  ==============================================================================

    TrackInfo.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Data structure for track identification and metadata.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"

namespace AIplayer {

/**
 * @struct TrackInfo
 * @brief Contains track identification and configuration data
 * 
 * This structure holds all information related to a specific
 * Logic Pro track instance and its AIplayer plugin.
 */
struct TrackInfo
{
    /// Temporary instance ID (UUID) before official Logic UUID is assigned
    juce::String tempInstanceID;
    
    /// Official Logic Pro Track UUID (e.g., "TR1", "TR2", "TR3")
    juce::String logicTrackUUID;
    
    /// OSC receiver port number assigned to this instance
    int oscPort{-1};
    
    /// Whether this track has been successfully identified
    bool isIdentified{false};
    
    /**
     * @brief Default constructor
     */
    TrackInfo() = default;
    
    /**
     * @brief Constructor with instance ID
     * 
     * @param instanceID The temporary instance ID
     */
    explicit TrackInfo(const juce::String& instanceID)
        : tempInstanceID(instanceID)
    {
    }
    
    /**
     * @brief Checks if the track info is valid
     * 
     * @return true if the track has been properly initialized
     */
    bool isValid() const
    {
        return !tempInstanceID.isEmpty() && oscPort > 0;
    }
    
    /**
     * @brief Checks if the track has been assigned a Logic UUID
     * 
     * @return true if Logic track UUID has been assigned
     */
    bool hasLogicUUID() const
    {
        return !logicTrackUUID.isEmpty();
    }
    
    /**
     * @brief Gets the display name for this track
     * 
     * @return Logic UUID if available, otherwise temp instance ID
     */
    juce::String getDisplayName() const
    {
        return hasLogicUUID() ? logicTrackUUID : tempInstanceID;
    }
    
    /**
     * @brief Converts the track info to a string for logging
     * 
     * @return String representation of the track info
     */
    juce::String toString() const
    {
        return juce::String::formatted("TrackInfo[temp=%s, logic=%s, port=%d, identified=%s]",
                                      tempInstanceID.toRawUTF8(),
                                      logicTrackUUID.isEmpty() ? "none" : logicTrackUUID.toRawUTF8(),
                                      oscPort,
                                      isIdentified ? "yes" : "no");
    }
};

} // namespace AIplayer
