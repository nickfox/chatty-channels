/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin processor.

  ==============================================================================
*/

#pragma once

#include <JuceHeader.h>
#include <juce_osc/juce_osc.h> // Include the JUCE OSC module header
#include <juce_audio_processors/juce_audio_processors.h> // Include APVTS header

//==============================================================================
/**
*/
class AIplayerAudioProcessor  : public juce::AudioProcessor,
                                public juce::OSCReceiver::Listener<juce::OSCReceiver::MessageLoopCallback> // Inherit from OSCReceiver Listener
{
public:
    //==============================================================================
    AIplayerAudioProcessor();
    ~AIplayerAudioProcessor() override;

    //==============================================================================
    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;

   #ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported (const BusesLayout& layouts) const override;
   #endif

    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    //==============================================================================
    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override;

    //==============================================================================
    const juce::String getName() const override;

    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    double getTailLengthSeconds() const override;

    //==============================================================================
    int getNumPrograms() override;
    int getCurrentProgram() override;
    void setCurrentProgram (int index) override;
    const juce::String getProgramName (int index) override;
    void changeProgramName (int index, const juce::String& newName) override;

    //==============================================================================
    void getStateInformation (juce::MemoryBlock& destData) override;
    void setStateInformation (const void* data, int sizeInBytes) override;

    //==============================================================================
    /** Called by the PluginEditor when the user sends a chat message. */
    void sendChatMessage(const juce::String& message);

    //==============================================================================
    // Parameter Handling
    juce::AudioProcessorValueTreeState apvts; // Add APVTS member

private:
    // Helper function to create parameter layout
    static juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();

    // Parameter pointers for real-time access
    std::atomic<float>* gainParameter = nullptr;
    //==============================================================================
    // OSC Message Callback
    /** Handles incoming OSC messages received by the receiver. */
    void oscMessageReceived (const juce::OSCMessage& message) override;

    // Custom internal methods
    /** Sends an OSC message with an instance ID and a message string. */
    void sendOSC(const juce::String& addressPattern, int instanceID, const juce::String& message);

    //==============================================================================
    // OSC Sender / Receiver
    juce::OSCSender sender;
    juce::OSCReceiver receiver;

    // Logging
    std::unique_ptr<juce::FileOutputStream> logStream;
    void logMessage (const juce::String& message);

    //==============================================================================
    JUCE_DECLARE_WEAK_REFERENCEABLE (AIplayerAudioProcessor) // Make this class usable with WeakReference
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AIplayerAudioProcessor)
};
