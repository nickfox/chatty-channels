// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginProcessor.cpp

/**
 * @file PluginProcessor.cpp
 * @brief Implementation of the AIplayer audio processor
 *
 * This file implements the core functionality of the AIplayer plugin,
 * including OSC communication with the ChattyChannels desktop app.
 */

#include "PluginProcessor.h"
#include "PluginEditor.h"

/**
 * @brief Constructs the AIplayer audio processor
 *
 * Sets up the audio processor with stereo output and initializes the OSC communication
 * by creating UDP sockets for sending and receiving messages. Also starts a background
 * thread for receiving OSC messages.
 */
AIplayerAudioProcessor::AIplayerAudioProcessor()
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)) {
    sendSocket = new UdpTransmitSocket(IpEndpointName("localhost", 9000));
    receiveSocket = std::make_unique<UdpListeningReceiveSocket>(
        IpEndpointName(IpEndpointName::ANY_ADDRESS, 9001),
        new OSCListener(this)
    );
    std::thread([this] { receiveSocket->Run(); }).detach();
}

/**
 * @brief Destructor for the AIplayer audio processor
 *
 * Cleans up resources by stopping the OSC receiver thread and deleting the send socket.
 */
AIplayerAudioProcessor::~AIplayerAudioProcessor() {
    receiveSocket->Break();
    delete sendSocket;
}

/**
 * @brief Sends an OSC message to the ChattyChannels desktop app
 *
 * Formats an OSC message with the specified instrument, action, and content,
 * then sends it to the desktop app via UDP.
 *
 * @param instrument The instrument identifier (e.g., "kick", "guitar")
 * @param action The action to perform (e.g., "gemini")
 * @param message The message content to send
 */
void AIplayerAudioProcessor::sendOSC(const juce::String& instrument, const juce::String& action, const juce::String& message) {
    char buffer[1024];
    osc::OutboundPacketStream p(buffer, 1024);
    p << osc::BeginMessage(("/" + instrument).toRawUTF8())
      << action.toRawUTF8() << message.toRawUTF8() << osc::EndMessage;
    sendSocket->Send(p.Data(), p.Size());
}

/**
 * @brief Updates the chat display in the plugin UI
 *
 * Called when a response is received from the ChattyChannels app.
 * This method forwards the message to the editor for display in the UI.
 *
 * @param message The message to display
 */
void AIplayerAudioProcessor::updateChatDisplay(const juce::String& message) {
    if (editor) {
        editor->updateChat(message);
    }
}

/**
 * @brief Creates the plugin editor
 *
 * @return A pointer to the newly created editor
 */
juce::AudioProcessorEditor* AIplayerAudioProcessor::createEditor() {
    editor = new AIplayerAudioProcessorEditor(*this);
    return editor;
}

/**
 * @brief Factory function to create the plugin
 *
 * This function is called by the host to create an instance of the plugin.
 *
 * @return A pointer to the newly created plugin instance
 */
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new AIplayerAudioProcessor();
}