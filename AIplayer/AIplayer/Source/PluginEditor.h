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
 * @class AIplayerAudioProcessorEditor
 * @brief GUI editor component for the AIplayer plugin
 *
 * This class implements the user interface for the AIplayer plugin,
 * including chat display, message input, send button, and parameter controls.
 * It communicates with the AIplayerAudioProcessor to handle user interactions
 * and display messages.
 */
class AIplayerAudioProcessorEditor  : public juce::AudioProcessorEditor,
                                      public juce::TextButton::Listener,
                                      public juce::TextEditor::Listener,
                                      private juce::Slider::Listener
{
public:
    /**
     * @brief Constructor for the AIplayerAudioProcessorEditor
     *
     * Sets up the UI components and configures their properties and listeners.
     *
     * @param p Reference to the audio processor that created this editor
     */
    AIplayerAudioProcessorEditor (AIplayerAudioProcessor& p);
    
    /**
     * @brief Destructor for the AIplayerAudioProcessorEditor
     *
     * Cleans up resources used by the editor.
     */
    ~AIplayerAudioProcessorEditor() override;

    //==============================================================================
    /**
     * @brief Renders the editor's UI components
     *
     * This method is called when the editor needs to be redrawn.
     *
     * @param g The graphics context to use for drawing
     */
    void paint (juce::Graphics& g) override;
    
    /**
     * @brief Updates the size and position of UI components
     *
     * This method is called when the editor is resized or when
     * the layout needs to be updated.
     */
    void resized() override;

    /**
     * @brief Displays a received message in the chat display
     *
     * This is called by the processor when a new message is received
     * via OSC to update the chat display.
     *
     * @param message The message to display
     */
    void displayReceivedMessage(const juce::String& message);

private:
    /**
     * @brief Handles button click events
     *
     * This callback is triggered when a button is clicked, such as
     * the send button.
     *
     * @param button Pointer to the button that was clicked
     */
    void buttonClicked (juce::Button* button) override;
    
    /**
     * @brief Handles return key presses in text editors
     *
     * This callback is triggered when the return key is pressed in a text editor,
     * such as the message input field.
     *
     * @param editor Reference to the text editor where the key was pressed
     */
    void textEditorReturnKeyPressed (juce::TextEditor& editor) override;
    
    /**
     * @brief Handles slider value changes
     *
     * This callback is triggered when a slider's value changes,
     * such as the gain slider.
     *
     * @param slider Pointer to the slider that changed
     */
    void sliderValueChanged (juce::Slider* slider) override;
    
    /**
     * @brief Sends the current message text to the processor
     *
     * This helper method sends the message from the input field
     * to the processor and clears the input field.
     */
    void sendMessage();

    /**
     * @brief Reference to the audio processor
     *
     * This reference provides access to the processor that created this editor.
     */
    AIplayerAudioProcessor& audioProcessor;

    /**
     * @brief Text editor for displaying chat messages
     *
     * This component displays sent and received chat messages.
     */
    juce::TextEditor chatDisplay;
    
    /**
     * @brief Text editor for entering messages
     *
     * This component allows the user to enter messages to send.
     */
    juce::TextEditor messageInput;
    
    /**
     * @brief Button for sending messages
     *
     * This button triggers the sendMessage() method when clicked.
     */
    juce::TextButton sendButton;
    
    /**
     * @brief Slider for controlling the gain parameter
     *
     * This slider allows the user to adjust the gain parameter.
     */
    juce::Slider gainSlider;
    
    /**
     * @brief Label for the gain slider
     *
     * This label displays the name of the gain parameter.
     */
    juce::Label gainLabel;
    
    /**
     * @brief Attachment for connecting the gain slider to the gain parameter
     *
     * This attachment connects the gain slider to the gain parameter in the
     * AudioProcessorValueTreeState, handling bidirectional updates automatically.
     */
    std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> gainAttachment;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AIplayerAudioProcessorEditor)
};
