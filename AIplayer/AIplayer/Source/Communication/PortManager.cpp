/*
  ==============================================================================

    PortManager.cpp
    Created: 16 Jun 2025
    Author:  Nick Fox

    Implementation of port assignment protocol manager.

  ==============================================================================
*/

#include "PortManager.h"
#include "OSCManager.h"

namespace AIplayer {

PortManager::PortManager(OSCManager& oscManager, Logger& logger)
    : oscManager(oscManager)
    , logger(logger)
{
    logger.log(Logger::Level::Info, "PortManager initialized");
}

bool PortManager::requestPort(const juce::String& instanceID, int ephemeralPort)
{
    if (currentState == State::Bound)
    {
        logger.log(Logger::Level::Debug, 
                  "Already have bound port " + juce::String(assignedPort) + 
                  ", skipping request");
        return true;
    }
    
    if (currentState == State::Requesting)
    {
        // Check if we should retry
        auto timeSinceLastRequest = juce::Time::getCurrentTime() - lastRequestTime;
        if (timeSinceLastRequest.inMilliseconds() < Constants::PORT_REQUEST_TIMEOUT_MS)
        {
            return false; // Still waiting for response
        }
    }
    
    if (retryCount >= maxRetries)
    {
        logger.log(Logger::Level::Error, 
                  "Max port request retries reached. Unable to get port assignment.");
        currentState = State::Failed;
        return false;
    }
    
    // Store request details
    currentInstanceID = instanceID;
    responsePort = ephemeralPort;
    
    logger.log(Logger::Level::Info, 
              "Requesting port assignment from ChattyChannels (attempt " + 
              juce::String(retryCount + 1) + "/" + juce::String(maxRetries) + ")");
    
    // Send the request
    if (!oscManager.sendPortRequest(instanceID, -1, ephemeralPort))
    {
        logger.log(Logger::Level::Error, "Failed to send port request");
        retryCount++;
        return false;
    }
    
    currentState = State::Requesting;
    lastRequestTime = juce::Time::getCurrentTime();
    retryCount++;
    
    return true;
}

bool PortManager::handlePortAssignment(int port, const juce::String& status, 
                                      const juce::String& instanceID)
{
    // Verify this assignment is for us
    if (instanceID != currentInstanceID)
    {
        logger.log(Logger::Level::Debug, 
                  "Ignoring port assignment for different plugin: " + instanceID);
        return false;
    }
    
    if (status == "assigned" && port > 0)
    {
        assignedPort = port;
        currentState = State::Assigned;
        
        logger.log(Logger::Level::Info, 
                  "Port " + juce::String(port) + " assigned to instance " + instanceID);
        
        // Try to bind immediately
        if (bindToPort(port))
        {
            return true;
        }
        else
        {
            // Binding failed, try requesting a new port
            currentState = State::Failed;
            reset();
            return false;
        }
    }
    else
    {
        logger.log(Logger::Level::Error, 
                  "Port assignment failed with status: " + status);
        currentState = State::Failed;
        return false;
    }
}

bool PortManager::bindToPort(int port)
{
    logger.log(Logger::Level::Info, 
              "Attempting to bind OSC receiver to assigned port " + juce::String(port));
    
    // Try to bind through OSCManager
    if (oscManager.bindReceiver(port))
    {
        // Verify we actually got the port
        if (verifyPortBinding(port))
        {
            assignedPort = port;
            currentState = State::Bound;
            
            logger.log(Logger::Level::Info, 
                      "Successfully bound to port " + juce::String(port));
            
            // Send confirmation to ChattyChannels
            if (!oscManager.sendPortConfirmation(currentInstanceID, port, "bound"))
            {
                logger.log(Logger::Level::Warning, "Failed to send port confirmation");
            }
            
            return true;
        }
        else
        {
            logger.log(Logger::Level::Error, 
                      "Port " + juce::String(port) + " verification failed");
            oscManager.disconnectReceiver();
        }
    }
    else
    {
        logger.log(Logger::Level::Error, 
                  "Failed to bind receiver to port " + juce::String(port));
    }
    
    // Binding failed - notify ChattyChannels
    oscManager.sendPortConfirmation(currentInstanceID, port, "failed");
    
    return false;
}

bool PortManager::checkAndRetry()
{
    if (currentState == State::Requesting || currentState == State::Unassigned)
    {
        auto timeSinceLastRequest = juce::Time::getCurrentTime() - lastRequestTime;
        if (timeSinceLastRequest.inMilliseconds() >= Constants::PORT_REQUEST_TIMEOUT_MS)
        {
            logger.log(Logger::Level::Warning, "Port assignment request timed out, retrying...");
            return requestPort(currentInstanceID, responsePort);
        }
    }
    else if (currentState == State::Failed)
    {
        // Try again after failure
        return requestPort(currentInstanceID, responsePort);
    }
    
    return false;
}

juce::String PortManager::getStateString() const
{
    return stateToString(currentState.load());
}

juce::String PortManager::stateToString(State state)
{
    switch (state)
    {
        case State::Unassigned: return "Unassigned";
        case State::Requesting: return "Requesting";
        case State::Assigned:   return "Assigned";
        case State::Bound:      return "Bound";
        case State::Failed:     return "Failed";
        default:                return "Unknown";
    }
}

void PortManager::reset()
{
    currentState = State::Unassigned;
    assignedPort = -1;
    retryCount = 0;
    currentInstanceID.clear();
    responsePort = -1;
    
    logger.log(Logger::Level::Info, "PortManager reset to initial state");
}

bool PortManager::verifyPortBinding(int port)
{
    // TODO: Implement proper port verification using platform-specific socket APIs
    // For now, trust that the binding succeeded
    // A proper implementation would:
    // 1. Create a test UDP socket
    // 2. Try to bind to the same port
    // 3. If binding fails, we know we have the port
    // 4. If binding succeeds, another process has it
    
    return true;
}

} // namespace AIplayer
