/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin editor.

  ==============================================================================
*/

#include "PluginProcessor.h"
#include "PluginEditor.h"

//==============================================================================
AIplayerAudioProcessorEditor::AIplayerAudioProcessorEditor (AIplayerAudioProcessor& p)
    : AudioProcessorEditor (&p), audioProcessor (p)
{
    // Chat Display
    addAndMakeVisible(chatDisplay);
    chatDisplay.setMultiLine(true);
    chatDisplay.setReadOnly(true);
    chatDisplay.setCaretVisible(false); // No caret needed for display
    chatDisplay.setScrollbarsShown(true);
    chatDisplay.setText("AIplayer Chat\n=============\n", juce::dontSendNotification); // Initial text

    // Message Input
    addAndMakeVisible(messageInput);
    messageInput.setReturnKeyStartsNewLine(false); // Return key should send
    messageInput.addListener(this);

    // Send Button
    addAndMakeVisible(sendButton);
    sendButton.setButtonText("Send");
    sendButton.addListener(this);

    // Gain Slider
    addAndMakeVisible(gainSlider);
    gainSlider.setSliderStyle(juce::Slider::LinearHorizontal); // Or Rotary, etc.
    gainSlider.setTextBoxStyle(juce::Slider::TextBoxRight, false, 80, 20);
    gainSlider.addListener(this); // Add listener

    // Gain Label
    addAndMakeVisible(gainLabel);
    gainLabel.setText("Gain", juce::dontSendNotification);
    gainLabel.attachToComponent(&gainSlider, true); // Attach label to the left of slider

    // Gain Attachment (Links slider to the APVTS parameter)
    gainAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
        audioProcessor.apvts, // The APVTS from the processor
        "GAIN",             // The Parameter ID to attach to
        gainSlider          // The slider UI element
    );

    // Set initial size (make slightly taller for slider)
    setSize (400, 350);
}

AIplayerAudioProcessorEditor::~AIplayerAudioProcessorEditor()
{
    // Remove listeners to avoid dangling pointers if the editor is destroyed before buttons
    sendButton.removeListener(this);
    messageInput.removeListener(this);
    gainSlider.removeListener(this); // Remove slider listener
}

//==============================================================================
void AIplayerAudioProcessorEditor::paint (juce::Graphics& g)
{
    // (Our component is opaque, so we must completely fill the background with a solid colour)
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));

    // No need to draw text here anymore, the TextEditor components handle it.
}

void AIplayerAudioProcessorEditor::resized()
{
    // This is generally where you'll want to lay out the positions of any
    // subcomponents in your editor..

    auto bounds = getLocalBounds().reduced(10); // Add overall margin
    auto topArea = bounds.removeFromTop(50);    // Area for gain slider
    auto bottomArea = bounds.removeFromBottom(40); // Area for input and button
    auto buttonWidth = 80;

    // Position Gain Slider (Label is attached automatically to the left)
    gainSlider.setBounds(topArea.reduced(0, 10)); // Reduce vertically for spacing

    // Position Chat Display (Takes remaining middle space)
    chatDisplay.setBounds(bounds);

    // Position Bottom Controls
    sendButton.setBounds(bottomArea.removeFromRight(buttonWidth).reduced(5)); // Button on the right
    messageInput.setBounds(bottomArea.reduced(5)); // Input field takes remaining bottom area
}

//==============================================================================
// Listener Callbacks
void AIplayerAudioProcessorEditor::buttonClicked (juce::Button* button)
{
    if (button == &sendButton)
    {
        sendMessage();
    }
}

void AIplayerAudioProcessorEditor::textEditorReturnKeyPressed (juce::TextEditor& editor)
{
    if (&editor == &messageInput)
    {
        sendMessage();
    }
} // <-- ADD THIS MISSING BRACE

// Slider Listener Callback (Required, but attachment handles sync)
    void AIplayerAudioProcessorEditor::sliderValueChanged (juce::Slider* slider)
    {
        if (slider == &gainSlider)
        {
            // Value is already updated in the processor via attachment.
            // Can add custom logic here if needed when the user manually moves the slider.
            // audioProcessor.logMessage("Gain slider moved by user."); // Example logging
        }
    }

void AIplayerAudioProcessorEditor::displayReceivedMessage(const juce::String& message)
{
    // Ensure UI updates happen on the message thread
    juce::MessageManager::callAsync([this, message]()
    {
        // We add "AI: " prefix for clarity
        chatDisplay.moveCaretToEnd(); // Ensure text is appended at the end
        chatDisplay.insertTextAtCaret("AI: " + message + "\n");
        chatDisplay.moveCaretToEnd(); // Scroll to bottom after adding text
    });
}

//==============================================================================
// Private Helper Methods
void AIplayerAudioProcessorEditor::sendMessage()
{
    juce::String message = messageInput.getText();
    if (message.isNotEmpty())
    {
        // 1. Append user message to display (for immediate feedback)
        // We add "You: " prefix for clarity
        chatDisplay.moveCaretToEnd(); // Ensure text is appended at the end
        chatDisplay.insertTextAtCaret("You: " + message + "\n");
        chatDisplay.moveCaretToEnd(); // Scroll to bottom after adding text

        // 2. Clear the input field
        messageInput.clear();

        // 3. Send the message to the PluginProcessor
        audioProcessor.sendChatMessage(message);
        // DBG("Message sent to processor: " + message); // Keep DBG for OSC sending in processor
    }
}
