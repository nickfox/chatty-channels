// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginProcessor.h
#pragma once

/**
 * @file PluginProcessor.h
 * @brief Defines the audio processor for the AIplayer plugin
 *
 * This header defines the AIplayer audio processor which handles the OSC
 * communication between the plugin and the ChattyChannels desktop app.
 * It manages UDP sockets for sending and receiving OSC messages.
 */

#include <JuceHeader.h>
#include "oscpack/ip/UdpSocket.h"
#include "oscpack/osc/OscOutboundPacketStream.h"
#include "oscpack/osc/OscPacketListener.h"
#include "oscpack/osc/OscReceivedElements.h"

class AIplayerAudioProcessorEditor;

/**
 * @brief Main audio processor for the AIplayer plugin
 *
 * This class handles the core functionality of the plugin including OSC communication
 * with the ChattyChannels desktop app. It sets up UDP sockets for bidirectional
 * communication and processes messages between the plugin UI and the desktop app.
 */
class AIplayerAudioProcessor : public juce::AudioProcessor {
public:
    AIplayerAudioProcessor();
    ~AIplayerAudioProcessor() override;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override {}
    void releaseResources() override {}
    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override {}

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }
    const juce::String getName() const override { return "AIplayer"; }
    bool acceptsMidi() const override { return true; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}
    void getStateInformation(juce::MemoryBlock&) override {}
    void setStateInformation(const void*, int) override {}

    /**
     * @brief Sends an OSC message to the ChattyChannels app
     *
     * @param instrument The instrument identifier (e.g., "kick", "guitar")
     * @param action The action to perform (e.g., "gemini")
     * @param message The message content to send
     */
    void sendOSC(const juce::String& instrument, const juce::String& action, const juce::String& message);
    
    /**
     * @brief Updates the chat display in the plugin UI
     *
     * This method is called when a response is received from the ChattyChannels app
     * and needs to be displayed in the plugin's chat interface.
     *
     * @param message The message to display
     */
    void updateChatDisplay(const juce::String& message);

private:
    UdpTransmitSocket* sendSocket;
    std::unique_ptr<UdpListeningReceiveSocket> receiveSocket;
    AIplayerAudioProcessorEditor* editor;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AIplayerAudioProcessor)
};

/**
 * @brief Listens for OSC messages from the ChattyChannels app
 *
 * This class handles incoming OSC messages from the desktop app,
 * particularly chat responses that need to be displayed in the plugin UI.
 */
class OSCListener : public osc::OscPacketListener {
public:
    OSCListener(AIplayerAudioProcessor* p) : processor(p) {}
protected:
    /**
     * @brief Processes received OSC messages
     *
     * This method is called when an OSC message is received from the ChattyChannels app.
     * It checks if the message is a chat response and updates the plugin UI accordingly.
     *
     * @param m The received OSC message
     * @param endpointName The source endpoint of the message
     */
    void ProcessMessage(const osc::ReceivedMessage& m, const IpEndpointName&) override {
        if (m.TypeTag() == "s" && String(m.AddressPattern()).endsWith("/response")) {
            processor->updateChatDisplay(m.ArgumentStream().ReceiveString().c_str());
        }
    }
private:
    AIplayerAudioProcessor* processor;
};