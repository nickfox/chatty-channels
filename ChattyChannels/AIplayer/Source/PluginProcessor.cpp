// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginProcessor.cpp
#include "PluginProcessor.h"
#include "PluginEditor.h"

AIplayerAudioProcessor::AIplayerAudioProcessor()
    : AudioProcessor(BusesProperties().withOutput("Output", juce::AudioChannelSet::stereo(), true)) {
    sendSocket = new UdpTransmitSocket(IpEndpointName("localhost", 9000));
    receiveSocket = std::make_unique<UdpListeningReceiveSocket>(
        IpEndpointName(IpEndpointName::ANY_ADDRESS, 9001),
        new OSCListener(this)
    );
    std::thread([this] { receiveSocket->Run(); }).detach();
}

AIplayerAudioProcessor::~AIplayerAudioProcessor() {
    receiveSocket->Break();
    delete sendSocket;
}

void AIplayerAudioProcessor::sendOSC(const juce::String& instrument, const juce::String& action, const juce::String& message) {
    char buffer[1024];
    osc::OutboundPacketStream p(buffer, 1024);
    p << osc::BeginMessage(("/" + instrument).toRawUTF8())
      << action.toRawUTF8() << message.toRawUTF8() << osc::EndMessage;
    sendSocket->Send(p.Data(), p.Size());
}

void AIplayerAudioProcessor::updateChatDisplay(const juce::String& message) {
    if (editor) {
        editor->updateChat(message);
    }
}

juce::AudioProcessorEditor* AIplayerAudioProcessor::createEditor() {
    editor = new AIplayerAudioProcessorEditor(*this);
    return editor;
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new AIplayerAudioProcessor();
}