/*
  ==============================================================================

    PortManager.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Port assignment protocol manager for AIplayer plugin.
    Handles negotiation with ChattyChannels for OSC port assignment.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"
#include "../Core/Logger.h"
#include "../Core/Constants.h"

namespace AIplayer {

// Forward declaration
class OSCManager;

/**
 * @class PortManager
 * @brief Manages the port assignment protocol with ChattyChannels
 * 
 * This class handles the state machine for requesting and binding
 * to OSC ports, including retry logic and error handling.
 */
class PortManager
{
public:
    /**
     * @enum State
     * @brief Port assignment state machine states
     */
    enum class State
    {
        Unassigned,      ///< No port assigned yet
        Requesting,      ///< Sent request, waiting for response
        Assigned,        ///< Port assigned by ChattyChannels
        Bound,           ///< Successfully bound to assigned port
        Failed           ///< Failed to bind or get assignment
    };
    
    /**
     * @brief Constructor
     * 
     * @param oscManager Reference to OSC manager for communication
     * @param logger Reference to logger for debugging
     */
    PortManager(OSCManager& oscManager, Logger& logger);
    
    /**
     * @brief Destructor
     */
    ~PortManager() = default;
    
    /**
     * @brief Requests a port assignment from ChattyChannels
     * 
     * @param instanceID The plugin instance ID
     * @param ephemeralPort The ephemeral port for receiving response
     * @return true if request was sent successfully
     */
    bool requestPort(const juce::String& instanceID, int ephemeralPort);
    
    /**
     * @brief Handles port assignment response from ChattyChannels
     * 
     * @param port The assigned port number
     * @param status The assignment status ("assigned" or error)
     * @param instanceID The instance ID in the response
     * @return true if this assignment is for us
     */
    bool handlePortAssignment(int port, const juce::String& status, const juce::String& instanceID);
    
    /**
     * @brief Attempts to bind to the assigned port
     * 
     * @param port The port to bind to
     * @return true if binding successful
     */
    bool bindToPort(int port);
    
    /**
     * @brief Checks if a retry is needed and performs it
     * 
     * @return true if retry was attempted
     */
    bool checkAndRetry();
    
    /**
     * @brief Gets the current state
     * 
     * @return Current port manager state
     */
    State getState() const { return currentState; }
    
    /**
     * @brief Gets the assigned port number
     * 
     * @return Port number, or -1 if not assigned
     */
    int getAssignedPort() const { return assignedPort; }
    
    /**
     * @brief Checks if we have a successfully bound port
     * 
     * @return true if state is Bound
     */
    bool isBound() const { return currentState == State::Bound; }
    
    /**
     * @brief Gets a string representation of the current state
     * 
     * @return State as string
     */
    juce::String getStateString() const;
    
    /**
     * @brief Converts a State enum value to string
     * 
     * @param state The state to convert
     * @return State as string
     */
    static juce::String stateToString(State state);
    
    /**
     * @brief Resets the port manager to initial state
     */
    void reset();
    
private:
    /// Reference to OSC manager
    OSCManager& oscManager;
    
    /// Reference to logger
    Logger& logger;
    
    /// Current state
    std::atomic<State> currentState{State::Unassigned};
    
    /// Assigned port number
    std::atomic<int> assignedPort{-1};
    
    /// Number of retry attempts
    std::atomic<int> retryCount{0};
    
    /// Time of last port request
    juce::Time lastRequestTime;
    
    /// Instance ID for current request
    juce::String currentInstanceID;
    
    /// Ephemeral port for responses
    int responsePort{-1};
    
    /// Maximum number of retries
    static constexpr int maxRetries = Constants::PORT_REQUEST_MAX_RETRIES;
    
    /**
     * @brief Verifies that we actually have the port
     * 
     * Works around potential JUCE bugs where connect() returns true
     * even when the port is already in use.
     * 
     * @param port The port to verify
     * @return true if port is actually available
     */
    bool verifyPortBinding(int port);
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PortManager)
};

} // namespace AIplayer
