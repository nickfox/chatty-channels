// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginEditor.cpp
#include "PluginEditor.h"

AIplayerAudioProcessorEditor::AIplayerAudioProcessorEditor(AIplayerAudioProcessor& p)
    : AudioProcessorEditor(&p), processor(p) {
    instrumentCombo.addItem("Kick", 1);
    instrumentCombo.addItem("Guitar", 2);
    instrumentCombo.setSelectedId(1);
    addAndMakeVisible(instrumentCombo);
    
    chatInput.setMultiLine(false);
    chatInput.setText("Type here...");
    addAndMakeVisible(chatInput);
    chatInput.onReturnKey = [this] {
        processor.sendOSC(instrumentCombo.getText().toLowerCase(), "gemini", chatInput.getText());
        chatDisplay.setText(chatDisplay.getText() + "\nYou: " + chatInput.getText());
        chatInput.setText("");
    };
    
    chatDisplay.setMultiLine(true);
    chatDisplay.setReadOnly(true);
    addAndMakeVisible(chatDisplay);
    
    setSize(400, 300);
}

AIplayerAudioProcessorEditor::~AIplayerAudioProcessorEditor() {}

void AIplayerAudioProcessorEditor::paint(juce::Graphics& g) {
    g.fillAll(juce::Colours::black);
    g.setColour(juce::Colours::white);
    g.drawText("AIplayer", 0, 0, getWidth(), 20, juce::Justification::centred);
}

void AIplayerAudioProcessorEditor::resized() {
    instrumentCombo.setBounds(10, 30, 150, 20);
    chatInput.setBounds(10, 60, 380, 20);
    chatDisplay.setBounds(10, 90, 380, 200);
}

void AIplayerAudioProcessorEditor::updateChat(const juce::String& message) {
    chatDisplay.setText(chatDisplay.getText() + "\nGemini: " + message);
}