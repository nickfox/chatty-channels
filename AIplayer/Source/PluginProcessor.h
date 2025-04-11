// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginProcessor.h
#pragma once
#include <JuceHeader.h>
#include "oscpack/ip/UdpSocket.h"
#include "oscpack/osc/OscOutboundPacketStream.h"

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

    void sendOSC(const juce::String& instrument, const juce::String& action, const juce::String& message);

private:
    UdpTransmitSocket* socket;
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AIplayerAudioProcessor)
};