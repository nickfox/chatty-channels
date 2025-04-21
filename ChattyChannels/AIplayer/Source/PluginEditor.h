// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginEditor.h
#pragma once

/**
 * @file PluginEditor.h
 * @brief Defines the editor component for the AIplayer plugin
 *
 * This header defines the GUI component that allows users to interact with
 * the AIplayer plugin through a chat interface connected to the ChattyChannels app.
 */

#include <JuceHeader.h>
#include "PluginProcessor.h"

/**
 * @brief The GUI component for the AIplayer plugin
 *
 * This class provides a user interface for the plugin, including:
 * - An instrument selector dropdown
 * - A text input field for sending messages
 * - A chat display area for showing the conversation
 *
 * It communicates with the ChattyChannels app through the processor's OSC interface.
 */
class AIplayerAudioProcessorEditor : public juce::AudioProcessorEditor {
public:
    AIplayerAudioProcessorEditor(AIplayerAudioProcessor&);
    ~AIplayerAudioProcessorEditor() override;

    /**
     * @brief Paints the editor component
     *
     * @param g The graphics context to use for drawing
     */
    void paint(juce::Graphics& g) override;
    
    /**
     * @brief Called when the component is resized
     *
     * Positions the UI elements within the component bounds.
     */
    void resized() override;
    
    /**
     * @brief Updates the chat display with a new message
     *
     * Called by the processor when a new message is received from ChattyChannels.
     *
     * @param message The message to display
     */
    void updateChat(const juce::String& message);

private:
    AIplayerAudioProcessor& processor;
    juce::ComboBox instrumentCombo;
    juce::TextEditor chatInput, chatDisplay;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AIplayerAudioProcessorEditor)
};