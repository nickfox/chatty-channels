/*
  ==============================================================================

    This file contains the basic framework code for a JUCE plugin processor.

  ==============================================================================
*/

#include "PluginProcessor.h"
#include "PluginEditor.h"
#include "Core/Constants.h"

namespace AIplayer {

//==============================================================================
juce::AudioProcessorValueTreeState::ParameterLayout AIplayerAudioProcessor::createParameterLayout()
{
    std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;

    // Add Gain parameter with a version hint using ParameterID
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("GAIN", 1),                          // Parameter ID with version hint
        "Gain",                                                // Parameter Name
        juce::NormalisableRange<float>(-60.0f, 0.0f, 0.1f),  // Range (-60dB to 0dB, 0.1 step)
        0.0f,                                                  // Default value
        "dB"                                                   // Unit Suffix
    ));

    return { params.begin(), params.end() };
}

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
                       ),
#else
     :
#endif
       apvts (*this, nullptr, "Parameters", createParameterLayout())
{
    // Generate unique instance ID
    tempInstanceID = juce::Uuid().toString();
    
    // Initialize components
    initializeComponents();
    
    // Setup parameters
    setupParameters();
    
    // Setup OSC communication
    setupOSCCommunication();
}

AIplayerAudioProcessor::~AIplayerAudioProcessor()
{
    // Stop services before destruction
    if (telemetryService)
        telemetryService->stopTelemetry();
    
    // Remove listeners
    if (oscManager)
    {
        oscManager->removeListener(this);
    }
    
    // Stop timer
    stopTimer();
    
    if (logger)
        logger->log(Logger::Level::Info, "--- AIplayer Plugin Shutting Down ---");
}

//==============================================================================
/**
 * @brief Initializes all plugin components in proper dependency order
 * 
 * @details This method performs a multi-stage initialization sequence:
 * 1. Creates log directory and initializes logging system
 * 2. Initializes audio processing components (AudioMetrics, ToneGenerator, FrequencyAnalyzer)
 * 3. Initializes communication components (OSCManager, PortManager, TelemetryService)
 * 
 * The initialization order is critical due to component dependencies:
 * - Logger must be initialized first as all other components depend on it
 * - Audio components are independent and can be initialized in parallel
 * - Communication components depend on audio components for data sources
 * 
 * @note This method creates the log directory if it doesn't exist and handles
 *       file system errors gracefully. The FrequencyAnalyzer is configured with
 *       optimized settings (1024 FFT samples, 10Hz update rate) for real-time performance.
 * 
 * @warning This method must be called before any audio processing begins.
 *          Failure to initialize properly will result in componentsInitialized
 *          remaining false, causing processBlock to return early.
 */
void AIplayerAudioProcessor::initializeComponents()
{
    // Initialize logger first - all other components depend on it
    juce::File logDirectory = juce::File::getSpecialLocation(juce::File::userHomeDirectory)
                                .getChildFile("Documents")
                                .getChildFile("chatty-channel")
                                .getChildFile("logs");

    if (!logDirectory.exists())
        logDirectory.createDirectory();

    juce::File logFile = logDirectory.getChildFile("AIplayer.log");
    logger = std::make_unique<Logger>(logFile);
    
    logger->log(Logger::Level::Info, "==================================================================");
    logger->log(Logger::Level::Info, "AIplayer PLUGIN WITH REFACTORED ARCHITECTURE STARTING!");
    logger->log(Logger::Level::Info, "Plugin Instance tempInstanceID: " + tempInstanceID);
    logger->log(Logger::Level::Info, "==================================================================");
    
    // Initialize audio processing components - order independent
    audioMetrics = std::make_unique<AudioMetrics>();
    toneGenerator = std::make_unique<CalibrationToneGenerator>();
    
    // Initialize frequency analyzer with optimized real-time configuration
    FrequencyAnalyzer::Config fftConfig;
    fftConfig.fftOrder = 10;          // 1024 samples for good frequency resolution
    fftConfig.updateRateHz = 10;      // 10 Hz update rate balances accuracy vs CPU usage
    fftConfig.enableAWeighting = false; // Disabled for raw frequency analysis
    fftConfig.autoStart = true;       // Start analysis immediately
    frequencyAnalyzer = std::make_unique<FrequencyAnalyzer>(*logger, fftConfig);
    
    // Initialize communication components - depend on audio components for data
    oscManager = std::make_unique<OSCManager>(*logger);
    portManager = std::make_unique<PortManager>(*oscManager, *logger);
    telemetryService = std::make_unique<TelemetryService>(*audioMetrics, *frequencyAnalyzer, *oscManager, *logger);
    
    componentsInitialized = true;
}

void AIplayerAudioProcessor::setupOSCCommunication()
{
    // Register as listener for OSC events
    oscManager->addListener(this);
    
    // Connect to ChattyChannels
    if (!oscManager->connect(Constants::OSC_HOST, Constants::OSC_CHATTY_CHANNELS_PORT))
    {
        logger->log(Logger::Level::Error, "Failed to connect OSC sender to ChattyChannels");
        // Start timer to retry connection
        startTimer(2000); // Retry every 2 seconds
    }
    else
    {
        logger->log(Logger::Level::Info, "Successfully connected to ChattyChannels");
        
        // Bind to ephemeral port first for receiving responses
        int ephemeralPort = 0;
        for (int port = 50000; port < 60000; port += 100)
        {
            if (oscManager->bindReceiver(port))
            {
                ephemeralPort = port;
                logger->log(Logger::Level::Info, "Bound to ephemeral port " + juce::String(port));
                break;
            }
        }
        
        if (ephemeralPort > 0)
        {
            // Request port assignment
            portManager->requestPort(tempInstanceID, ephemeralPort);
        }
        else
        {
            logger->log(Logger::Level::Error, "Failed to bind to ephemeral port");
        }
    }
}

void AIplayerAudioProcessor::setupParameters()
{
    // Get the raw pointer to the gain parameter after APVTS initialization
    gainParameter = apvts.getRawParameterValue("GAIN");
    if (gainParameter)
        logger->log(Logger::Level::Info, "Gain parameter pointer acquired.");
    else
        logger->log(Logger::Level::Error, "Failed to acquire Gain parameter pointer.");
}

//==============================================================================
void AIplayerAudioProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    if (!componentsInitialized)
        return;
        
    logger->log(Logger::Level::Info, "prepareToPlay called. Sample Rate: " + 
                juce::String(sampleRate) + ", Samples Per Block: " + juce::String(samplesPerBlock));
    
    // Prepare audio components
    toneGenerator->prepare(sampleRate, samplesPerBlock);
    
    logger->log(Logger::Level::Info, "Audio components prepared for playback");
}

void AIplayerAudioProcessor::releaseResources()
{
    if (logger)
        logger->log(Logger::Level::Info, "releaseResources called.");
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
 * @brief Core audio processing method called by the host for each audio block
 * 
 * @details This method implements the main audio processing pipeline:
 * 1. Validates component initialization and clears unused output channels
 * 2. Applies gain parameter to input audio (with dB to linear conversion)
 * 3. Processes calibration tone generation (mixes tone into audio if active)
 * 4. Updates audio metrics (RMS, peak levels) for telemetry
 * 5. Feeds processed audio to frequency analyzer for FFT and band analysis
 * 
 * The processing order ensures that all components receive the final processed
 * audio signal including gain adjustment and calibration tones.
 * 
 * @param buffer Audio buffer containing input samples, modified in-place
 * @param midiMessages MIDI buffer (ignored as this is an audio effect)
 * 
 * @note This method is called from the audio thread and must be real-time safe.
 *       No allocations, file I/O, or blocking operations are permitted.
 *       ScopedNoDenormals prevents performance degradation from denormal numbers.
 * 
 * @warning If componentsInitialized is false, processing is skipped entirely
 *          to prevent crashes from uninitialized components.
 * 
 * @see initializeComponents() for initialization requirements
 * @see AudioMetrics::updateMetrics() for RMS calculation details
 * @see FrequencyAnalyzer::processBlock() for FFT processing
 */
void AIplayerAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    // Skip processing if components not properly initialized
    if (!componentsInitialized)
        return;
        
    juce::ignoreUnused (midiMessages);
    juce::ScopedNoDenormals noDenormals; // Prevent denormal performance issues
    
    auto totalNumInputChannels  = getTotalNumInputChannels();
    auto totalNumOutputChannels = getTotalNumOutputChannels();

    // Clear extra output channels that don't have corresponding inputs
    for (auto i = totalNumInputChannels; i < totalNumOutputChannels; ++i)
        buffer.clear (i, 0, buffer.getNumSamples());

    // Apply gain parameter with thread-safe atomic access
    if (gainParameter)
    {
        float currentGainDb = gainParameter->load();
        float gainFactor = juce::Decibels::decibelsToGain(currentGainDb);

        // Apply gain to all input channels
        for (int channel = 0; channel < totalNumInputChannels; ++channel)
        {
            buffer.applyGain(channel, 0, buffer.getNumSamples(), gainFactor);
        }
    }
    
    // Process calibration tone if enabled (mixes tone into existing audio)
    toneGenerator->processBlock(buffer);
    
    // Update audio metrics with the final processed signal
    audioMetrics->updateMetrics(buffer);
    
    // Feed processed audio to frequency analyzer for spectral analysis
    frequencyAnalyzer->processBlock(buffer, getSampleRate());
}

//==============================================================================
bool AIplayerAudioProcessor::hasEditor() const
{
    return true;
}

juce::AudioProcessorEditor* AIplayerAudioProcessor::createEditor()
{
    return new AIplayerAudioProcessorEditor (*this);
}

//==============================================================================
void AIplayerAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    try
    {
        auto state = apvts.copyState();
        std::unique_ptr<juce::XmlElement> xml (state.createXml());
        if (xml != nullptr)
        {
            copyXmlToBinary (*xml, destData);
            if (logger)
                logger->log(Logger::Level::Info, "Plugin state saved.");
        }
        else
        {
            if (logger)
                logger->log(Logger::Level::Error, "Failed to create XML from state for saving.");
        }
    }
    catch (const std::exception& e)
    {
        if (logger)
            logger->log(Logger::Level::Error, "Exception in getStateInformation: " + juce::String(e.what()));
    }
}

void AIplayerAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    try
    {
        std::unique_ptr<juce::XmlElement> xmlState (getXmlFromBinary (data, sizeInBytes));

        if (xmlState != nullptr)
        {
            if (xmlState->hasTagName (apvts.state.getType()))
            {
                apvts.replaceState (juce::ValueTree::fromXml (*xmlState));
                if (logger)
                    logger->log(Logger::Level::Info, "Plugin state restored.");
            }
            else
            {
                if (logger)
                    logger->log(Logger::Level::Error, "Failed to restore state - XML tag mismatch.");
            }
        }
        else
        {
            if (logger)
                logger->log(Logger::Level::Error, "Failed to restore state - Could not get XML from binary data.");
        }
    }
    catch (const std::exception& e)
    {
        if (logger)
            logger->log(Logger::Level::Error, "Exception in setStateInformation: " + juce::String(e.what()));
    }
}

//==============================================================================
// Basic plugin info methods
const juce::String AIplayerAudioProcessor::getName() const
{
    return "AIplayer";
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
// Public interface methods
void AIplayerAudioProcessor::sendChatMessage(const juce::String& message)
{
    if (oscManager)
    {
        // For now, using a placeholder instance ID
        int placeholderInstanceID = 1;
        oscManager->sendChatMessage(placeholderInstanceID, message);
    }
}

//==============================================================================
// OSCManager::Listener callbacks
void AIplayerAudioProcessor::handleTrackAssignment(const juce::String& trackID)
{
    logicTrackUUID = trackID;
    logger->log(Logger::Level::Info, "Plugin " + tempInstanceID + 
                " successfully assigned LogicTrackUUID: " + logicTrackUUID);
    
    // Update telemetry service with the track ID
    if (telemetryService)
    {
        telemetryService->setTrackID(trackID);
        telemetryService->setInstanceID(tempInstanceID);
    }
    
    // Send confirmation back to ChattyChannels
    if (oscManager)
    {
        oscManager->sendUUIDConfirmation(tempInstanceID, logicTrackUUID);
    }
    
    // Start telemetry if we have a port
    if (portManager && portManager->isBound() && !logicTrackUUID.isEmpty())
    {
        telemetryService->startTelemetry(Constants::TELEMETRY_RATE_HZ);
    }
}

void AIplayerAudioProcessor::handlePortAssignment(int port, const juce::String& status)
{
    logger->log(Logger::Level::Info, "Received port assignment: port=" + 
                juce::String(port) + ", status=" + status);
    
    if (portManager)
    {
        portManager->handlePortAssignment(port, status, tempInstanceID);
        
        // If successfully bound and we have a track ID, start telemetry
        if (portManager->isBound() && !logicTrackUUID.isEmpty())
        {
            telemetryService->startTelemetry(Constants::TELEMETRY_RATE_HZ);
        }
    }
}

void AIplayerAudioProcessor::handleParameterChange(const juce::String& paramID, float value)
{
    logger->log(Logger::Level::Info, "Received parameter set request via OSC: ParamID=" + 
                paramID + ", Value=" + juce::String(value));

    if (auto* parameter = apvts.getParameter(paramID))
    {
        float normalizedValue = parameter->convertTo0to1(value);
        normalizedValue = juce::jlimit(0.0f, 1.0f, normalizedValue);
        parameter->setValueNotifyingHost(normalizedValue);
        
        logger->log(Logger::Level::Info, "Parameter " + paramID + " set to " + 
                    juce::String(value) + " (Normalized: " + juce::String(normalizedValue) + ")");
    }
    else
    {
        logger->log(Logger::Level::Error, "Parameter with ID '" + paramID + "' not found.");
    }
}

void AIplayerAudioProcessor::handleRMSQuery(const juce::String& queryID)
{
    if (audioMetrics && oscManager)
    {
        float currentRMS = audioMetrics->getCurrentRMS();
        oscManager->sendRMSResponse(queryID, tempInstanceID, currentRMS);
    }
}

void AIplayerAudioProcessor::handleToneControl(bool start, float frequency, float amplitude)
{
    if (start)
    {
        logger->log(Logger::Level::Info, "Received start_tone command: freq=" + 
                    juce::String(frequency) + "Hz, amp=" + juce::String(amplitude) + "dB");
        
        if (toneGenerator)
        {
            toneGenerator->setTone(frequency, amplitude);
            toneGenerator->startTone();
            
            // Send confirmation
            if (oscManager)
            {
                oscManager->sendToneStarted(tempInstanceID, frequency);
            }
        }
    }
    else
    {
        logger->log(Logger::Level::Info, "Received stop_tone command");
        
        if (toneGenerator)
        {
            toneGenerator->stopTone();
            
            // Send confirmation
            if (oscManager)
            {
                oscManager->sendToneStopped(tempInstanceID);
            }
        }
    }
}

void AIplayerAudioProcessor::handleChatResponse(const juce::String& response)
{
    logger->log(Logger::Level::Info, "Received chat response via OSC: " + response);

    // Safely get the active editor and update it
    juce::WeakReference<AIplayerAudioProcessor> weakSelf = this;
    juce::MessageManager::callAsync([weakSelf, response]() {
        if (weakSelf == nullptr) return;

        if (auto* editor = weakSelf->getActiveEditor())
        {
            if (auto* aiEditor = dynamic_cast<AIplayerAudioProcessorEditor*>(editor))
            {
                aiEditor->displayReceivedMessage(response);
            }
        }
    });
}



//==============================================================================
// Timer callback for initialization retry
void AIplayerAudioProcessor::timerCallback()
{
    if (!oscManager->isSenderConnected())
    {
        logger->log(Logger::Level::Info, "Retrying OSC connection...");
        
        if (oscManager->connect(Constants::OSC_HOST, Constants::OSC_CHATTY_CHANNELS_PORT))
        {
            logger->log(Logger::Level::Info, "Successfully reconnected to ChattyChannels");
            stopTimer();
            
            // Bind to ephemeral port and request port assignment
            int ephemeralPort = 0;
            for (int port = 50000; port < 60000; port += 100)
            {
                if (oscManager->bindReceiver(port))
                {
                    ephemeralPort = port;
                    logger->log(Logger::Level::Info, "Bound to ephemeral port " + juce::String(port));
                    break;
                }
            }
            
            if (ephemeralPort > 0 && portManager)
            {
                portManager->requestPort(tempInstanceID, ephemeralPort);
            }
        }
        else
        {
            initRetryCount++;
            if (initRetryCount >= maxInitRetries)
            {
                logger->log(Logger::Level::Error, "Max connection retries reached. Unable to connect to ChattyChannels.");
                stopTimer();
            }
        }
    }
}

} // namespace AIplayer

//==============================================================================
// This creates new instances of the plugin..
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new AIplayer::AIplayerAudioProcessor();
}
