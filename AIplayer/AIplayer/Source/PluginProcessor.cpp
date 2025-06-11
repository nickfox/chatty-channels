// /Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Source/PluginProcessor.cpp
/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin processor.

  ==============================================================================
*/

#include "../JuceLibraryCode/JuceHeader.h"
#include "PluginProcessor.h"
#include "PluginEditor.h"


// Helper function to get OSC argument type character
static juce::String getOscArgumentTypeChar(const juce::OSCArgument& arg)
{
    if (arg.isInt32())
        return "i";
    if (arg.isFloat32())
        return "f";
    if (arg.isString())
        return "s";
    if (arg.isBlob())
        return "b";
    // Add other types as needed, e.g., int64, timetags, doubles, chars, colours, MIDI messages, bools, nulls, infinites
    return "?";
}
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
        logMessage(LogLevel::Info, "Gain parameter pointer acquired.");
    else
        logMessage(LogLevel::Error, "Failed to acquire Gain parameter pointer.");
        
    // Add a distinctive log message to confirm this version is running
    logMessage(LogLevel::Info, "==================================================================");
    logMessage(LogLevel::Info, "AIplayer PLUGIN WITH 24 HZ CINEMA FRAMERATE TIMER STARTING!");
    logMessage(LogLevel::Info, "==================================================================");

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
            logMessage(LogLevel::Info, "--- AIplayer Plugin Starting ---");
            logMessage(LogLevel::Info, "Log Path: " + logFile.getFullPathName());
        }
        else
        {
            // DBG is fine here as logMessage itself might be failing
            DBG("CRITICAL: Could not create FileOutputStream for log file: " + logFile.getFullPathName());
            // logStream remains nullptr
        }
    }
    else
    {
         // DBG is fine here as logMessage itself might be failing
         DBG("CRITICAL: Could not create or access log directory: " + logDirectory.getFullPathName());
         // logStream remains nullptr
    }
    // --- End Logging Setup ---

    // Connect the OSC sender to Swift App's listening port (port 8999 to avoid conflict with plugin ports)
    // Note: Chatty Channels listens on 8999 for requests from plugins
    int maxRetries = 3;
    senderConnected = false;
    
    for (int retry = 0; retry < maxRetries; retry++) 
    {
        if (sender.connect("127.0.0.1", 8999))
        {
            logMessage(LogLevel::Info, "OSC Sender connected to 127.0.0.1:8999 on attempt " + juce::String(retry + 1));
            senderConnected = true;
            break;
        }
        
        logMessage(LogLevel::Warning, "Failed to connect OSC sender to 127.0.0.1:8999 on attempt " + 
                  juce::String(retry + 1) + " of " + juce::String(maxRetries));
        
        // Small delay before retrying
        juce::Thread::sleep(100);
    }
    
    if (!senderConnected)
    {
        logMessage(LogLevel::Error, "Could not connect OSC sender to 127.0.0.1:8999 after " + 
                   juce::String(maxRetries) + " attempts. VU meter will not function.");
    }

    // Bind to an ephemeral port first so we can receive the port assignment response
    int ephemeralPort = 0; // 0 means let the OS assign any available port
    if (receiver.connect(ephemeralPort))
    {
        // Get the actual port we were assigned
        // Note: JUCE doesn't provide a way to get the bound port, so we'll use a high range
        // Try binding to a specific high port range for ephemeral use
        receiver.disconnect();
        
        // Try ports in the 50000-60000 range for ephemeral binding
        bool ephemeralBound = false;
        for (int port = 50000; port < 60000; port += 100)
        {
            if (receiver.connect(port))
            {
                oscReceiverPort = port;
                ephemeralBound = true;
                logMessage(LogLevel::Info, "OSC Receiver bound to ephemeral port " + juce::String(port) + " for port assignment");
                break;
            }
        }
        
        if (!ephemeralBound)
        {
            logMessage(LogLevel::Error, "Failed to bind to any ephemeral port. Port assignment will fail.");
        }
    }
    else
    {
        logMessage(LogLevel::Error, "Failed to bind OSC receiver to ephemeral port");
    }
    
    // Initialize tempInstanceID BEFORE requesting port assignment
    tempInstanceID = juce::Uuid().toString();
    logMessage(LogLevel::Info, "Plugin Instance tempInstanceID: " + tempInstanceID);
    
    // Register listener for incoming OSC messages
    receiver.addListener(this);
    
    // Request port assignment from ChattyChannels
    requestPortAssignment();
    // logicTrackUUID is initially empty by default juce::String constructor
    
    // Initialize the lastProcessedBuffer with a small default size to avoid uninitialized access
    // This ensures the buffer is ready before timer starts
    lastProcessedBuffer.setSize(2, 512, false, true, false); // 2 channels, 512 samples, clear it
    
    // Initialize calibration oscillator with default spec
    oscProcessSpec.sampleRate = 44100.0;
    oscProcessSpec.maximumBlockSize = 512;
    oscProcessSpec.numChannels = 2;
    calibrationOscillator.prepare(oscProcessSpec);
    calibrationOscillator.setFrequency(440.0f);
    calibrationOscillator.initialise([](float x) { return std::sin(x); });
    

    
    logMessage(LogLevel::Info, "JUCE DSP calibration oscillator initialized");
    
    // Don't start RMS timer yet - wait until we have a port assigned
    // Timer will be started after successful port binding
    logMessage(LogLevel::Info, "RMS telemetry timer will start after port assignment");
}

/**
 * @brief Destructor for the AIplayerAudioProcessor
 *
 * Cleans up resources and properly shuts down OSC communication.
 */
AIplayerAudioProcessor::~AIplayerAudioProcessor() noexcept
{
    // Stop the timer before destruction
    stopTimer();
    logMessage(LogLevel::Info, "RMS telemetry timer stopped");
    
    // Unregister OSC listener
    receiver.removeListener(this);
    logMessage(LogLevel::Info, "OSC listener unregistered.");
    
    logMessage(LogLevel::Info, "--- AIplayer Plugin Shutting Down ---");
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
    logMessage(LogLevel::Info, "prepareToPlay called. Sample Rate: " + juce::String(sampleRate) + ", Samples Per Block: " + juce::String(samplesPerBlock));
    
    // Store sample rate for oscillator use
    currentSampleRate = sampleRate;
    
    // Update oscillator process spec and prepare
    oscProcessSpec.sampleRate = sampleRate;
    oscProcessSpec.maximumBlockSize = samplesPerBlock;
    oscProcessSpec.numChannels = getTotalNumOutputChannels();
    calibrationOscillator.prepare(oscProcessSpec);
    calibrationOscillator.setFrequency(toneFrequency);
    

    
    logMessage(LogLevel::Info, "JUCE DSP calibration oscillator prepared for sample rate: " + juce::String(sampleRate));
    
    juce::ignoreUnused (samplesPerBlock);
}

/**
 * @brief Called when playback stops to free resources
 */
void AIplayerAudioProcessor::releaseResources()
{
    // When playback stops, you can use this as an opportunity to free up any
    // spare memory, etc.
    logMessage(LogLevel::Info, "releaseResources called.");
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
    
    // Add calibration tone if enabled
    if (toneEnabled.load())
    {
        // Update oscillator frequency if needed
        calibrationOscillator.setFrequency(toneFrequency);
        
        // Create a temporary buffer for the tone (same size as input buffer)
        juce::AudioBuffer<float> toneBuffer(buffer.getNumChannels(), buffer.getNumSamples());
        toneBuffer.clear();
        
        // Create audio block and process context for the tone buffer
        juce::dsp::AudioBlock<float> toneBlock(toneBuffer);
        juce::dsp::ProcessContextReplacing<float> context(toneBlock);
        
        // Generate the tone into the temporary buffer
        calibrationOscillator.process(context);
        
        // Apply amplitude and mix with existing audio
        for (int channel = 0; channel < buffer.getNumChannels(); ++channel)
        {
            buffer.addFrom(channel, 0, toneBuffer, channel, 0, buffer.getNumSamples(), toneAmplitude);
        }
    }
    
    // Store a copy of the processed buffer for RMS calculation
    // Make sure we only allocate memory if needed
    {
        const juce::ScopedLock sl(bufferLock);
        
        // Only resize if the buffer configuration has changed
        // to avoid unnecessary memory allocation in the audio thread
        if (lastProcessedBuffer.getNumChannels() != buffer.getNumChannels() || 
            lastProcessedBuffer.getNumSamples() != buffer.getNumSamples())
        {
            lastProcessedBuffer.setSize(buffer.getNumChannels(), buffer.getNumSamples(), false, false, true);
        }
        
        // Copy only what we need for RMS calculation
        // This is a lightweight copy that should be fast
        for (int channel = 0; channel < buffer.getNumChannels(); ++channel)
        {
            lastProcessedBuffer.copyFrom(channel, 0, buffer, channel, 0, buffer.getNumSamples());
        }
    }
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
    try
    {
        // You should use this method to store your parameters in the memory block.
        // You could do that either as raw data, or use the XML or ValueTree classes
        // Use APVTS to store the state
        auto state = apvts.copyState();
        std::unique_ptr<juce::XmlElement> xml (state.createXml());
        if (xml != nullptr)
        {
            copyXmlToBinary (*xml, destData);
            logMessage(LogLevel::Info, "Plugin state saved.");
        }
        else
        {
            logMessage(LogLevel::Error, "Failed to create XML from state for saving.");
        }
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Exception in getStateInformation: " + juce::String(e.what()));
    }
    catch (...)
    {
        logMessage(LogLevel::Error, "Unknown exception in getStateInformation");
    }
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
    try
    {
        // Use APVTS to restore the state
        std::unique_ptr<juce::XmlElement> xmlState (getXmlFromBinary (data, sizeInBytes));

        if (xmlState != nullptr)
        {
            if (xmlState->hasTagName (apvts.state.getType()))
            {
                apvts.replaceState (juce::ValueTree::fromXml (*xmlState));
                logMessage(LogLevel::Info, "Plugin state restored.");
            }
             else
            {
                 logMessage(LogLevel::Error, "Failed to restore state - XML tag mismatch. Expected: " + apvts.state.getType().toString() + ", Got: " + xmlState->getTagName());
            }
        }
         else
        {
             logMessage(LogLevel::Error, "Failed to restore state - Could not get XML from binary data of size " + juce::String(sizeInBytes) + " bytes.");
        }
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Exception in setStateInformation: " + juce::String(e.what()));
    }
    catch (...)
    {
        logMessage(LogLevel::Error, "Unknown exception in setStateInformation");
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
    try
    {
        // Only log important messages, not routine RMS traffic
        if (!message.getAddressPattern().toString().contains("rms") &&
            !message.getAddressPattern().toString().contains("query_rms"))
        {
            logMessage(LogLevel::Info, "Received OSC message: " + message.getAddressPattern().toString() + 
                       " with " + juce::String(message.size()) + " arguments");
        }

        // Check if the message is the chat response we expect
        if (message.getAddressPattern() == "/aiplayer/chat/response")
    {
        // Expecting one string argument: the AI response
        if (message.size() == 1 && message[0].isString())
        {
            const juce::String response = message[0].getString();
            logMessage(LogLevel::Info, "Received chat response via OSC: " + response);

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
                        weakSelf->logMessage(LogLevel::Error, "Could not cast active editor to AIplayerAudioProcessorEditor in oscMessageReceived callback."); // Call via weakSelf
                    }
                }
                // else { weakSelf->logMessage(LogLevel::Warning, "No active editor found to display received message."); } // Call via weakSelf
            });
        }
        else
        {
             logMessage(LogLevel::Warning, "Received /aiplayer/chat/response message with unexpected arguments. Expected 1 string, got "
                                       + juce::String(message.size()) + " arguments.");
            for(int i = 0; i < message.size(); ++i) {
                logMessage(LogLevel::Debug, "Arg " + juce::String(i) + " type: " + getOscArgumentTypeChar(message[i]));
            }
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

           logMessage(LogLevel::Info, "Received parameter set request via OSC: ParamID=" + paramID + ", Value=" + juce::String(value));

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

               logMessage(LogLevel::Info, "Parameter " + paramID + " set to " + juce::String(value) + " (Normalized: " + juce::String(normalizedValue) + ")");
           }
           else
           {
               logMessage(LogLevel::Error, "Parameter with ID '" + paramID + "' not found for set_parameter request.");
           }
       }
       else
       {
           logMessage(LogLevel::Warning, "Received /aiplayer/set_parameter message with unexpected arguments. Expected 2 (String, Float32), got "
                                     + juce::String(message.size()) + " arguments.");
           for(int i = 0; i < message.size(); ++i) {
               logMessage(LogLevel::Debug, "Arg " + juce::String(i) + " type: " + getOscArgumentTypeChar(message[i]));
           }
       }
   }
   else if (message.getAddressPattern().toString() == "/aiplayer/track_uuid_assignment")
   {
       // ChattyChannels sends 3 arguments, and the first might be an int or string
       if (message.size() >= 2)
       {
           juce::String tempIDToMatch;
           juce::String assignedUUID;
           
           // Handle first argument - could be int or string
           if (message[0].isString())
           {
               tempIDToMatch = message[0].getString();
           }
           else if (message[0].isInt32())
           {
               // Convert int to string if needed
               tempIDToMatch = juce::String(message[0].getInt32());
           }
           else
           {
               logMessage(LogLevel::Warning, "First argument of track_uuid_assignment is neither string nor int");
               return;
           }
           
           // Second argument should be string
           if (message[1].isString())
           {
               assignedUUID = message[1].getString();
           }
           else
           {
               logMessage(LogLevel::Warning, "Second argument of track_uuid_assignment is not a string");
               return;
           }
           
           // Log what we received
           logMessage(LogLevel::Info, "Received /aiplayer/track_uuid_assignment:");
           logMessage(LogLevel::Info, "  tempIDToMatch: " + tempIDToMatch);
           logMessage(LogLevel::Info, "  assignedUUID: " + assignedUUID);
           if (message.size() > 2 && message[2].isString())
               logMessage(LogLevel::Info, "  third arg: " + message[2].getString());

           // BUT WAIT - ChattyChannels is sending the PORT as the first argument!
           // Let's check if the second or third argument matches our tempID
           bool matched = false;
           
           // Check if second argument is our tempID
           if (assignedUUID == this->tempInstanceID)
           {
               // Pattern: [port, tempID, trackUUID]
               this->logicTrackUUID = (message.size() > 2 && message[2].isString()) ? message[2].getString() : "";
               matched = true;
               logMessage(LogLevel::Info, "Matched pattern [port, tempID, trackUUID]");
           }
           // Check if first argument (as string) is our tempID  
           else if (tempIDToMatch == this->tempInstanceID)
           {
               // Pattern: [tempID, trackUUID, ...]
               this->logicTrackUUID = assignedUUID;
               matched = true;
               logMessage(LogLevel::Info, "Matched pattern [tempID, trackUUID, ...]");
           }
           
           if (matched && !this->logicTrackUUID.isEmpty())
           {
               logMessage(LogLevel::Info, "Plugin " + tempInstanceID + " successfully assigned LogicTrackUUID: " + this->logicTrackUUID);
               
               // Send confirmation back to ChattyChannels
               juce::OSCMessage confirmation("/aiplayer/uuid_assignment_confirmed");
               confirmation.addString(tempInstanceID);
               confirmation.addString(this->logicTrackUUID);
               confirmation.addString("confirmed");
               
               if (!sender.send(confirmation))
               {
                   logMessage(LogLevel::Warning, "Failed to send UUID assignment confirmation");
               }
               else
               {
                   logMessage(LogLevel::Info, "Sent UUID assignment confirmation for track " + this->logicTrackUUID);
               }
           }
           else if (!matched)
           {
               logMessage(LogLevel::Debug, "Plugin " + tempInstanceID + " received track_uuid_assignment not meant for it");
           }
       }
       else
       {
           logMessage(LogLevel::Warning, "Received /aiplayer/track_uuid_assignment with insufficient arguments: " + juce::String(message.size()));
       }
   }
   else if (message.getAddressPattern().toString() == "/aiplayer/query_rms")
   {
       if (message.size() == 1 && message[0].isString())
       {
           juce::String queryID = message[0].getString();
           // Don't log RMS queries - they happen frequently during calibration
           
           // Get current RMS level from the last processed buffer
           float currentRMS = 0.0f;
           {
               const juce::ScopedLock sl(bufferLock);
               if (lastProcessedBuffer.getNumSamples() > 0)
               {
                   currentRMS = calculateRMS(lastProcessedBuffer);
               }
               else
               {
                   currentRMS = 0.0001f; // Default very low value if no buffer
               }
           }
           
           // Send response back to ChattyChannels
           juce::OSCMessage response("/aiplayer/rms_response");
           response.addString(queryID);
           response.addString(tempInstanceID);
           response.addFloat32(currentRMS);
           
           if (!sender.send(response))
           {
               logMessage(LogLevel::Warning, "Failed to send RMS response for query: " + queryID);
           }
           // Don't log successful RMS responses - they happen too frequently
       }
       else
       {
           logMessage(LogLevel::Warning, "Received /aiplayer/query_rms message with unexpected arguments. Expected 1 string, got "
                                     + juce::String(message.size()) + " arguments.");
       }
   }
   else if (message.getAddressPattern().toString() == "/aiplayer/start_tone")
   {
       if (message.size() == 2 && message[0].isFloat32() && message[1].isFloat32())
       {
           float frequency = message[0].getFloat32();
           float amplitudeDb = message[1].getFloat32();
           
           logMessage(LogLevel::Info, "Received start_tone command: freq=" + juce::String(frequency) + 
                     "Hz, amp=" + juce::String(amplitudeDb) + "dB");
           
           startCalibrationTone(frequency, amplitudeDb);
           
           // Send confirmation response
           juce::OSCMessage response("/aiplayer/tone_started");
           response.addString(tempInstanceID);
           response.addFloat32(frequency);
           
           if (!sender.send(response))
           {
               logMessage(LogLevel::Warning, "Failed to send tone_started response");
           }
       }
       else
       {
           logMessage(LogLevel::Warning, "Received /aiplayer/start_tone with unexpected arguments. Expected 2 floats, got "
                                     + juce::String(message.size()) + " arguments.");
           
           // Send error response
           juce::OSCMessage errorResponse("/aiplayer/tone_error");
           errorResponse.addString(tempInstanceID);
           errorResponse.addString("Invalid arguments for start_tone");
           sender.send(errorResponse);
       }
   }
   else if (message.getAddressPattern().toString() == "/aiplayer/stop_tone")
   {
       logMessage(LogLevel::Info, "Received stop_tone command");
       
       stopCalibrationTone();
       
       // Send confirmation response
       juce::OSCMessage response("/aiplayer/tone_stopped");
       response.addString(tempInstanceID);
       
       if (!sender.send(response))
       {
           logMessage(LogLevel::Warning, "Failed to send tone_stopped response");
       }
   }
   else if (message.getAddressPattern().toString() == "/aiplayer/tone_status")
   {
       // Send current tone status without logging
       juce::OSCMessage response("/aiplayer/tone_status_response");
       response.addString(tempInstanceID);
       response.addInt32(toneEnabled.load() ? 1 : 0);
       response.addFloat32(toneFrequency);
       response.addFloat32(juce::Decibels::gainToDecibels(toneAmplitude));
       
       if (!sender.send(response))
       {
           logMessage(LogLevel::Warning, "Failed to send tone_status_response");
       }
   }
   else if (message.getAddressPattern().toString() == "/aiplayer/port_assignment")
   {
       if (message.size() == 3 && message[0].isString() && message[1].isInt32() && message[2].isString())
       {
           juce::String assignedTempID = message[0].getString();
           int32_t assignedPortNum = message[1].getInt32();
           juce::String status = message[2].getString();
           
           logMessage(LogLevel::Info, "Received port assignment: tempID=" + assignedTempID + 
                     ", port=" + juce::String(assignedPortNum) + ", status=" + status);
           
           // Verify this assignment is for us
           if (assignedTempID == tempInstanceID)
           {
               if (status == "assigned" && assignedPortNum > 0)
               {
                   assignedPort = assignedPortNum;
                   portState = PortState::Assigned;
                   
                   // Try to bind to the assigned port
                   if (bindToAssignedPort(assignedPortNum))
                   {
                       logMessage(LogLevel::Info, "Successfully bound to assigned port " + juce::String(assignedPortNum));
                   }
                   else
                   {
                       logMessage(LogLevel::Error, "Failed to bind to assigned port " + juce::String(assignedPortNum));
                       portState = PortState::Failed;
                       // Try requesting a new port
                       requestPortAssignment();
                   }
               }
               else
               {
                   logMessage(LogLevel::Error, "Port assignment failed with status: " + status);
                   portState = PortState::Failed;
                   // Retry after a delay
                   startTimerHz(0.5); // Retry in 2 seconds
               }
           }
           else
           {
               logMessage(LogLevel::Debug, "Ignoring port assignment for different plugin: " + assignedTempID);
           }
       }
       else
       {
           logMessage(LogLevel::Warning, "Received /aiplayer/port_assignment with unexpected arguments");
       }
   }
   else
   {
       logMessage(LogLevel::Warning, "Received unhandled OSC message with address: " + message.getAddressPattern().toString());
   }
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Exception in oscMessageReceived: " + juce::String(e.what()));
    }
    catch (...)
    {
        logMessage(LogLevel::Error, "Unknown exception in oscMessageReceived");
    }
}

//==============================================================================
/**
 * @brief Logs a message to the log file
 *
 * Adds a timestamp to the message and writes it to the log file.
 * If the log file is not available, falls back to using DBG.
 *
 * @param level The severity level of the log message
 * @param message The message to log
 */
void AIplayerAudioProcessor::logMessage(LogLevel level, const juce::String& message)
{
    // Filter out debug messages in production to reduce log size
    if (level == LogLevel::Debug)
        return;
    
    juce::String levelStr;
    switch (level)
    {
        case LogLevel::Info:    levelStr = "INFO";    break;
        case LogLevel::Warning: levelStr = "WARNING"; break;
        case LogLevel::Error:   levelStr = "ERROR";   break;
        case LogLevel::Debug:   levelStr = "DEBUG";   break;
        default:                levelStr = "UNKNOWN"; break;
    }

    if (logStream != nullptr)
    {
        // Add timestamp and level
        juce::String timestamp = juce::Time::getCurrentTime().toString (true, true, true, true);
        juce::String fullMessage = timestamp + " | " + levelStr + " | " + message + juce::newLine;
        
        // Use writeText instead of writeString to avoid null terminator
        logStream->writeText (fullMessage, false, false, nullptr);
        logStream->flush(); // Ensure it's written immediately for debugging
    }
    else
    {
        // Fallback to DBG if file stream isn't open
        // Prepend level to DBG output as well for consistency if log file fails
        DBG (levelStr + " | " + message);
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
        // Mark the connection as disconnected
        senderConnected = false;
        logMessage(LogLevel::Error, "Failed to send OSC message to " + addressPattern + " with ID: " + juce::String(instanceID) + ", Msg: " + message);
    }
    else
    {
        // Ensure connected flag is set
        senderConnected = true;
        logMessage(LogLevel::Debug, "OSC message sent to " + addressPattern + ": ID=" + juce::String(instanceID) + ", Msg=" + message);
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
    try
    {
        // Check if we're using the timer for port request retries
        if (portState != PortState::Bound)
        {
            // We're in port request mode
            if (portState == PortState::Requesting || portState == PortState::Unassigned)
            {
                // Check if enough time has passed for a retry
                auto timeSinceLastRequest = juce::Time::getCurrentTime() - lastPortRequestTime;
                if (timeSinceLastRequest.inMilliseconds() >= 2000) // 2 seconds timeout
                {
                    logMessage(LogLevel::Warning, "Port assignment request timed out, retrying...");
                    requestPortAssignment();
                }
            }
            else if (portState == PortState::Failed)
            {
                // Try again after failure
                requestPortAssignment();
            }
            return; // Don't send RMS telemetry until we have a port
        }
        
        // Normal RMS telemetry mode - send without logging
        // Remove heartbeat logging entirely - it's not needed in production
        sendRMSTelemetry();
    }
    catch (const std::bad_alloc& e)
    {
        logMessage(LogLevel::Error, "Memory allocation exception in timerCallback: " + juce::String(e.what()));
    }
    catch (const std::runtime_error& e)
    {
        logMessage(LogLevel::Error, "Runtime exception in timerCallback: " + juce::String(e.what()));
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Standard exception in timerCallback: " + juce::String(e.what()));
    }
    catch (...)
    {
        logMessage(LogLevel::Error, "Unknown exception in timerCallback");
    }
}

/**
 * @brief Sends the current RMS telemetry via OSC
 *
 * Calculates and sends the current RMS values from the audio buffer.
 * This function is called by the timer callback at regular intervals.
 */
void AIplayerAudioProcessor::sendRMSTelemetry()
{
    // Step 1: Check OSC connection
    try
    {
        if (!senderConnected)
        {
            // Only log reconnection attempts, not routine operations
            // Try to reconnect the sender
            if (!sender.connect("127.0.0.1", 8999))
            {
                logMessage(LogLevel::Error, "Failed to reconnect OSC sender for RMS telemetry.");
                return;
            }
            else
            {
                senderConnected = true;
                logMessage(LogLevel::Info, "Successfully reconnected OSC sender for RMS telemetry.");
            }
        }
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Exception in OSC connection check: " + juce::String(e.what()));
        return;
    }
    
    // Step 2: Calculate RMS from buffer
    float rmsValue = 0.0f;
    try
    {
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
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Exception in RMS calculation: " + juce::String(e.what()));
        return;
    }
    
    // Step 3: Prepare address and ID strings
    juce::String addressPatternString;
    juce::String idToSend;
    try
    {
        // If we have a Logic track UUID assigned, use that for identification
        if (!logicTrackUUID.isEmpty())
        {
            addressPatternString = "/aiplayer/rms";
            idToSend = logicTrackUUID;  // Send the track ID (TR1, TR2, TR3, etc.)
        }
        else if (portState == PortState::Bound && assignedPort > 0)
        {
            // Fallback to port-based identification if no track UUID yet
            addressPatternString = "/aiplayer/rms_" + juce::String(assignedPort);
            idToSend = tempInstanceID;
        }
        else
        {
            // Last resort - unidentified
            addressPatternString = "/aiplayer/rms_unidentified";
            idToSend = tempInstanceID;
        }
        
        // Validate our data before sending
        if (idToSend.isEmpty())
        {
            logMessage(LogLevel::Error, "Cannot send RMS telemetry - ID string is empty.");
            return;
        }
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Exception in address/ID preparation: " + juce::String(e.what()));
        return;
    }
    
    // Step 4: Create and send OSC message
    try
    {
        // Create the message with proper error handling
        juce::OSCMessage rmsMessageToSend(juce::OSCAddressPattern(addressPatternString.toStdString()));
        rmsMessageToSend.addString(idToSend.toStdString());
        rmsMessageToSend.addFloat32(rmsValue);
        
        // Step 5: Send the OSC message
        bool sendResult = false;
        try
        {
            sendResult = sender.send(rmsMessageToSend);
        }
        catch (const std::exception& sendEx)
        {
            logMessage(LogLevel::Error, "Exception during OSC send: " + juce::String(sendEx.what()));
            senderConnected = false;
            return;
        }
        
        if (!sendResult)
        {
            // Mark connection as disconnected
            senderConnected = false;
            // Only log errors, not successful sends
            logMessage(LogLevel::Warning, "Failed to send RMS telemetry via OSC - send returned false");
        }
        else
        {
            // Ensure connected flag is set
            senderConnected = true;
            // Don't log successful sends - they happen 24 times per second!
        }
    }
    catch (const std::bad_alloc& e)
    {
        logMessage(LogLevel::Error, "Memory allocation exception in OSC message creation: " + juce::String(e.what()));
        return;
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Exception in OSC message creation/sending: " + juce::String(e.what()));
        return;
    }
    catch (...)
    {
        logMessage(LogLevel::Error, "Unknown exception in OSC message creation/sending");
        return;
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
    const int numChannels = buffer.getNumChannels();
    const int numSamples = buffer.getNumSamples();
    
    // If no data, return minimum value
    if (numChannels == 0 || numSamples == 0)
        return 0.0001f;
    
    // Total number of samples across all channels
    const int totalSamples = numChannels * numSamples;
    
    // Process 4 samples at a time where possible for better performance
    const int numQuads = numSamples / 4;
    
    // Sum squared samples across all channels
    for (int channel = 0; channel < numChannels; ++channel)
    {
        const float* channelData = buffer.getReadPointer(channel);
        
        // Process 4 samples at a time for most of the buffer
        for (int quad = 0; quad < numQuads; ++quad)
        {
            const int sampleIdx = quad * 4;
            const float s1 = channelData[sampleIdx];
            const float s2 = channelData[sampleIdx + 1];
            const float s3 = channelData[sampleIdx + 2];
            const float s4 = channelData[sampleIdx + 3];
            
            sum += s1 * s1 + s2 * s2 + s3 * s3 + s4 * s4;
        }
        
        // Process any remaining samples
        for (int sample = numQuads * 4; sample < numSamples; ++sample)
        {
            const float value = channelData[sample];
            sum += value * value;
        }
    }
    
    // Calculate the mean of all squared samples
    const float meanSquare = sum / static_cast<float>(totalSamples);
    
    // Take the square root to get the RMS value
    // Add small epsilon to avoid denormals
    return std::sqrt(meanSquare + 1.0e-10f);
}

//==============================================================================
// Oscillator Control Implementation

/**
 * @brief Starts the calibration tone generation
 *
 * @param frequency The frequency of the tone in Hz
 * @param amplitudeDb The amplitude of the tone in dB
 */
void AIplayerAudioProcessor::startCalibrationTone(float frequency, float amplitudeDb)
{
    toneFrequency = frequency;
    toneAmplitude = juce::Decibels::decibelsToGain(amplitudeDb);
    
    // Update oscillator frequency
    calibrationOscillator.setFrequency(frequency);
    calibrationOscillator.reset(); // Reset phase for clean start
    
    // Enable tone generation atomically
    toneEnabled.store(true);
    
    logMessage(LogLevel::Info, "Calibration tone started: " + juce::String(frequency) + 
               "Hz at " + juce::String(amplitudeDb) + "dB");
}

/**
 * @brief Stops the calibration tone generation
 */
void AIplayerAudioProcessor::stopCalibrationTone()
{
    toneEnabled.store(false);
    logMessage(LogLevel::Info, "Calibration tone stopped");
}

/**
 * @brief Gets the current status of the calibration tone
 *
 * @return true if tone is currently enabled, false otherwise
 */
bool AIplayerAudioProcessor::isToneEnabled() const
{
    return toneEnabled.load();
}

//==============================================================================
// Port Assignment Protocol Implementation

/**
 * @brief Requests a port assignment from ChattyChannels
 */
void AIplayerAudioProcessor::requestPortAssignment()
{
    if (portState == PortState::Bound)
    {
        logMessage(LogLevel::Debug, "Already have bound port " + juce::String(assignedPort) + ", skipping request");
        return;
    }
    
    if (portState == PortState::Requesting)
    {
        // Check if we should retry
        auto timeSinceLastRequest = juce::Time::getCurrentTime() - lastPortRequestTime;
        if (timeSinceLastRequest.inMilliseconds() < 2000) // Wait at least 2 seconds between retries
        {
            return;
        }
    }
    
    if (portRequestRetries >= maxPortRequestRetries)
    {
        logMessage(LogLevel::Error, "Max port request retries reached. Unable to get port assignment.");
        portState = PortState::Failed;
        return;
    }
    
    logMessage(LogLevel::Info, "Requesting port assignment from ChattyChannels (attempt " + 
               juce::String(portRequestRetries + 1) + "/" + juce::String(maxPortRequestRetries) + ")");
    
    // Create port request message
    juce::OSCMessage portRequest("/aiplayer/request_port");
    portRequest.addString(tempInstanceID.toStdString());
    portRequest.addInt32(-1); // No preferred port
    portRequest.addInt32(oscReceiverPort); // Include our ephemeral port for response
    
    logMessage(LogLevel::Info, "Sending port request with tempID: " + tempInstanceID + 
               ", preferred: -1, responsePort: " + juce::String(oscReceiverPort));
    
    if (!sender.send(portRequest))
    {
        logMessage(LogLevel::Error, "Failed to send port request");
        // Schedule retry
        portRequestRetries++;
        startTimerHz(0.5); // Retry in 2 seconds
        return;
    }
    
    portState = PortState::Requesting;
    lastPortRequestTime = juce::Time::getCurrentTime();
    portRequestRetries++;
    
    // Start a timer to retry if we don't get a response
    startTimerHz(0.5); // Check every 2 seconds
}

/**
 * @brief Attempts to bind the OSC receiver to the assigned port
 */
bool AIplayerAudioProcessor::bindToAssignedPort(int port)
{
    logMessage(LogLevel::Info, "Attempting to bind OSC receiver to assigned port " + juce::String(port));
    
    // First disconnect if already connected
    receiver.disconnect();
    juce::Thread::sleep(50);
    
    // Try to connect to the assigned port
    try
    {
        if (receiver.connect(port))
        {
            // Verify we actually got the port (JUCE bug workaround)
            if (verifyPortBinding(port))
            {
                oscReceiverPort = port;
                assignedPort = port;
                portState = PortState::Bound;
                
                logMessage(LogLevel::Info, "Successfully bound OSC receiver to port " + juce::String(port));
                
                // Send confirmation to ChattyChannels
                juce::OSCMessage confirmation("/aiplayer/port_confirmed");
                confirmation.addString(tempInstanceID.toStdString());
                confirmation.addInt32(port);
                confirmation.addString("bound");
                
                if (!sender.send(confirmation))
                {
                    logMessage(LogLevel::Warning, "Failed to send port confirmation");
                }
                
                // Now we can start sending RMS telemetry
                startTimerHz(24); // 24 Hz for smooth VU meter updates
                
                return true;
            }
            else
            {
                logMessage(LogLevel::Error, "Port " + juce::String(port) + " verification failed");
                receiver.disconnect();
            }
        }
        else
        {
            logMessage(LogLevel::Error, "Failed to connect receiver to port " + juce::String(port));
        }
    }
    catch (const std::exception& e)
    {
        logMessage(LogLevel::Error, "Exception binding to port " + juce::String(port) + ": " + juce::String(e.what()));
    }
    
    // Binding failed - notify ChattyChannels
    juce::OSCMessage confirmation("/aiplayer/port_confirmed");
    confirmation.addString(tempInstanceID.toStdString());
    confirmation.addInt32(port);
    confirmation.addString("failed");
    
    sender.send(confirmation);
    
    return false;
}

/**
 * @brief Verifies that we actually have the port (works around JUCE bug)
 */
bool AIplayerAudioProcessor::verifyPortBinding(int port)
{
    // Try to create a test socket to verify the port is actually ours
    // This is a workaround for JUCE's OSC receiver bug where connect() returns true
    // even when the port is already in use
    
    // For now, we'll trust the connection and add more sophisticated verification later
    // A proper implementation would create a test UDP socket and try to bind to the same port
    
    // TODO: Implement proper port verification using platform-specific socket APIs
    
    return true; // Assume success for now
}
