/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin processor.

  ==============================================================================
*/

#pragma once

#include "../JuceLibraryCode/JuceHeader.h"
#include "Core/Logger.h"
#include "Audio/AudioMetrics.h"
#include "Audio/CalibrationToneGenerator.h"
#include "Communication/OSCManager.h"
#include "Communication/PortManager.h"
#include "Communication/TelemetryService.h"

namespace AIplayer {

//==============================================================================
/**
 * @class AIplayerAudioProcessor
 * @brief Main audio processor for the AIplayer plugin
 *
 * This class coordinates all the plugin components and handles audio processing.
 * It follows the single responsibility principle by delegating specific tasks
 * to dedicated components.
 */
class AIplayerAudioProcessor : public juce::AudioProcessor,
                               public OSCManager::Listener,
                               public juce::Timer
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
    // Public interface for UI
    void sendChatMessage(const juce::String& message);
    
    // Component access for editor
    AudioMetrics& getAudioMetrics() { return *audioMetrics; }
    CalibrationToneGenerator& getToneGenerator() { return *toneGenerator; }
    
    // Plugin state
    juce::AudioProcessorValueTreeState apvts;
    
    // Instance identification
    const juce::String& getTempInstanceID() const { return tempInstanceID; }
    const juce::String& getLogicTrackUUID() const { return logicTrackUUID; }

private:
    //==============================================================================
    // Component initialization
    void initializeComponents();
    void setupOSCCommunication();
    void setupParameters();
    
    // Parameter layout creation
    static juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();
    
    //==============================================================================
    // OSCManager::Listener callbacks
    void handleTrackAssignment(const juce::String& trackID) override;
    void handlePortAssignment(int port, const juce::String& status) override;
    void handleParameterChange(const juce::String& param, float value) override;
    void handleRMSQuery(const juce::String& queryID) override;
    void handleToneControl(bool start, float frequency = 0.0f, float amplitude = 0.0f) override;
    void handleChatResponse(const juce::String& response) override;
    
    //==============================================================================
    // Timer callback for initialization retry
    void timerCallback() override;
    
    //==============================================================================
    // Core components
    std::unique_ptr<Logger> logger;
    std::unique_ptr<AudioMetrics> audioMetrics;
    std::unique_ptr<CalibrationToneGenerator> toneGenerator;
    
    // Communication components
    std::unique_ptr<OSCManager> oscManager;
    std::unique_ptr<PortManager> portManager;
    std::unique_ptr<TelemetryService> telemetryService;
    
    // Plugin state
    std::atomic<float>* gainParameter{nullptr};
    juce::String tempInstanceID;
    juce::String logicTrackUUID;
    
    // Initialization state
    bool componentsInitialized{false};
    int initRetryCount{0};
    static constexpr int maxInitRetries{3};
    
    //==============================================================================
    JUCE_DECLARE_WEAK_REFERENCEABLE (AIplayerAudioProcessor)
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AIplayerAudioProcessor)
};

} // namespace AIplayer

// Make the processor available without namespace for JUCE plugin factory
using AIplayerAudioProcessor = AIplayer::AIplayerAudioProcessor;
