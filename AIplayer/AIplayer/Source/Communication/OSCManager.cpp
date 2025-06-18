/*
  ==============================================================================

    OSCManager.cpp
    Created: 16 Jun 2025
    Author:  Nick Fox

    Implementation of centralized OSC communication manager.

  ==============================================================================
*/

#include "OSCManager.h"
#include "../Core/Constants.h"

namespace AIplayer {

OSCManager::OSCManager(Logger& logger)
    : logger(logger)
{
    // Add ourselves as the receiver listener
    receiver.addListener(this);
    
    logger.log(Logger::Level::Info, "OSCManager initialized");
}

OSCManager::~OSCManager()
{
    // Remove ourselves as listener
    receiver.removeListener(this);
    
    // Disconnect if connected
    disconnectReceiver();
    
    logger.log(Logger::Level::Info, "OSCManager shutdown");
}

bool OSCManager::connect(const juce::String& remoteHost, int remotePort)
{
    int maxRetries = 3;
    
    for (int retry = 0; retry < maxRetries; retry++)
    {
        if (sender.connect(remoteHost, remotePort))
        {
            senderConnected.store(true);
            logger.log(Logger::Level::Info, 
                      "OSC Sender connected to " + remoteHost + ":" + 
                      juce::String(remotePort) + " on attempt " + 
                      juce::String(retry + 1));
            return true;
        }
        
        logger.log(Logger::Level::Warning, 
                  "Failed to connect OSC sender to " + remoteHost + ":" + 
                  juce::String(remotePort) + " on attempt " + 
                  juce::String(retry + 1) + " of " + juce::String(maxRetries));
        
        // Small delay before retrying
        juce::Thread::sleep(Constants::OSC_RECONNECT_DELAY_MS);
    }
    
    logger.log(Logger::Level::Error, 
              "Could not connect OSC sender after " + 
              juce::String(maxRetries) + " attempts");
    senderConnected.store(false);
    return false;
}

bool OSCManager::bindReceiver(int port)
{
    // Disconnect if already connected
    if (receiverPort.load() > 0)
    {
        receiver.disconnect();
        juce::Thread::sleep(50); // Small delay to ensure clean disconnect
    }
    
    // Try to bind to the new port
    if (receiver.connect(port))
    {
        receiverPort.store(port);
        logger.log(Logger::Level::Info, 
                  "OSC Receiver bound to port " + juce::String(port));
        return true;
    }
    
    logger.log(Logger::Level::Error, 
              "Failed to bind OSC receiver to port " + juce::String(port));
    receiverPort.store(-1);
    return false;
}

void OSCManager::disconnectReceiver()
{
    if (receiverPort.load() > 0)
    {
        receiver.disconnect();
        receiverPort.store(-1);
        logger.log(Logger::Level::Info, "OSC Receiver disconnected");
    }
}

bool OSCManager::sendTelemetry(const TelemetryData& data)
{
    if (!senderConnected.load())
    {
        logger.log(Logger::Level::Warning, "Cannot send telemetry - sender not connected");
        return false;
    }
    
    // Use new telemetry format that includes band energies
    juce::OSCMessage message(Constants::OSCAddresses::TELEMETRY);
    message.addString(data.trackID.isEmpty() ? data.instanceID : data.trackID);
    message.addFloat32(data.rmsLevel);
    message.addFloat32(data.bandEnergies[0]); // Low
    message.addFloat32(data.bandEnergies[1]); // Low-Mid
    message.addFloat32(data.bandEnergies[2]); // High-Mid
    message.addFloat32(data.bandEnergies[3]); // High
    
    if (!sender.send(message))
    {
        senderConnected.store(false);
        logger.log(Logger::Level::Error, "Failed to send telemetry");
        return false;
    }
    
    // Also send legacy RMS-only message for backward compatibility
    if (!data.trackID.isEmpty())
    {
        juce::OSCMessage legacyMessage(Constants::OSCAddresses::RMS_TELEMETRY);
        legacyMessage.addString(data.trackID);
        legacyMessage.addFloat32(data.rmsLevel);
        sender.send(legacyMessage); // Don't check return value for legacy
    }
    
    return true;
}

bool OSCManager::sendPortRequest(const juce::String& instanceID, int preferredPort, int responsePort)
{
    if (!senderConnected.load())
    {
        logger.log(Logger::Level::Warning, "Cannot send port request - sender not connected");
        return false;
    }
    
    juce::OSCMessage message(Constants::OSCAddresses::REQUEST_PORT);
    message.addString(instanceID);
    message.addInt32(preferredPort);
    message.addInt32(responsePort);
    
    if (!sender.send(message))
    {
        senderConnected.store(false);
        logger.log(Logger::Level::Error, "Failed to send port request");
        return false;
    }
    
    logger.log(Logger::Level::Info, 
              "Sent port request: tempID=" + instanceID + 
              ", preferred=" + juce::String(preferredPort) + 
              ", responsePort=" + juce::String(responsePort));
    return true;
}

bool OSCManager::sendPortConfirmation(const juce::String& instanceID, int port, const juce::String& status)
{
    if (!senderConnected.load())
        return false;
    
    juce::OSCMessage message(Constants::OSCAddresses::PORT_CONFIRMED);
    message.addString(instanceID);
    message.addInt32(port);
    message.addString(status);
    
    return sender.send(message);
}

bool OSCManager::sendUUIDConfirmation(const juce::String& instanceID, const juce::String& trackUUID)
{
    if (!senderConnected.load())
        return false;
    
    juce::OSCMessage message(Constants::OSCAddresses::UUID_CONFIRMED);
    message.addString(instanceID);
    message.addString(trackUUID);
    message.addString("confirmed");
    
    return sender.send(message);
}

bool OSCManager::sendRMSResponse(const juce::String& queryID, const juce::String& instanceID, float rmsValue)
{
    if (!senderConnected.load())
        return false;
    
    juce::OSCMessage message(Constants::OSCAddresses::RMS_RESPONSE);
    message.addString(queryID);
    message.addString(instanceID);
    message.addFloat32(rmsValue);
    
    return sender.send(message);
}

bool OSCManager::sendToneStarted(const juce::String& instanceID, float frequency)
{
    if (!senderConnected.load())
        return false;
    
    juce::OSCMessage message(Constants::OSCAddresses::TONE_STARTED);
    message.addString(instanceID);
    message.addFloat32(frequency);
    
    return sender.send(message);
}

bool OSCManager::sendToneStopped(const juce::String& instanceID)
{
    if (!senderConnected.load())
        return false;
    
    juce::OSCMessage message(Constants::OSCAddresses::TONE_STOPPED);
    message.addString(instanceID);
    
    return sender.send(message);
}

bool OSCManager::sendToneStatus(const juce::String& instanceID, bool enabled, float frequency, float amplitudeDb)
{
    if (!senderConnected.load())
        return false;
    
    juce::OSCMessage message(Constants::OSCAddresses::TONE_STATUS_RESPONSE);
    message.addString(instanceID);
    message.addInt32(enabled ? 1 : 0);
    message.addFloat32(frequency);
    message.addFloat32(amplitudeDb);
    
    return sender.send(message);
}

bool OSCManager::sendChatMessage(int instanceID, const juce::String& message)
{
    if (!senderConnected.load())
        return false;
    
    juce::OSCMessage oscMessage(Constants::OSCAddresses::CHAT_REQUEST);
    oscMessage.addInt32(instanceID);
    oscMessage.addString(message);
    
    return sender.send(oscMessage);
}

void OSCManager::addListener(Listener* listener)
{
    listeners.add(listener);
}

void OSCManager::removeListener(Listener* listener)
{
    listeners.remove(listener);
}

void OSCManager::oscMessageReceived(const juce::OSCMessage& message)
{
    try
    {
        const auto addressPattern = message.getAddressPattern().toString();
        
        // Only log important messages, not routine RMS traffic
        if (!addressPattern.contains("rms") && !addressPattern.contains("query_rms"))
        {
            logger.log(Logger::Level::Info, 
                      "Received OSC message: " + addressPattern + 
                      " with " + juce::String(message.size()) + " arguments");
        }
        
        // Route to appropriate parser
        if (addressPattern == Constants::OSCAddresses::PORT_ASSIGNMENT)
        {
            parsePortAssignment(message);
        }
        else if (addressPattern == Constants::OSCAddresses::TRACK_UUID_ASSIGNMENT)
        {
            parseTrackAssignment(message);
        }
        else if (addressPattern == Constants::OSCAddresses::SET_PARAMETER)
        {
            parseParameterChange(message);
        }
        else if (addressPattern == Constants::OSCAddresses::QUERY_RMS)
        {
            parseRMSQuery(message);
        }
        else if (addressPattern == Constants::OSCAddresses::START_TONE ||
                 addressPattern == Constants::OSCAddresses::STOP_TONE ||
                 addressPattern == Constants::OSCAddresses::TONE_STATUS)
        {
            parseToneControl(message);
        }
        else if (addressPattern == Constants::OSCAddresses::CHAT_RESPONSE)
        {
            if (message.size() == 1 && message[0].isString())
            {
                listeners.call(&Listener::handleChatResponse, message[0].getString());
            }
        }
        else
        {
            logger.log(Logger::Level::Warning, 
                      "Received unhandled OSC message: " + addressPattern);
        }
    }
    catch (const std::exception& e)
    {
        logger.log(Logger::Level::Error, 
                  "Exception in oscMessageReceived: " + juce::String(e.what()));
    }
}

void OSCManager::parsePortAssignment(const juce::OSCMessage& message)
{
    if (message.size() == 3 && 
        message[0].isString() && 
        message[1].isInt32() && 
        message[2].isString())
    {
        const auto tempID = message[0].getString();
        const auto port = message[1].getInt32();
        const auto status = message[2].getString();
        
        logger.log(Logger::Level::Info, 
                  "Received port assignment: tempID=" + tempID + 
                  ", port=" + juce::String(port) + 
                  ", status=" + status);
        
        // Note: We don't pass tempID to the listener - the processor will check it
        listeners.call(&Listener::handlePortAssignment, port, status);
    }
    else
    {
        logger.log(Logger::Level::Warning, 
                  "Invalid port assignment message format");
    }
}

void OSCManager::parseTrackAssignment(const juce::OSCMessage& message)
{
    // ChattyChannels sends various formats - handle them all
    if (message.size() >= 2)
    {
        // Try to extract the track UUID from different positions
        for (int i = 0; i < message.size(); ++i)
        {
            if (message[i].isString())
            {
                const auto str = message[i].getString();
                // Check if this looks like a track ID (TR1, TR2, etc.)
                if (str.startsWith("TR"))
                {
                    listeners.call(&Listener::handleTrackAssignment, str);
                    return;
                }
            }
        }
    }
    
    logger.log(Logger::Level::Warning, 
              "Could not parse track UUID from assignment message");
}

void OSCManager::parseParameterChange(const juce::OSCMessage& message)
{
    if (message.size() == 2 && 
        message[0].isString() && 
        message[1].isFloat32())
    {
        const auto paramID = message[0].getString();
        const auto value = message[1].getFloat32();
        
        listeners.call(&Listener::handleParameterChange, paramID, value);
    }
}

void OSCManager::parseRMSQuery(const juce::OSCMessage& message)
{
    if (message.size() == 1 && message[0].isString())
    {
        const auto queryID = message[0].getString();
        listeners.call(&Listener::handleRMSQuery, queryID);
    }
}

void OSCManager::parseToneControl(const juce::OSCMessage& message)
{
    const auto addressPattern = message.getAddressPattern().toString();
    
    if (addressPattern == Constants::OSCAddresses::START_TONE)
    {
        if (message.size() == 2 && 
            message[0].isFloat32() && 
            message[1].isFloat32())
        {
            const auto frequency = message[0].getFloat32();
            const auto amplitude = message[1].getFloat32();
            listeners.call(&Listener::handleToneControl, true, frequency, amplitude);
        }
    }
    else if (addressPattern == Constants::OSCAddresses::STOP_TONE)
    {
        listeners.call(&Listener::handleToneControl, false, 0.0f, 0.0f);
    }
}

juce::String OSCManager::getOscArgumentTypeString(const juce::OSCArgument& arg)
{
    if (arg.isInt32()) return "i";
    if (arg.isFloat32()) return "f";
    if (arg.isString()) return "s";
    if (arg.isBlob()) return "b";
    return "?";
}

} // namespace AIplayer
