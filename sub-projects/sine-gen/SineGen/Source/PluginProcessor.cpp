#include "PluginProcessor.h"
#include "PluginEditor.h"

SineGenAudioProcessor::SineGenAudioProcessor()
    : AudioProcessor(BusesProperties()
                     .withInput("Input", juce::AudioChannelSet::stereo(), true)
                     .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      apvts(*this, nullptr, "Parameters", createParameterLayout())
{
    oscillator.setFrequency(137.0f);
    oscillator.initialise([](float x) { return std::sin(x); });
    
    onOffParameter = apvts.getRawParameterValue("onoff");
}

SineGenAudioProcessor::~SineGenAudioProcessor() {}

void SineGenAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    juce::dsp::ProcessSpec spec;
    spec.sampleRate = sampleRate;
    spec.maximumBlockSize = samplesPerBlock;
    spec.numChannels = getTotalNumOutputChannels();
    oscillator.prepare(spec);
}

void SineGenAudioProcessor::releaseResources() {}

void SineGenAudioProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    juce::ScopedNoDenormals noDenormals;

    if (*onOffParameter > 0.5f)
    {
        // Clear the buffer and generate only the sine wave
        buffer.clear();
        
        juce::dsp::AudioBlock<float> block(buffer);
        juce::dsp::ProcessContextReplacing<float> context(block);
        oscillator.process(context);
        
        // Apply gain to reduce volume
        buffer.applyGain(0.5f);
    }
    else
    {
        // When off, pass through the input signal unchanged
        // (buffer already contains input, so nothing to do)
    }
}

// Required plugin methods
const juce::String SineGenAudioProcessor::getName() const { return "SineGen"; }
bool SineGenAudioProcessor::acceptsMidi() const { return false; }
bool SineGenAudioProcessor::producesMidi() const { return false; }
bool SineGenAudioProcessor::isMidiEffect() const { return false; }
double SineGenAudioProcessor::getTailLengthSeconds() const { return 0.0; }
int SineGenAudioProcessor::getNumPrograms() { return 1; }
int SineGenAudioProcessor::getCurrentProgram() { return 0; }
void SineGenAudioProcessor::setCurrentProgram(int) {}
const juce::String SineGenAudioProcessor::getProgramName(int) { return {}; }
void SineGenAudioProcessor::changeProgramName(int, const juce::String&) {}
void SineGenAudioProcessor::getStateInformation(juce::MemoryBlock& destData) 
{
    auto state = apvts.copyState();
    std::unique_ptr<juce::XmlElement> xml(state.createXml());
    copyXmlToBinary(*xml, destData);
}

void SineGenAudioProcessor::setStateInformation(const void* data, int sizeInBytes) 
{
    std::unique_ptr<juce::XmlElement> xmlState(getXmlFromBinary(data, sizeInBytes));
    if (xmlState.get() != nullptr)
        if (xmlState->hasTagName(apvts.state.getType()))
            apvts.replaceState(juce::ValueTree::fromXml(*xmlState));
}

juce::AudioProcessorEditor* SineGenAudioProcessor::createEditor() 
{ 
    return new SineGenAudioProcessorEditor(*this); 
}

bool SineGenAudioProcessor::hasEditor() const { return true; }

juce::AudioProcessorValueTreeState::ParameterLayout SineGenAudioProcessor::createParameterLayout()
{
    juce::AudioProcessorValueTreeState::ParameterLayout layout;
    
    layout.add(std::make_unique<juce::AudioParameterBool>("onoff", "On/Off", false));
    
    return layout;
}

// Factory function for standalone plugin
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new SineGenAudioProcessor();
}
