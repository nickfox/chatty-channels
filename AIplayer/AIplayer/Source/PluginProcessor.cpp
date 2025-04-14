/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin processor.

  ==============================================================================
*/

#include "PluginProcessor.h"
#include "PluginEditor.h"

#include <juce_core/juce_core.h> // Needed for FileOutputStream, Time, etc.

//==============================================================================
AIplayerAudioProcessor::AIplayerAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
     : AudioProcessor (BusesProperties()
                     #if ! JucePlugin_IsMidiEffect
                      #if ! JucePlugin_IsSynth
                       .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                      #endif
                       .withOutput ("Output", juce::AudioChannelSet::stereo(), true)
                     #endif
                       )
#endif
{
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
}

AIplayerAudioProcessor::~AIplayerAudioProcessor()
{
    // logStream unique_ptr will automatically delete the stream when processor is destroyed
}

//==============================================================================
const juce::String AIplayerAudioProcessor::getName() const
{
    return JucePlugin_Name;
}

bool AIplayerAudioProcessor::acceptsMidi() const
{
   #if JucePlugin_WantsMidiInput
    return true;
   #else
    return false;
   #endif
}

bool AIplayerAudioProcessor::producesMidi() const
{
   #if JucePlugin_ProducesMidiOutput
    return true;
   #else
    return false;
   #endif
}

bool AIplayerAudioProcessor::isMidiEffect() const
{
   #if JucePlugin_IsMidiEffect
    return true;
   #else
    return false;
   #endif
}

double AIplayerAudioProcessor::getTailLengthSeconds() const
{
    return 0.0;
}

int AIplayerAudioProcessor::getNumPrograms()
{
    return 1;   // NB: some hosts don't cope very well if you tell them there are 0 programs,
                // so this should be at least 1, even if you're not really implementing programs.
}

int AIplayerAudioProcessor::getCurrentProgram()
{
    return 0;
}

void AIplayerAudioProcessor::setCurrentProgram (int index)
{
    juce::ignoreUnused (index);
}

const juce::String AIplayerAudioProcessor::getProgramName (int index)
{
    juce::ignoreUnused (index);
    return {};
}

void AIplayerAudioProcessor::changeProgramName (int index, const juce::String& newName)
{
    juce::ignoreUnused (index, newName);
}

//==============================================================================
void AIplayerAudioProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    // Use this method as the place to do any pre-playback
    // initialisation that you need..
    juce::ignoreUnused (sampleRate, samplesPerBlock);
}

void AIplayerAudioProcessor::releaseResources()
{
    // When playback stops, you can use this as an opportunity to free up any
    // spare memory, etc.
}

#ifndef JucePlugin_PreferredChannelConfigurations
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

void AIplayerAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    juce::ignoreUnused (midiMessages);
    juce::ScopedNoDenormals noDenormals;
    auto totalNumInputChannels  = getTotalNumInputChannels();
    auto totalNumOutputChannels = getTotalNumOutputChannels();

    // In case we have more outputs than inputs, this code clears any output
    // channels that didn't contain input data, (because these aren't
    // guaranteed to be empty - they may contain garbage).
    // This is here to avoid people getting screaming feedback
    // when they first compile a plugin, but obviously you don't need to keep
    // this code if your algorithm always overwrites all the output channels.
    for (auto i = totalNumInputChannels; i < totalNumOutputChannels; ++i)
        buffer.clear (i, 0, buffer.getNumSamples());

    // This is the place where you'd normally do the guts of your plugin's
    // audio processing...
    // Make sure to reset the state if your inner loop is processing
    // the samples and the outer loop is handling the channels.
    // Alternatively, you can process the samples with the channels
    // interleaved by keeping the same state.
    for (int channel = 0; channel < totalNumInputChannels; ++channel)
    {
        auto* channelData = buffer.getWritePointer (channel);
        juce::ignoreUnused (channelData); // Avoid unused variable warning

        // ..do something to the data...
    }
}

//==============================================================================
bool AIplayerAudioProcessor::hasEditor() const
{
    return true; // (change this to false if you choose to not supply an editor)
}

juce::AudioProcessorEditor* AIplayerAudioProcessor::createEditor()
{
    return new AIplayerAudioProcessorEditor (*this);
}

//==============================================================================
void AIplayerAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    // You should use this method to store your parameters in the memory block.
    // You could do that either as raw data, or use the XML or ValueTree classes
    // as intermediaries to make it easy to save and load complex data.
    juce::ignoreUnused (destData);
}

void AIplayerAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    // You should use this method to restore your parameters from this memory block,
    // whose contents will have been created by the getStateInformation() call.
    juce::ignoreUnused (data, sizeInBytes);
}

//==============================================================================
//==============================================================================
// Custom Public Methods Implementation
void AIplayerAudioProcessor::sendChatMessage(const juce::String& message)
{
    // TODO: Add instance ID logic here if needed
    // For now, using a fixed address pattern
    int placeholderInstanceID = 1; // Placeholder - needs proper instance management later
    sendOSC("/aiplayer/chat/request", placeholderInstanceID, message);
}

//==============================================================================
// OSC Message Handling
/**
    Callback function that gets invoked when an OSC message is received.
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
    // TODO: Add handling for other incoming OSC messages if needed
}

//==============================================================================
// Custom Internal Methods Implementation (Logging)
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
// Custom Internal Methods Implementation (OSC Sending)
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
// This creates new instances of the plugin..
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new AIplayerAudioProcessor();
}
