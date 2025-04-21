// AIplayer/AIplayer/Tests/PluginProcessorTests.cpp
#include <juce_core/juce_core.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_osc/juce_osc.h> // Include OSC for testing message handling
#include <juce_unit_test/juce_unit_test.h>

// Include the processor header relative to the test file location
#include "../../Source/PluginProcessor.h"

//==============================================================================
class PluginProcessorTest : public juce::UnitTest
{
public:
    PluginProcessorTest() : juce::UnitTest ("AIplayerAudioProcessor Tests") {}

    void runTest() override
    {
        beginTest ("Initial Placeholder Test");
        expect (true); // Simple placeholder to ensure the test runner works

        // --- Add specific test sections below ---

        // --- Add specific test sections below ---

        beginTest ("APVTS Parameter Setup");
        testParameterSetup();

        beginTest ("OSC Parameter Set Handling");
        testOSCParameterHandling();

        beginTest ("Gain Processing");
        testGainProcessing();

        beginTest ("State Persistence");
        testStatePersistence();
    }

private:
    // --- Helper methods for tests ---

    // Example: Create a processor instance for testing
    std::unique_ptr<AIplayerAudioProcessor> createTestProcessor()
    {
        // JUCE plugins often need the message manager for async operations
        // Ensure it exists for the test environment
        juce::ScopedJuceInitialiser_GUI libraryInitialiser;
        return std::make_unique<AIplayerAudioProcessor>();
    }

    // --- Test implementation methods ---

    void testParameterSetup()
    {
        auto processor = createTestProcessor();
        expect (processor != nullptr);

        auto* gainParam = dynamic_cast<juce::AudioParameterFloat*>(processor->apvts.getParameter ("GAIN"));
        expect (gainParam != nullptr, "GAIN parameter should exist");

        // Check range, default value, etc.
        // Note: JUCE NormalisableRange stores start/end, not min/max if skewed, but for linear range they are the same.
        expectEquals (gainParam->range.start, -60.0f, "Gain start range should be -60.0f");
        expectEquals (gainParam->range.end, 0.0f, "Gain end range should be 0.0f");

        // Default value is 0.0dB. We need to check the *normalized* default value (0.0-1.0 range).
        // For a linear range from -60 to 0, 0dB corresponds to the maximum value, so normalized should be 1.0.
        float expectedDefaultNormalized = gainParam->convertTo0to1(0.0f); // Convert 0dB to normalized
        expectEquals(expectedDefaultNormalized, 1.0f, "Normalized value for 0dB should be 1.0f");
        expectEquals (gainParam->getDefaultValue(), expectedDefaultNormalized, "Gain default normalized value should correspond to 0dB");
        expectEquals (gainParam->getValue(), gainParam->getDefaultValue(), "Initial gain value should be default");
     }

    void testOSCParameterHandling()
    {
        auto processor = createTestProcessor();
        expect (processor != nullptr);

        auto* gainParam = dynamic_cast<juce::AudioParameterFloat*>(processor->apvts.getParameter ("GAIN"));
        expect (gainParam != nullptr);
        float initialNormalizedValue = gainParam->getValue();

        // 1. Test valid message
        juce::OSCMessage validMsg ("/aiplayer/set_parameter");
        validMsg.addString ("GAIN");
        validMsg.addFloat32 (-12.0f); // Value in dB
        processor->oscMessageReceived(validMsg);

        // Check if parameter value changed (use convertTo0to1 for comparison)
        float expectedNormalizedValue = gainParam->convertTo0to1(-12.0f);
        expect (gainParam->getValue() != initialNormalizedValue, "Gain value should have changed after valid OSC message");
        expectEquals (gainParam->getValue(), expectedNormalizedValue, "Gain value should be set correctly via OSC");

        // 2. Test invalid parameter ID
        float valueBeforeInvalidID = gainParam->getValue();
        juce::OSCMessage invalidIDMsg ("/aiplayer/set_parameter");
        invalidIDMsg.addString ("VOLUME"); // Incorrect ID
        invalidIDMsg.addFloat32 (-6.0f);
        processor->oscMessageReceived(invalidIDMsg);
        expectEquals (gainParam->getValue(), valueBeforeInvalidID, "Gain value should not change with invalid parameter ID");

        // 3. Test wrong argument types/count
        float valueBeforeInvalidArgs = gainParam->getValue();
        juce::OSCMessage invalidArgsMsg ("/aiplayer/set_parameter");
        invalidArgsMsg.addString ("GAIN");
        invalidArgsMsg.addInt32 (10); // Wrong type
        processor->oscMessageReceived(invalidArgsMsg);
        expectEquals (gainParam->getValue(), valueBeforeInvalidArgs, "Gain value should not change with invalid OSC arguments");

        juce::OSCMessage wrongCountMsg ("/aiplayer/set_parameter");
        wrongCountMsg.addString ("GAIN"); // Missing value
        processor->oscMessageReceived(wrongCountMsg);
        expectEquals (gainParam->getValue(), valueBeforeInvalidArgs, "Gain value should not change with wrong OSC argument count");
    }

    void testGainProcessing()
    {
        auto processor = createTestProcessor();
        expect (processor != nullptr);

        auto* gainParam = dynamic_cast<juce::AudioParameterFloat*>(processor->apvts.getParameter ("GAIN"));
        expect (gainParam != nullptr);

        int numSamples = 512;
        int numChannels = 2;
        juce::AudioBuffer<float> buffer (numChannels, numSamples);
        buffer.clear(); // Start with silence

        // Fill buffer with some value (e.g., 0.5)
        for (int chan = 0; chan < numChannels; ++chan)
            juce::FloatVectorOperations::fill (buffer.getWritePointer(chan), 0.5f, numSamples);

        juce::MidiBuffer midi; // Empty midi buffer

        // Test 1: Gain at 0dB (no change expected)
        gainParam->setValueNotifyingHost (gainParam->convertTo0to1 (0.0f));
        processor->prepareToPlay (44100.0, numSamples); // Prepare processor
        processor->processBlock (buffer, midi);
        // Check if buffer values are still approx 0.5
        expect (juce::approximatelyEqual (buffer.getSample(0, 0), 0.5f), "Gain at 0dB should not change sample value significantly");
        expect (juce::approximatelyEqual (buffer.getSample(1, numSamples / 2), 0.5f), "Gain at 0dB should not change sample value significantly");

        // Test 2: Gain at -6dB (values should be halved)
        // Reset buffer
        for (int chan = 0; chan < numChannels; ++chan)
            juce::FloatVectorOperations::fill (buffer.getWritePointer(chan), 0.5f, numSamples);

        gainParam->setValueNotifyingHost (gainParam->convertTo0to1 (-6.0f)); // Approx -6dB
        processor->processBlock (buffer, midi);
        float expectedValue = 0.5f * juce::Decibels::decibelsToGain (-6.0f);
        expect (juce::approximatelyEqual (buffer.getSample(0, 0), expectedValue), "Gain at -6dB should halve sample value");
        expect (juce::approximatelyEqual (buffer.getSample(1, numSamples / 2), expectedValue), "Gain at -6dB should halve sample value");

        // Test 3: Gain at -inf (-60dB in this case, effectively silence)
        // Reset buffer
        for (int chan = 0; chan < numChannels; ++chan)
            juce::FloatVectorOperations::fill (buffer.getWritePointer(chan), 0.5f, numSamples);

        gainParam->setValueNotifyingHost (gainParam->convertTo0to1 (-60.0f));
        processor->processBlock (buffer, midi);
        expect (juce::approximatelyEqual (buffer.getSample(0, 0), 0.0f), "Gain at -60dB should result in near silence");
        expect (juce::approximatelyEqual (buffer.getSample(1, numSamples / 2), 0.0f), "Gain at -60dB should result in near silence");
    }

    void testStatePersistence()
    {
        // Create processor 1, set a value
        auto processor1 = createTestProcessor();
        auto* gainParam1 = dynamic_cast<juce::AudioParameterFloat*>(processor1->apvts.getParameter ("GAIN"));
        expect (gainParam1 != nullptr);
        float testValueDb = -18.0f;
        float testNormalizedValue = gainParam1->convertTo0to1(testValueDb);
        gainParam1->setValueNotifyingHost(testNormalizedValue);

        // Get state
        juce::MemoryBlock stateBlock;
        processor1->getStateInformation(stateBlock);

        // Create processor 2, load state
        auto processor2 = createTestProcessor();
        processor2->setStateInformation(stateBlock.getData(), (int)stateBlock.getSize());

        // Check if processor 2 has the value from processor 1
        auto* gainParam2 = dynamic_cast<juce::AudioParameterFloat*>(processor2->apvts.getParameter ("GAIN"));
        expect (gainParam2 != nullptr);
        expectEquals (gainParam2->getValue(), testNormalizedValue, "State persistence should restore the correct parameter value");
    }

};

// This registers the test class with the JUCE framework.
static PluginProcessorTest pluginProcessorTest;