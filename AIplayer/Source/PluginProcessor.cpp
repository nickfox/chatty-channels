// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginProcessor.cpp
#include "PluginProcessor.h"
#include "PluginEditor.h"

AIplayerAudioProcessor::AIplayerAudioProcessor()
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)) {
    socket = new UdpTransmitSocket(IpEndpointName("localhost", 9000));
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