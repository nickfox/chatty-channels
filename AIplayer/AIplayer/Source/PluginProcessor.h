// /Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Source/PluginProcessor.h
/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin processor.

  ==============================================================================
*/

#pragma once

#include "../JuceLibraryCode/JuceHeader.h" // Should be first for JUCE projects

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
    ~AIplayerAudioProcessor() noexcept override; // Added noexcept

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

    // Moved LogLevel and logMessage declaration to be before private section
    enum class LogLevel
    {
        Info,
        Warning,
        Error,
        Debug // For messages that are usually only relevant during development
    };
    /**
     * @brief Logs a message to the log file with a specified level
     *
     * @param level The severity level of the log message
     * @param message The message to log
     */
    void logMessage (LogLevel level, const juce::String& message);

    //==============================================================================
    /// Oscillator Control Methods
    
    /**
     * @brief Starts the calibration tone generation
     *
     * @param frequency The frequency of the tone in Hz
     * @param amplitudeDb The amplitude of the tone in dB
     */
    void startCalibrationTone(float frequency, float amplitudeDb);
    
    /**
     * @brief Stops the calibration tone generation
     */
    void stopCalibrationTone();
    
    /**
     * @brief Gets the current status of the calibration tone
     *
     * @return true if tone is currently enabled, false otherwise
     */
    bool isToneEnabled() const;

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

    juce::String tempInstanceID;    // Unique ID for this plugin instance before official Logic UUID is known
    juce::String logicTrackUUID;    // Official Logic Pro Track UUID, assigned by Control Room app
    int oscReceiverPort = 0;        // The port number our OSC receiver is bound to
    
    // Track OSC connection state since juce::OSCSender doesn't have isConnected()
    bool senderConnected = false;
    
    //==============================================================================
    // Port Assignment Protocol
    enum class PortState
    {
        Unassigned,      // No port assigned yet
        Requesting,      // Sent request, waiting for response
        Assigned,        // Port assigned by ChattyChannels
        Bound,          // Successfully bound to assigned port
        Failed          // Failed to bind or get assignment
    };
    
    PortState portState = PortState::Unassigned;
    int assignedPort = -1;
    int portRequestRetries = 0;
    const int maxPortRequestRetries = 5;
    juce::Time lastPortRequestTime;
    
    /**
     * @brief Requests a port assignment from ChattyChannels
     */
    void requestPortAssignment();
    
    /**
     * @brief Attempts to bind the OSC receiver to the assigned port
     * @param port The port number to bind to
     * @return true if successfully bound, false otherwise
     */
    bool bindToAssignedPort(int port);
    
    /**
     * @brief Verifies that we actually have the port (works around JUCE bug)
     * @param port The port number to verify
     * @return true if port is actually bound, false otherwise
     */
    bool verifyPortBinding(int port);
    
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
    /// Calibration oscillator for track identification using JUCE DSP
    juce::dsp::Oscillator<float> calibrationOscillator;
    juce::dsp::ProcessSpec oscProcessSpec;
    

    
    /// Whether the calibration tone is currently enabled
    std::atomic<bool> toneEnabled{false};
    
    /// Frequency of the calibration tone in Hz
    float toneFrequency = 440.0f;
    
    /// Amplitude of the calibration tone (linear gain, not dB)
    float toneAmplitude = 0.1f;
    
    /// Current sample rate for oscillator phase calculation
    double currentSampleRate = 44100.0;

    //==============================================================================
    JUCE_DECLARE_WEAK_REFERENCEABLE (AIplayerAudioProcessor)
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AIplayerAudioProcessor)
};
