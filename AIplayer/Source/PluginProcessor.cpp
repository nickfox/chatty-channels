// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginProcessor.cpp
#include "../JuceLibraryCode/JuceHeader.h"
#include "PluginProcessor.h"
#include "PluginEditor.h"

AIplayerAudioProcessor::AIplayerAudioProcessor()
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)) {
    socket = new UdpTransmitSocket(IpEndpointName("localhost", 9000));
    startTimerHz(333);
}

AIplayerAudioProcessor::~AIplayerAudioProcessor() {
    delete socket;
}

void AIplayerAudioProcessor::sendOSC(const juce::String& instrument, const juce::String& action, const juce::String& message) {
    char buffer[1024];
    osc::OutboundPacketStream p(buffer, 1024);
    p << osc::BeginMessage(("/" + instrument).toRawUTF8())
      << action.toRawUTF8() << message.toRawUTF8() << osc::EndMessage;
    socket->Send(p.Data(), p.Size());
}

juce::AudioProcessorEditor* AIplayerAudioProcessor::createEditor() {
    return new AIplayerAudioProcessorEditor(*this);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new AIplayerAudioProcessor();
}

const juce::String AIplayerAudioProcessor::getName() const override {
    return "AIplayer";
}

void AIplayerAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock) override {
    // Implementation if needed
}

void AIplayerAudioProcessor::releaseResources() override {
    // Implementation if needed
}

void AIplayerAudioProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages) override {
    // Implementation if needed
}

bool AIplayerAudioProcessor::hasEditor() const override {
    return true;
}

bool AIplayerAudioProcessor::acceptsMidi() const override {
    return true;
}

bool AIplayerAudioProcessor::producesMidi() const override {
    return false;
}

double AIplayerAudioProcessor::getTailLengthSeconds() const override {
    return 0.0;
}

int AIplayerAudioProcessor::getNumPrograms() override {
    return 1;
}

int AIplayerAudioProcessor::getCurrentProgram() override {
    return 0;
}

void AIplayerAudioProcessor::setCurrentProgram(int index) override {
    // Implementation if needed
}

const juce::String AIplayerAudioProcessor::getProgramName(int index) override {
    return {};
}

void AIplayerAudioProcessor::changeProgramName(int index, const juce::String& newName) override {
    // Implementation if needed
}

void AIplayerAudioProcessor::getStateInformation(juce::MemoryBlock& destData) override {
    // Implementation if needed
}

void AIplayerAudioProcessor::setStateInformation(const void* data, int sizeInBytes) override {
    // Implementation if needed
}
void AIplayerAudioProcessor::timerCallback() {
    // Compute and send RMS value; placeholder for RMS calculation.
    float rmsValue = 0.0f; // TODO: implement actual RMS computation if needed.
    juce::String rmsStr(rmsValue);
    sendOSC("RMS", "update", rmsStr);
}