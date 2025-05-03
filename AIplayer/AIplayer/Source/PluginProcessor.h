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
 * @class AIplayerAudioProcessor
 * @brief Main audio processor for the AIplayer plugin
 *
 * This class handles all audio processing, OSC communication, and parameter management
 * for the AIplayer plugin. It processes audio, sends/receives OSC messages,
 * manages plugin parameters via AudioProcessorValueTreeState, and provides
 * RMS telemetry functionality.
 */
class AIplayerAudioProcessor  : public juce::AudioProcessor,
                                public juce::OSCReceiver::Listener<juce::OSCReceiver::MessageLoopCallback>,
                                public juce::Timer
{
public:
    //==============================================================================
    /**
     * @brief Constructor for the AIplayerAudioProcessor
     *
     * Initializes all member variables, sets up OSC communication,
     * and configures audio processing parameters.
     */
    AIplayerAudioProcessor();
    
    /**
     * @brief Destructor for the AIplayerAudioProcessor
     *
     * Cleans up resources and properly shuts down OSC communication.
     */
    ~AIplayerAudioProcessor() override;

    //==============================================================================
    /**
     * @brief Called before playback starts to prepare resources
     *
     * @param sampleRate The sample rate that will be used for audio processing
     * @param samplesPerBlock The maximum number of samples in each audio buffer
     */
    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    
    /**
     * @brief Called when playback stops to free resources
     */
    void releaseResources() override;

   #ifndef JucePlugin_PreferredChannelConfigurations
    /**
     * @brief Checks if the provided bus layout is supported
     *
     * @param layouts The bus layout to check
     * @return true if the layout is supported, false otherwise
     */
    bool isBusesLayoutSupported (const BusesLayout& layouts) const override;
   #endif

    /**
     * @brief Processes a block of incoming audio data
     *
     * This is the main audio processing function that handles incoming audio,
     * calculates RMS values, and applies any needed processing.
     *
     * @param buffer The audio buffer containing the input data to process
     * @param midiMessages Any incoming MIDI messages to process
     */
    void processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages) override;

    //==============================================================================
    /**
     * @brief Creates the plugin's editor component
     *
     * @return A pointer to the newly created editor component
     */
    juce::AudioProcessorEditor* createEditor() override;
    
    /**
     * @brief Checks if this processor has an editor component
     *
     * @return true if the processor has an editor, false otherwise
     */
    bool hasEditor() const override;

    //==============================================================================
    /**
     * @brief Gets the name of the processor
     *
     * @return The name of the processor as a JUCE String
     */
    const juce::String getName() const override;

    /**
     * @brief Checks if the processor accepts MIDI input
     *
     * @return true if the processor accepts MIDI input, false otherwise
     */
    bool acceptsMidi() const override;
    
    /**
     * @brief Checks if the processor produces MIDI output
     *
     * @return true if the processor produces MIDI output, false otherwise
     */
    bool producesMidi() const override;
    
    /**
     * @brief Checks if the processor is a MIDI effect plugin
     *
     * @return true if the processor is a MIDI effect, false otherwise
     */
    bool isMidiEffect() const override;
    
    /**
     * @brief Gets the tail length in seconds
     *
     * @return The tail length in seconds
     */
    double getTailLengthSeconds() const override;

    //==============================================================================
    /**
     * @brief Gets the number of programs provided by the processor
     *
     * @return The number of programs
     */
    int getNumPrograms() override;
    
    /**
     * @brief Gets the index of the current program
     *
     * @return The index of the current program
     */
    int getCurrentProgram() override;
    
    /**
     * @brief Sets the current program
     *
     * @param index The index of the program to set as current
     */
    void setCurrentProgram (int index) override;
    
    /**
     * @brief Gets the name of the specified program
     *
     * @param index The index of the program
     * @return The name of the program as a JUCE String
     */
    const juce::String getProgramName (int index) override;
    
    /**
     * @brief Changes the name of the specified program
     *
     * @param index The index of the program to rename
     * @param newName The new name for the program
     */
    void changeProgramName (int index, const juce::String& newName) override;

    //==============================================================================
    /**
     * @brief Saves the current state of the processor to a memory block
     *
     * @param destData The memory block to store the state in
     */
    void getStateInformation (juce::MemoryBlock& destData) override;
    
    /**
     * @brief Restores the processor's state from a memory block
     *
     * @param data Pointer to the data to restore from
     * @param sizeInBytes The size of the data in bytes
     */
    void setStateInformation (const void* data, int sizeInBytes) override;

    //==============================================================================
    /**
     * @brief Called by the PluginEditor when the user sends a chat message
     *
     * Formats and sends the chat message via OSC.
     *
     * @param message The chat message to send
     */
    void sendChatMessage(const juce::String& message);

    //==============================================================================
    /**
     * @brief Audio processor value tree state for parameter management
     *
     * This manages all plugin parameters and their state, provides automatic
     * undo/redo functionality, and handles parameter attachments for UI components.
     */
    juce::AudioProcessorValueTreeState apvts;

private:
    /**
     * @brief Creates the parameter layout for the AudioProcessorValueTreeState
     *
     * Defines all parameters used by the plugin including their ranges,
     * default values, and skew factors.
     *
     * @return The parameter layout containing all plugin parameters
     */
    static juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();

    /**
     * @brief Pointer to the gain parameter for real-time access
     *
     * This provides thread-safe, lock-free access to the gain parameter value.
     */
    std::atomic<float>* gainParameter = nullptr;
    
    //==============================================================================
    /**
     * @brief Handles incoming OSC messages received by the OSCReceiver
     *
     * This callback is triggered when an OSC message is received, and it
     * processes the message based on its address pattern.
     *
     * @param message The received OSC message
     */
    void oscMessageReceived (const juce::OSCMessage& message) override;

    /**
     * @brief Sends an OSC message with an instance ID and a message string
     *
     * @param addressPattern The OSC address pattern to use
     * @param instanceID The instance ID to include in the message
     * @param message The message string to send
     */
    void sendOSC(const juce::String& addressPattern, int instanceID, const juce::String& message);

    //==============================================================================
    /**
     * @brief OSC sender for outgoing messages
     *
     * Handles sending OSC messages to external applications or services.
     */
    juce::OSCSender sender;
    
    /**
     * @brief OSC receiver for incoming messages
     *
     * Handles receiving OSC messages from external applications or services.
     */
    juce::OSCReceiver receiver;

    /**
     * @brief File output stream for logging
     *
     * Used to log messages and errors to a file for debugging.
     */
    std::unique_ptr<juce::FileOutputStream> logStream;
    
    /**
     * @brief Logs a message to the log file
     *
     * @param message The message to log
     */
    void logMessage (const juce::String& message);
    
    //==============================================================================
    /**
     * @brief Timer callback method that is called at regular intervals
     *
     * This is used to send RMS telemetry data at regular intervals.
     */
    void timerCallback() override;
    
    /**
     * @brief Sends the current RMS telemetry via OSC
     *
     * Calculates and sends the current RMS values from the audio buffer.
     */
    void sendRMSTelemetry();
    
    /**
     * @brief Calculates the RMS value from an audio buffer
     *
     * @param buffer The audio buffer to calculate RMS from
     * @return The calculated RMS value
     */
    float calculateRMS(const juce::AudioBuffer<float>& buffer);
    
    /**
     * @brief Stores the last processed audio buffer for RMS calculation
     *
     * This buffer is accessed from both the audio thread and the timer thread,
     * so access is protected by the bufferLock critical section.
     */
    juce::AudioBuffer<float> lastProcessedBuffer;
    
    /**
     * @brief Critical section for thread-safe access to lastProcessedBuffer
     *
     * Prevents concurrent access to the buffer from multiple threads.
     */
    juce::CriticalSection bufferLock;

    //==============================================================================
    JUCE_DECLARE_WEAK_REFERENCEABLE (AIplayerAudioProcessor)
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AIplayerAudioProcessor)
};
