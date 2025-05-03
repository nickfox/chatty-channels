/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin processor.

  ==============================================================================
*/

#include "PluginProcessor.h"
#include "PluginEditor.h"

#include <juce_core/juce_core.h> // Needed for FileOutputStream, Time, etc.

//==============================================================================
/**
 * @brief Creates the parameter layout for the AudioProcessorValueTreeState
 *
 * Defines all parameters used by the plugin including their ranges,
 * default values, and skew factors.
 *
 * @return The parameter layout containing all plugin parameters
 */
juce::AudioProcessorValueTreeState::ParameterLayout AIplayerAudioProcessor::createParameterLayout()
{
    std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;

    // Add Gain parameter with a version hint using ParameterID
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("GAIN", 1),               // Parameter ID with version hint
        "Gain",                                     // Parameter Name
        juce::NormalisableRange<float>(-60.0f, 0.0f, 0.1f), // Range (-60dB to 0dB, 0.1 step)
        0.0f,                                       // Default value
        "dB"                                        // Unit Suffix
    ));

    // Add more parameters here if needed in the future

    return { params.begin(), params.end() };
}

/**
 * @brief Constructor for the AIplayerAudioProcessor
 *
 * Initializes all member variables, sets up OSC communication,
 * configures audio processing parameters, and starts the RMS timer.
 */
AIplayerAudioProcessor::AIplayerAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
     : AudioProcessor (BusesProperties()
                     #if ! JucePlugin_IsMidiEffect
                      #if ! JucePlugin_IsSynth
                       .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                      #endif
                       .withOutput ("Output", juce::AudioChannelSet::stereo(), true)
                     #endif
                       ),
#else
     :
#endif
       apvts (*this, nullptr, "Parameters", createParameterLayout()) // Initialize APVTS here
{
    // Get the raw pointer to the gain parameter after APVTS initialization
    gainParameter = apvts.getRawParameterValue("GAIN");
    if (gainParameter)
        logMessage("Gain parameter pointer acquired.");
    else
        logMessage("Error: Failed to acquire Gain parameter pointer.");

    // --- Manual File Logging Setup ---
    // Construct path relative to user's home/Documents directory
    juce::File logDirectory = juce::File::getSpecialLocation (juce::File::userHomeDirectory)
                                .getChildFile ("Documents")
                                .getChildFile ("chatty-channel")
                                .getChildFile ("logs");

    if (!logDirectory.exists())
        logDirectory.createDirectory(); // Attempt to create logs directory

    if (logDirectory.isDirectory())
    {
        juce::File logFile = logDirectory.getChildFile("AIplayer.log");
        logStream = logFile.createOutputStream(); // Create/open the file stream

        if (logStream != nullptr)
        {
            logStream->setPosition(logFile.getSize()); // Append to existing file
            logMessage("--- AIplayer Plugin Starting ---");
            logMessage("Log Path: " + logFile.getFullPathName());
        }
        else
        {
            DBG("Error: Could not create FileOutputStream for log file: " + logFile.getFullPathName());
            // logStream remains nullptr
        }
    }
    else
    {
         DBG("Error: Could not create or access log directory: " + logDirectory.getFullPathName());
         // logStream remains nullptr
    }
    // --- End Logging Setup ---

    // Connect the OSC sender to Swift App's listening port (e.g., 9001)
    // Note: We assume Swift App listens on 9001 for requests from plugins
    if (!sender.connect("127.0.0.1", 9001))
    {
        logMessage("Error: Could not connect OSC sender to 127.0.0.1:9001");
    }
    else
    {
        logMessage("OSC Sender connected to 127.0.0.1:9001");
    }

    // Connect the OSC receiver to listen on a port for responses (e.g., 9000)
    // Note: This port needs to be unique per instance or managed carefully if multiple instances run
    // For now, using a fixed port 9000. Swift App needs to know to send responses here.
    if (!receiver.connect(9000))
    {
         logMessage("Error: Could not connect OSC receiver to port 9000");
    }
    else
    {
        logMessage("OSC Receiver connected to port 9000");
    }

    // Register listener for incoming OSC messages
    receiver.addListener(this);
    
    // Start the timer for RMS telemetry at 333 Hz (~3ms period)
    // This frequency gives approximately one update per 128 samples at 44.1 kHz
    startTimerHz(333);
    logMessage("RMS telemetry timer started at 333 Hz");
}

/**
 * @brief Destructor for the AIplayerAudioProcessor
 *
 * Cleans up resources and properly shuts down OSC communication.
 */
AIplayerAudioProcessor::~AIplayerAudioProcessor()
{
    // Stop the timer before destruction
    stopTimer();
    logMessage("RMS telemetry timer stopped");
    
    // Unregister OSC listener
    receiver.removeListener(this);
    
    // logStream unique_ptr will automatically delete the stream when processor is destroyed
}

//==============================================================================
/**
 * @brief Gets the name of the processor
 *
 * @return The name of the processor as a JUCE String
 */
const juce::String AIplayerAudioProcessor::getName() const
{
    // Returning a literal avoids relying on JucePlugin_Name macro,
    // which is only defined when the full JUCE plug-in wrapper headers are included.
    return "AIplayer";
}

/**
 * @brief Checks if the processor accepts MIDI input
 *
 * @return true if the processor accepts MIDI input, false otherwise
 */
bool AIplayerAudioProcessor::acceptsMidi() const
{
   #if JucePlugin_WantsMidiInput
    return true;
   #else
    return false;
   #endif
}

/**
 * @brief Checks if the processor produces MIDI output
 *
 * @return true if the processor produces MIDI output, false otherwise
 */
bool AIplayerAudioProcessor::producesMidi() const
{
   #if JucePlugin_ProducesMidiOutput
    return true;
   #else
    return false;
   #endif
}

/**
 * @brief Checks if the processor is a MIDI effect plugin
 *
 * @return true if the processor is a MIDI effect, false otherwise
 */
bool AIplayerAudioProcessor::isMidiEffect() const
{
   #if JucePlugin_IsMidiEffect
    return true;
   #else
    return false;
   #endif
}

/**
 * @brief Gets the tail length in seconds
 *
 * @return The tail length in seconds
 */
double AIplayerAudioProcessor::getTailLengthSeconds() const
{
    return 0.0;
}

/**
 * @brief Gets the number of programs provided by the processor
 *
 * @return The number of programs
 */
int AIplayerAudioProcessor::getNumPrograms()
{
    return 1;   // NB: some hosts don't cope very well if you tell them there are 0 programs,
                // so this should be at least 1, even if you're not really implementing programs.
}

/**
 * @brief Gets the index of the current program
 *
 * @return The index of the current program
 */
int AIplayerAudioProcessor::getCurrentProgram()
{
    return 0;
}

/**
 * @brief Sets the current program
 *
 * @param index The index of the program to set as current
 */
void AIplayerAudioProcessor::setCurrentProgram (int index)
{
    juce::ignoreUnused (index);
}

/**
 * @brief Gets the name of the specified program
 *
 * @param index The index of the program
 * @return The name of the program as a JUCE String
 */
const juce::String AIplayerAudioProcessor::getProgramName (int index)
{
    juce::ignoreUnused (index);
    return {};
}

/**
 * @brief Changes the name of the specified program
 *
 * @param index The index of the program to rename
 * @param newName The new name for the program
 */
void AIplayerAudioProcessor::changeProgramName (int index, const juce::String& newName)
{
    juce::ignoreUnused (index, newName);
}

//==============================================================================
/**
 * @brief Called before playback starts to prepare resources
 *
 * @param sampleRate The sample rate that will be used for audio processing
 * @param samplesPerBlock The maximum number of samples in each audio buffer
 */
void AIplayerAudioProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    // Use this method as the place to do any pre-playback
    // initialisation that you need..
    juce::ignoreUnused (sampleRate, samplesPerBlock);
}

/**
 * @brief Called when playback stops to free resources
 */
void AIplayerAudioProcessor::releaseResources()
{
    // When playback stops, you can use this as an opportunity to free up any
    // spare memory, etc.
}

#ifndef JucePlugin_PreferredChannelConfigurations
/**
 * @brief Checks if the provided bus layout is supported
 *
 * @param layouts The bus layout to check
 * @return true if the layout is supported, false otherwise
 */
bool AIplayerAudioProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
  #if JucePlugin_IsMidiEffect
    juce::ignoreUnused (layouts);
    return true;
  #else
    // This is the place where you check if the layout is supported.
    // In this template code we only support mono or stereo.
    // Some plugin hosts, such as certain GarageBand versions, will only
    // load plugins that support stereo bus layouts.
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono()
     && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;

    // This checks if the input layout matches the output layout
   #if ! JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
   #endif

    return true;
  #endif
}
#endif

/**
 * @brief Processes a block of incoming audio data
 *
 * This is the main audio processing function that handles incoming audio,
 * applies gain based on the parameter value, and stores a copy of the
 * processed buffer for RMS calculation.
 *
 * @param buffer The audio buffer containing the input data to process
 * @param midiMessages Any incoming MIDI messages to process
 */
void AIplayerAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    juce::ignoreUnused (midiMessages);
    juce::ScopedNoDenormals noDenormals;
    auto totalNumInputChannels  = getTotalNumInputChannels();
    auto totalNumOutputChannels = getTotalNumOutputChannels();

    // Clear extra output channels
    for (auto i = totalNumInputChannels; i < totalNumOutputChannels; ++i)
        buffer.clear (i, 0, buffer.getNumSamples());

    // --- Apply Gain Parameter ---
    // Get the current gain value in dB from the atomic pointer
    float currentGainDb = gainParameter->load();
    // Convert dB to a gain factor
    float gainFactor = juce::Decibels::decibelsToGain(currentGainDb);

    // Apply the gain to all input channels
    for (int channel = 0; channel < totalNumInputChannels; ++channel)
    {
        buffer.applyGain(channel, 0, buffer.getNumSamples(), gainFactor);
    }
    
    // Store a copy of the processed buffer for RMS calculation
    // This avoids potential threading issues with the timer callback
    const juce::ScopedLock sl(bufferLock);
    lastProcessedBuffer.makeCopyOf(buffer);
}

//==============================================================================
/**
 * @brief Checks if this processor has an editor component
 *
 * @return true if the processor has an editor, false otherwise
 */
bool AIplayerAudioProcessor::hasEditor() const
{
    return true; // (change this to false if you choose to not supply an editor)
}

/**
 * @brief Creates the plugin's editor component
 *
 * @return A pointer to the newly created editor component
 */
juce::AudioProcessorEditor* AIplayerAudioProcessor::createEditor()
{
    return new AIplayerAudioProcessorEditor (*this);
}

//==============================================================================
/**
 * @brief Saves the current state of the processor to a memory block
 *
 * Uses the AudioProcessorValueTreeState to store all parameters
 * in XML format within the memory block.
 *
 * @param destData The memory block to store the state in
 */
void AIplayerAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    // You should use this method to store your parameters in the memory block.
    // You could do that either as raw data, or use the XML or ValueTree classes
    // Use APVTS to store the state
    auto state = apvts.copyState();
    std::unique_ptr<juce::XmlElement> xml (state.createXml());
    copyXmlToBinary (*xml, destData);
    logMessage("Plugin state saved.");
}

/**
 * @brief Restores the processor's state from a memory block
 *
 * Uses the AudioProcessorValueTreeState to restore all parameters
 * from XML format within the memory block.
 *
 * @param data Pointer to the data to restore from
 * @param sizeInBytes The size of the data in bytes
 */
void AIplayerAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    // Use APVTS to restore the state
    std::unique_ptr<juce::XmlElement> xmlState (getXmlFromBinary (data, sizeInBytes));

    if (xmlState != nullptr)
    {
        if (xmlState->hasTagName (apvts.state.getType()))
        {
            apvts.replaceState (juce::ValueTree::fromXml (*xmlState));
            logMessage("Plugin state restored.");
        }
         else
        {
             logMessage("Error: Failed to restore state - XML tag mismatch.");
        }
    }
     else
    {
         logMessage("Error: Failed to restore state - Could not get XML from binary.");
    }
}

//==============================================================================
//==============================================================================
/**
 * @brief Called by the PluginEditor when the user sends a chat message
 *
 * Formats and sends the chat message via OSC.
 *
 * @param message The chat message to send
 */
void AIplayerAudioProcessor::sendChatMessage(const juce::String& message)
{
    // TODO: Add instance ID logic here if needed
    // For now, using a fixed address pattern
    int placeholderInstanceID = 1; // Placeholder - needs proper instance management later
    sendOSC("/aiplayer/chat/request", placeholderInstanceID, message);
}

//==============================================================================
/**
 * @brief Handles incoming OSC messages received by the OSCReceiver
 *
 * This callback is triggered when an OSC message is received, and it
 * processes the message based on its address pattern.
 *
 * @param message The received OSC message
 */
void AIplayerAudioProcessor::oscMessageReceived (const juce::OSCMessage& message)
{
    logMessage("OSC Message Received: " + message.getAddressPattern().toString());

    // Check if the message is the chat response we expect
    if (message.getAddressPattern() == "/aiplayer/chat/response")
    {
        // Expecting one string argument: the AI response
        if (message.size() == 1 && message[0].isString())
        {
            const juce::String response = message[0].getString();
            logMessage("Received chat response via OSC: " + response);

            // Safely get the active editor and update it
            // Use WeakReference to avoid issues if editor is deleted while message is processing
            juce::WeakReference<AIplayerAudioProcessor> weakSelf = this;
            juce::MessageManager::callAsync([weakSelf, response]() {
                if (weakSelf == nullptr) return; // Processor was deleted

                if (auto* editor = weakSelf->getActiveEditor())
                {
                    // Cast to our specific editor type to call the custom method
                    if (auto* aiEditor = dynamic_cast<AIplayerAudioProcessorEditor*>(editor))
                    {
                        aiEditor->displayReceivedMessage(response);
                    }
                    else
                    {
                        weakSelf->logMessage("Error: Could not cast active editor to AIplayerAudioProcessorEditor in oscMessageReceived callback."); // Call via weakSelf
                    }
                }
                 // else { weakSelf->logMessage("Warning: No active editor found to display received message."); } // Call via weakSelf
            });
        }
        else
        {
             logMessage("Warning: Received /aiplayer/chat/response message with unexpected arguments. Size: "
                                      + juce::String(message.size()));
       }
   }
   // Handle parameter setting messages
   else if (message.getAddressPattern() == "/aiplayer/set_parameter")
   {
       // Expecting: string parameterID, float value
       if (message.size() == 2 && message[0].isString() && message[1].isFloat32()) // Corrected: isFloat32()
       {
           juce::String paramID = message[0].getString();
           float value = message[1].getFloat32();

           logMessage("Received parameter set request via OSC: ParamID=" + paramID + ", Value=" + juce::String(value));

           // Find the parameter in the APVTS
           if (auto* parameter = apvts.getParameter(paramID))
           {
               // Convert the received value (assumed to be in the parameter's actual range, e.g., -60 to 0 dB)
               // to the normalized 0.0 to 1.0 range required by setValueNotifyingHost.
               float normalizedValue = parameter->convertTo0to1(value);

               // Clamp the normalized value just in case
               normalizedValue = juce::jlimit(0.0f, 1.0f, normalizedValue);

               // Set the parameter value and notify the host
               parameter->setValueNotifyingHost(normalizedValue);

               logMessage("Parameter " + paramID + " set to " + juce::String(value) + " (Normalized: " + juce::String(normalizedValue) + ")");
           }
           else
           {
               logMessage("Error: Parameter with ID '" + paramID + "' not found.");
           }
       }
       else
       {
           logMessage("Warning: Received /aiplayer/set_parameter message with unexpected arguments. Size: "
                                     + juce::String(message.size()));
           // Log argument types for debugging (getTypeString() is not a valid method)
           // We already know the types/count didn't match the expectation.
           logMessage("Arguments received did not match expected types (String, Float32).");
           // Example of checking specific types if needed for more detail:
           // for (int i = 0; i < message.size(); ++i) {
           //     if (message[i].isString()) logMessage("Arg " + juce::String(i) + " is String");
           //     else if (message[i].isFloat32()) logMessage("Arg " + juce::String(i) + " is Float32");
           //     // ... add other types as needed
           //     else logMessage("Arg " + juce::String(i) + " is of unexpected type.");
           // }
           }
       }
    // TODO: Add handling for other incoming OSC messages if needed
}

//==============================================================================
/**
 * @brief Logs a message to the log file
 *
 * Adds a timestamp to the message and writes it to the log file.
 * If the log file is not available, falls back to using DBG.
 *
 * @param message The message to log
 */
void AIplayerAudioProcessor::logMessage(const juce::String& message)
{
    if (logStream != nullptr)
    {
        // Add timestamp
        juce::String timestamp = juce::Time::getCurrentTime().toString (true, true, true, true);
        logStream->writeString (timestamp + " | " + message + juce::newLine);
        logStream->flush(); // Ensure it's written immediately for debugging
    }
    else
    {
        // Fallback to DBG if file stream isn't open
        DBG (message);
    }
}

//==============================================================================
/**
 * @brief Sends an OSC message with an instance ID and a message string
 *
 * @param addressPattern The OSC address pattern to use
 * @param instanceID The instance ID to include in the message
 * @param message The message string to send
 */
void AIplayerAudioProcessor::sendOSC(const juce::String& addressPattern, int instanceID, const juce::String& message)
{
    // Note: juce::OSCSender::send() returns false if not connected or on other errors.
    // The check below handles this.

    // Create the OSC message with the address pattern
    juce::OSCMessage oscMessage(addressPattern);

    // Add arguments: instance ID (int32) first, then message (string)
    oscMessage.addInt32(instanceID);
    oscMessage.addString(message);

    // Send the OSC message
    if (!sender.send(oscMessage))
    {
        logMessage("Error: Failed to send OSC message to " + addressPattern + " with ID: " + juce::String(instanceID) + ", Msg: " + message);
    }
    else
    {
        logMessage("OSC message sent to " + addressPattern + ": ID=" + juce::String(instanceID) + ", Msg=" + message);
    }
}

//==============================================================================
/**
 * @brief Creates new instances of the plugin
 *
 * This function is called by the host to create new instances of the plugin.
 * It's exported with C linkage to avoid name mangling.
 *
 * @return Pointer to a new AIplayerAudioProcessor
 */
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new AIplayerAudioProcessor();
}

//==============================================================================
// Timer and RMS Implementation

/**
 * @brief Timer callback method that is called at regular intervals
 *
 * This is used to send RMS telemetry data at regular intervals.
 * The frequency is set by startTimerHz() in the constructor.
 */
void AIplayerAudioProcessor::timerCallback()
{
    // This method is called regularly at the frequency set by startTimerHz()
    sendRMSTelemetry();
}

/**
 * @brief Sends the current RMS telemetry via OSC
 *
 * Calculates and sends the current RMS values from the audio buffer.
 * This function is called by the timer callback at regular intervals.
 */
void AIplayerAudioProcessor::sendRMSTelemetry()
{
    // Calculate RMS from the last processed buffer
    float rmsValue = 0.0f;
    
    {
        // Thread-safe access to lastProcessedBuffer
        const juce::ScopedLock sl(bufferLock);
        
        // Only calculate if we have samples
        if (lastProcessedBuffer.getNumSamples() > 0)
        {
            rmsValue = calculateRMS(lastProcessedBuffer);
        }
        else
        {
            // If no buffer is available yet, use a very low value
            rmsValue = 0.0001f;
        }
    }
    
    // Create the OSC message for RMS
    juce::OSCMessage rmsMessage("/aiplayer/rms");
    rmsMessage.addFloat32(rmsValue);
    
    // Send the OSC message
    if (!sender.send(rmsMessage))
    {
        logMessage("Error: Failed to send RMS telemetry via OSC");
    }
    else
    {
        // Uncomment for debugging, but note this could flood the log
        // logMessage("Sent RMS telemetry: " + juce::String(rmsValue));
    }
}

/**
 * @brief Calculates the RMS value from an audio buffer
 *
 * @param buffer The audio buffer to calculate RMS from
 * @return The calculated RMS value
 */
float AIplayerAudioProcessor::calculateRMS(const juce::AudioBuffer<float>& buffer)
{
    float sum = 0.0f;
    int numChannels = buffer.getNumChannels();
    int numSamples = buffer.getNumSamples();
    
    // Sum squared samples across all channels
    for (int channel = 0; channel < numChannels; ++channel)
    {
        const float* channelData = buffer.getReadPointer(channel);
        
        for (int sample = 0; sample < numSamples; ++sample)
        {
            float value = channelData[sample];
            sum += value * value; // Square the sample value
        }
    }
    
    // Calculate the mean of all squared samples
    float meanSquare = sum / (numChannels * numSamples);
    
    // Take the square root to get the RMS value
    float rms = std::sqrt(meanSquare);
    
    return rms;
}
