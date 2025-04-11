// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginEditor.h
#pragma once
#include <JuceHeader.h>
#include "PluginProcessor.h"

class AIplayerAudioProcessorEditor : public juce::AudioProcessorEditor {
public:
    AIplayerAudioProcessorEditor(AIplayerAudioProcessor&);
    ~AIplayerAudioProcessorEditor() override;

    void paint(juce::Graphics&) override;
    void resized() override;
    void updateChat(const juce::String& message);

private:
    AIplayerAudioProcessor& processor;
    juce::ComboBox instrumentCombo;
    juce::TextEditor chatInput, chatDisplay;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AIplayerAudioProcessorEditor)
};