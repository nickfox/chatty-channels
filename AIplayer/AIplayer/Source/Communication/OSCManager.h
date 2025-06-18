/*
  ==============================================================================

    OSCManager.h
    Created: 16 Jun 2025
    Author:  Nick Fox

    Centralized OSC communication manager for AIplayer plugin.
    Handles all sending and receiving of OSC messages.

  ==============================================================================
*/

#pragma once

#include "../../JuceLibraryCode/JuceHeader.h"
#include "../Core/Logger.h"
#include "../Models/TelemetryData.h"
#include "../Models/TrackInfo.h"

namespace AIplayer {

/**
 * @class OSCManager
 * @brief Manages all OSC communication for the AIplayer plugin
 * 
 * This class centralizes all OSC sending and receiving functionality,
 * providing a clean interface for other components to communicate
 * with ChattyChannels.
 */
class OSCManager : public juce::OSCReceiver::Listener<juce::OSCReceiver::MessageLoopCallback>
{
public:
    /**
     * @class Listener
     * @brief Interface for components that need to respond to OSC messages
     */
    class Listener
    {
    public:
        virtual ~Listener() = default;
        
        /// Called when a track UUID assignment is received
        virtual void handleTrackAssignment(const juce::String& trackID) = 0;
        
        /// Called when a port assignment is received
        virtual void handlePortAssignment(int port, const juce::String& status) = 0;
        
        /// Called when a parameter change request is received
        virtual void handleParameterChange(const juce::String& param, float value) = 0;
        
        /// Called when an RMS query is received
        virtual void handleRMSQuery(const juce::String& queryID) = 0;
        
        /// Called when a tone control command is received
        virtual void handleToneControl(bool start, float frequency = 0.0f, float amplitude = 0.0f) = 0;
        
        /// Called when a chat response is received
        virtual void handleChatResponse(const juce::String& response) = 0;
    };
    
    /**
     * @brief Constructor
     * 
     * @param logger Reference to the logger for debugging
     */
    explicit OSCManager(Logger& logger);
    
    /**
     * @brief Destructor
     */
    ~OSCManager();
    
    /**
     * @brief Connects the OSC sender to the remote host
     * 
     * @param remoteHost The host address (typically "127.0.0.1")
     * @param remotePort The port to connect to (typically 8999)
     * @return true if connection successful
     */
    bool connect(const juce::String& remoteHost, int remotePort);
    
    /**
     * @brief Binds the OSC receiver to a specific port
     * 
     * @param port The port to bind to
     * @return true if binding successful
     */
    bool bindReceiver(int port);
    
    /**
     * @brief Disconnects the OSC receiver
     */
    void disconnectReceiver();
    
    /**
     * @brief Sends telemetry data via OSC
     * 
     * @param data The telemetry data to send
     * @return true if sent successfully
     */
    bool sendTelemetry(const TelemetryData& data);
    
    /**
     * @brief Sends a port request to ChattyChannels
     * 
     * @param instanceID The plugin instance ID
     * @param preferredPort Preferred port (-1 for any)
     * @param responsePort Port for receiving the response
     * @return true if sent successfully
     */
    bool sendPortRequest(const juce::String& instanceID, int preferredPort, int responsePort);
    
    /**
     * @brief Sends port confirmation to ChattyChannels
     * 
     * @param instanceID The plugin instance ID
     * @param port The port that was bound
     * @param status Status string ("bound" or "failed")
     * @return true if sent successfully
     */
    bool sendPortConfirmation(const juce::String& instanceID, int port, const juce::String& status);
    
    /**
     * @brief Sends UUID assignment confirmation
     * 
     * @param instanceID The plugin instance ID
     * @param trackUUID The assigned track UUID
     * @return true if sent successfully
     */
    bool sendUUIDConfirmation(const juce::String& instanceID, const juce::String& trackUUID);
    
    /**
     * @brief Sends RMS response for a query
     * 
     * @param queryID The query ID to respond to
     * @param instanceID The plugin instance ID
     * @param rmsValue The current RMS value
     * @return true if sent successfully
     */
    bool sendRMSResponse(const juce::String& queryID, const juce::String& instanceID, float rmsValue);
    
    /**
     * @brief Sends tone started confirmation
     * 
     * @param instanceID The plugin instance ID
     * @param frequency The tone frequency
     * @return true if sent successfully
     */
    bool sendToneStarted(const juce::String& instanceID, float frequency);
    
    /**
     * @brief Sends tone stopped confirmation
     * 
     * @param instanceID The plugin instance ID
     * @return true if sent successfully
     */
    bool sendToneStopped(const juce::String& instanceID);
    
    /**
     * @brief Sends tone status response
     * 
     * @param instanceID The plugin instance ID
     * @param enabled Whether tone is enabled
     * @param frequency Current frequency
     * @param amplitudeDb Current amplitude in dB
     * @return true if sent successfully
     */
    bool sendToneStatus(const juce::String& instanceID, bool enabled, float frequency, float amplitudeDb);
    
    /**
     * @brief Sends a chat message
     * 
     * @param instanceID The plugin instance ID (or use 1 for now)
     * @param message The chat message to send
     * @return true if sent successfully
     */
    bool sendChatMessage(int instanceID, const juce::String& message);
    
    /**
     * @brief Adds a listener for OSC events
     * 
     * @param listener The listener to add
     */
    void addListener(Listener* listener);
    
    /**
     * @brief Removes a listener
     * 
     * @param listener The listener to remove
     */
    void removeListener(Listener* listener);
    
    /**
     * @brief Checks if the sender is connected
     * 
     * @return true if connected
     */
    bool isSenderConnected() const { return senderConnected; }
    
    /**
     * @brief Gets the current receiver port
     * 
     * @return The port number, or -1 if not bound
     */
    int getReceiverPort() const { return receiverPort; }
    
private:
    /// OSC sender for outgoing messages
    juce::OSCSender sender;
    
    /// OSC receiver for incoming messages
    juce::OSCReceiver receiver;
    
    /// Reference to logger
    Logger& logger;
    
    /// List of listeners
    juce::ListenerList<Listener> listeners;
    
    /// Whether sender is connected
    std::atomic<bool> senderConnected{false};
    
    /// Current receiver port
    std::atomic<int> receiverPort{-1};
    
    /**
     * @brief OSC message received callback
     * 
     * @param message The received OSC message
     */
    void oscMessageReceived(const juce::OSCMessage& message) override;
    
    /**
     * @brief Parses a port assignment message
     */
    void parsePortAssignment(const juce::OSCMessage& message);
    
    /**
     * @brief Parses a track UUID assignment message
     */
    void parseTrackAssignment(const juce::OSCMessage& message);
    
    /**
     * @brief Parses a parameter change message
     */
    void parseParameterChange(const juce::OSCMessage& message);
    
    /**
     * @brief Parses an RMS query message
     */
    void parseRMSQuery(const juce::OSCMessage& message);
    
    /**
     * @brief Parses tone control messages
     */
    void parseToneControl(const juce::OSCMessage& message);
    
    /**
     * @brief Helper to get OSC argument type as string
     */
    static juce::String getOscArgumentTypeString(const juce::OSCArgument& arg);
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(OSCManager)
};

} // namespace AIplayer
