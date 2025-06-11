#pragma once

#include <JuceHeader.h>
#include "PluginProcessor.h"

class SineGenAudioProcessorEditor  : public juce::AudioProcessorEditor
{
public:
    SineGenAudioProcessorEditor (SineGenAudioProcessor&);
    ~SineGenAudioProcessorEditor() override;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    SineGenAudioProcessor& audioProcessor;
    
    juce::ToggleButton onOffButton;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment> onOffAttachment;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (SineGenAudioProcessorEditor)
};
