/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin editor.

  ==============================================================================
*/

#pragma once

#include <JuceHeader.h>
#include "PluginProcessor.h"

//==============================================================================
/**
*/
class AIplayerAudioProcessorEditor  : public juce::AudioProcessorEditor,
                                      public juce::TextButton::Listener, // Inherit from TextButton Listener
                                      public juce::TextEditor::Listener  // Inherit from TextEditor Listener
{
public:
    AIplayerAudioProcessorEditor (AIplayerAudioProcessor&);
    ~AIplayerAudioProcessorEditor() override;

    //==============================================================================
    void paint (juce::Graphics&) override;
    void resized() override;

    // Public method for Processor to update display
    void displayReceivedMessage(const juce::String& message);

private:
    // Listener Callbacks
    void buttonClicked (juce::Button* button) override;
    void textEditorReturnKeyPressed (juce::TextEditor& editor) override;
    // Private Helper Methods
    void sendMessage();

    // This reference is provided as a quick way for your editor to
    // access the processor object that created it.
    AIplayerAudioProcessor& audioProcessor;

    // UI Elements
    juce::TextEditor chatDisplay;
    juce::TextEditor messageInput;
    juce::TextButton sendButton;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AIplayerAudioProcessorEditor)
};
