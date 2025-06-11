#include "PluginProcessor.h"
#include "PluginEditor.h"

SineGenAudioProcessorEditor::SineGenAudioProcessorEditor (SineGenAudioProcessor& p)
    : AudioProcessorEditor (&p), audioProcessor (p)
{
    addAndMakeVisible(onOffButton);
    onOffButton.setButtonText("Generate Sine Wave");
    onOffButton.setClickingTogglesState(true);
    
    onOffAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ButtonAttachment>(
        audioProcessor.apvts, "onoff", onOffButton);
    
    setSize (300, 150);
}

SineGenAudioProcessorEditor::~SineGenAudioProcessorEditor()
{
}

void SineGenAudioProcessorEditor::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
    
    g.setColour (juce::Colours::white);
    g.setFont (15.0f);
    g.drawFittedText ("137Hz Sine Generator", getLocalBounds().removeFromTop(30), 
                      juce::Justification::centred, 1);
}

void SineGenAudioProcessorEditor::resized()
{
    auto area = getLocalBounds();
    area.removeFromTop(40);
    onOffButton.setBounds(area.reduced(50, 30));
}
