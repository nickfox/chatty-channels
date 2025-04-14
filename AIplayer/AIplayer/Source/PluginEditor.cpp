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

    // Set initial size
    setSize (400, 300);
}

AIplayerAudioProcessorEditor::~AIplayerAudioProcessorEditor()
{
    // Remove listeners to avoid dangling pointers if the editor is destroyed before buttons
    sendButton.removeListener(this);
    messageInput.removeListener(this);
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

    auto bounds = getLocalBounds();
    auto bottomArea = bounds.removeFromBottom(40); // Area for input and button
    auto buttonWidth = 80;

    chatDisplay.setBounds(bounds.reduced(10)); // Chat display takes most space, with margin

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
