// /Users/nickfox137/Documents/chatty-channel/AIplayer/Source/PluginEditor.cpp

/**
 * @file PluginEditor.cpp
 * @brief Implementation of the AIplayer plugin editor
 *
 * This file implements the GUI component for the AIplayer plugin,
 * providing a chat interface that communicates with the ChattyChannels app.
 */

#include "PluginEditor.h"

/**
 * @brief Constructs the editor component
 *
 * Sets up the UI components including the instrument dropdown,
 * chat input field, and chat display area. Also configures the
 * event handlers for user interactions.
 *
 * @param p Reference to the audio processor
 */
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

/**
 * @brief Destructor for the editor component
 */
AIplayerAudioProcessorEditor::~AIplayerAudioProcessorEditor() {}

/**
 * @brief Paints the editor component
 *
 * Fills the background and draws the plugin title.
 *
 * @param g The graphics context to use for drawing
 */
void AIplayerAudioProcessorEditor::paint(juce::Graphics& g) {
    g.fillAll(juce::Colours::black);
    g.setColour(juce::Colours::white);
    g.drawText("AIplayer", 0, 0, getWidth(), 20, juce::Justification::centred);
}

/**
 * @brief Positions UI components when the editor is resized
 *
 * Arranges the instrument dropdown, chat input, and chat display
 * within the editor bounds.
 */
void AIplayerAudioProcessorEditor::resized() {
    instrumentCombo.setBounds(10, 30, 150, 20);
    chatInput.setBounds(10, 60, 380, 20);
    chatDisplay.setBounds(10, 90, 380, 200);
}

/**
 * @brief Updates the chat display with a new message
 *
 * Appends the received message to the chat display area with
 * a "Gemini:" prefix to indicate it's from the AI.
 *
 * @param message The message to display
 */
void AIplayerAudioProcessorEditor::updateChat(const juce::String& message) {
    chatDisplay.setText(chatDisplay.getText() + "\nGemini: " + message);
}