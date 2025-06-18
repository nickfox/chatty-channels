/*
  ==============================================================================

    TelemetryIntegrationTests.cpp
    Created: 18 Jun 2025
    Author:  Nick Fox

    Integration tests for telemetry system with FFT data.

  ==============================================================================
*/

#include <JuceHeader.h>
#include "../Audio/AudioMetrics.h"
#include "../Audio/FrequencyAnalyzer.h"
#include "../Communication/TelemetryService.h"
#include "../Communication/OSCManager.h"
#include "../Core/Logger.h"
#include "../Models/TelemetryData.h"

namespace AIplayer {

class MockOSCReceiver : public juce::OSCReceiver::Listener<juce::OSCReceiver::MessageLoopCallback>
{
public:
    struct ReceivedMessage
    {
        juce::String address;
        juce::String trackID;
        float rmsValue;
        std::array<float, 4> bandEnergies;
        juce::Time timestamp;
    };
    
    MockOSCReceiver()
    {
        // Listen on a test port
        if (!receiver.connect(9002))
        {
            DBG("Failed to bind OSC receiver to port 9002");
        }
        receiver.addListener(this);
    }
    
    ~MockOSCReceiver()
    {
        receiver.removeListener(this);
        receiver.disconnect();
    }
    
    void oscMessageReceived(const juce::OSCMessage& message) override
    {
        ReceivedMessage msg;
        msg.address = message.getAddressPattern().toString();
        msg.timestamp = juce::Time::getCurrentTime();
        
        if (msg.address == "/aiplayer/telemetry" && message.size() >= 6)
        {
            msg.trackID = message[0].getString();
            msg.rmsValue = message[1].getFloat32();
            msg.bandEnergies[0] = message[2].getFloat32();
            msg.bandEnergies[1] = message[3].getFloat32();
            msg.bandEnergies[2] = message[4].getFloat32();
            msg.bandEnergies[3] = message[5].getFloat32();
            
            const juce::ScopedLock sl(lock);
            receivedMessages.add(msg);
        }
    }
    
    std::vector<ReceivedMessage> getMessages()
    {
        const juce::ScopedLock sl(lock);
        std::vector<ReceivedMessage> result;
        for (auto& msg : receivedMessages)
        {
            result.push_back(msg);
        }
        return result;
    }
    
    void clearMessages()
    {
        const juce::ScopedLock sl(lock);
        receivedMessages.clear();
    }
    
private:
    juce::OSCReceiver receiver;
    juce::Array<ReceivedMessage> receivedMessages;
    juce::CriticalSection lock;
};

class TelemetryIntegrationTests : public juce::UnitTest
{
public:
    TelemetryIntegrationTests() : UnitTest("Telemetry Integration Tests", "AIplayer") {}
    
    void runTest() override
    {
        testTelemetryDataStructure();
        testTelemetryServiceWithFFT();
        testOSCTelemetryFormat();
        testEndToEndTelemetryFlow();
        testBackwardCompatibility();
    }
    
private:
    void testTelemetryDataStructure()
    {
        beginTest("TelemetryData Structure with Band Energies");
        
        TelemetryData data;
        data.trackID = "TR1";
        data.instanceID = "test-uuid-123";
        data.rmsLevel = 0.5f;
        data.peakLevel = 0.7f;
        data.bandEnergies[0] = -10.0f;
        data.bandEnergies[1] = -20.0f;
        data.bandEnergies[2] = -30.0f;
        data.bandEnergies[3] = -40.0f;
        
        expect(data.isValid());
        
        juce::String str = data.toString();
        expect(str.contains("TR1"));
        expect(str.contains("-10.0"));
        expect(str.contains("-20.0"));
        expect(str.contains("-30.0"));
        expect(str.contains("-40.0"));
        
        logMessage("TelemetryData string: " + str);
    }
    
    void testTelemetryServiceWithFFT()
    {
        beginTest("TelemetryService with Frequency Analyzer");
        
        // Create test log file
        juce::File tempDir = juce::File::getSpecialLocation(juce::File::tempDirectory)
                                .getChildFile("AIplayerTest");
        tempDir.createDirectory();
        juce::File logFile = tempDir.getChildFile("test.log");
        
        // Create components
        Logger logger(logFile);
        AudioMetrics audioMetrics;
        FrequencyAnalyzer::Config fftConfig;
        fftConfig.fftOrder = 9; // 512 samples for faster testing
        fftConfig.updateRateHz = 100; // Fast updates for testing
        fftConfig.autoStart = false;
        FrequencyAnalyzer frequencyAnalyzer(logger, fftConfig);
        OSCManager oscManager(logger);
        
        // Connect to test port
        oscManager.connect("127.0.0.1", 9002);
        
        // Create telemetry service
        TelemetryService telemetryService(audioMetrics, frequencyAnalyzer, oscManager, logger);
        telemetryService.setTrackID("TR1");
        telemetryService.setInstanceID("test-instance");
        
        // Generate test audio with known frequency content
        juce::AudioBuffer<float> buffer(2, 512);
        const float sampleRate = 44100.0f;
        
        // Mix of frequencies for different bands
        for (int i = 0; i < 512; ++i)
        {
            float t = i / sampleRate;
            float sample = 0.0f;
            
            // Low frequency (100 Hz)
            sample += 0.5f * std::sin(2.0f * juce::MathConstants<float>::pi * 100.0f * t);
            
            // Mid frequency (1000 Hz)
            sample += 0.3f * std::sin(2.0f * juce::MathConstants<float>::pi * 1000.0f * t);
            
            // High frequency (5000 Hz)
            sample += 0.1f * std::sin(2.0f * juce::MathConstants<float>::pi * 5000.0f * t);
            
            buffer.setSample(0, i, sample);
            buffer.setSample(1, i, sample);
        }
        
        // Process audio through the chain
        audioMetrics.updateMetrics(buffer);
        frequencyAnalyzer.processBlock(buffer, sampleRate);
        
        // Force FFT computation
        frequencyAnalyzer.computeNow();
        
        // Collect telemetry data
        telemetryService.sendTelemetryNow();
        
        // Wait a bit for async operations
        juce::Thread::sleep(50);
        
        // Check that band energies are reasonable
        auto bandEnergies = frequencyAnalyzer.getBandEnergies();
        logMessage("Band energies from analyzer:");
        logMessage("  Low: " + juce::String(bandEnergies[0], 1) + " dB");
        logMessage("  Low-Mid: " + juce::String(bandEnergies[1], 1) + " dB");
        logMessage("  High-Mid: " + juce::String(bandEnergies[2], 1) + " dB");
        logMessage("  High: " + juce::String(bandEnergies[3], 1) + " dB");
        
        // Low band should have highest energy due to 100 Hz component
        expect(bandEnergies[0] > bandEnergies[3], "Low band should be louder than high");
        
        // Cleanup
        tempDir.deleteRecursively();
    }
    
    void testOSCTelemetryFormat()
    {
        beginTest("OSC Telemetry Message Format");
        
        // Create mock receiver
        MockOSCReceiver mockReceiver;
        
        // Create minimal test setup
        juce::File tempLog = juce::File::getSpecialLocation(juce::File::tempDirectory)
                                .getChildFile("test_osc.log");
        Logger logger(tempLog);
        OSCManager oscManager(logger);
        
        // Connect to mock receiver
        expect(oscManager.connect("127.0.0.1", 9002), "Should connect to mock receiver");
        
        // Create and send telemetry data
        TelemetryData data;
        data.trackID = "TR1";
        data.instanceID = "test-123";
        data.rmsLevel = 0.707f;
        data.bandEnergies[0] = -6.0f;
        data.bandEnergies[1] = -12.0f;
        data.bandEnergies[2] = -18.0f;
        data.bandEnergies[3] = -24.0f;
        
        bool sent = oscManager.sendTelemetry(data);
        expect(sent, "Telemetry should be sent successfully");
        
        // Wait for message to arrive
        juce::Thread::sleep(100);
        
        // Check received messages
        auto messages = mockReceiver.getMessages();
        expect(messages.size() > 0, "Should receive at least one message");
        
        if (messages.size() > 0)
        {
            // Find the telemetry message
            bool foundTelemetry = false;
            for (const auto& msg : messages)
            {
                if (msg.address == "/aiplayer/telemetry")
                {
                    foundTelemetry = true;
                    expectEquals(msg.trackID, juce::String("TR1"));
                    expectWithinAbsoluteError(msg.rmsValue, 0.707f, 0.001f);
                    expectWithinAbsoluteError(msg.bandEnergies[0], -6.0f, 0.1f);
                    expectWithinAbsoluteError(msg.bandEnergies[1], -12.0f, 0.1f);
                    expectWithinAbsoluteError(msg.bandEnergies[2], -18.0f, 0.1f);
                    expectWithinAbsoluteError(msg.bandEnergies[3], -24.0f, 0.1f);
                    
                    logMessage("Received telemetry message verified successfully");
                    break;
                }
            }
            expect(foundTelemetry, "Should find telemetry message");
        }
        
        // Cleanup
        tempLog.deleteFile();
    }
    
    void testEndToEndTelemetryFlow()
    {
        beginTest("End-to-End Telemetry Flow with FFT");
        
        // This test simulates the complete flow from audio input to OSC output
        MockOSCReceiver mockReceiver;
        mockReceiver.clearMessages();
        
        // Create full component chain
        juce::File tempDir = juce::File::getSpecialLocation(juce::File::tempDirectory)
                                .getChildFile("AIplayerE2E");
        tempDir.createDirectory();
        Logger logger(tempDir.getChildFile("e2e.log"));
        
        AudioMetrics audioMetrics;
        FrequencyAnalyzer::Config fftConfig;
        fftConfig.fftOrder = 10;
        fftConfig.updateRateHz = 50;
        fftConfig.autoStart = true;
        FrequencyAnalyzer frequencyAnalyzer(logger, fftConfig);
        
        OSCManager oscManager(logger);
        oscManager.connect("127.0.0.1", 9002);
        
        TelemetryService telemetryService(audioMetrics, frequencyAnalyzer, oscManager, logger);
        telemetryService.setTrackID("TR1");
        telemetryService.setInstanceID("e2e-test");
        telemetryService.startTelemetry(50); // 50 Hz for testing
        
        // Simulate processing audio blocks
        const int numBlocks = 20;
        const int blockSize = 512;
        const float sampleRate = 44100.0f;
        
        for (int block = 0; block < numBlocks; ++block)
        {
            juce::AudioBuffer<float> buffer(2, blockSize);
            
            // Generate different content for each block
            for (int i = 0; i < blockSize; ++i)
            {
                float t = (block * blockSize + i) / sampleRate;
                
                // Sweep frequency over time
                float freq = 100.0f + 1000.0f * (block / float(numBlocks));
                float sample = 0.5f * std::sin(2.0f * juce::MathConstants<float>::pi * freq * t);
                
                buffer.setSample(0, i, sample);
                buffer.setSample(1, i, sample);
            }
            
            // Process through the chain
            audioMetrics.updateMetrics(buffer);
            frequencyAnalyzer.processBlock(buffer, sampleRate);
            
            // Small delay between blocks
            juce::Thread::sleep(20);
        }
        
        // Stop telemetry and wait for final messages
        telemetryService.stopTelemetry();
        juce::Thread::sleep(100);
        
        // Verify messages were received
        auto messages = mockReceiver.getMessages();
        int telemetryCount = 0;
        int legacyCount = 0;
        
        for (const auto& msg : messages)
        {
            if (msg.address == "/aiplayer/telemetry")
            {
                telemetryCount++;
                expect(msg.trackID == "TR1");
                expect(msg.rmsValue > 0.0f);
                
                // At least one band should have energy
                bool hasEnergy = false;
                for (int i = 0; i < 4; ++i)
                {
                    if (msg.bandEnergies[i] > -60.0f)
                    {
                        hasEnergy = true;
                        break;
                    }
                }
                expect(hasEnergy, "Should have energy in at least one band");
            }
            else if (msg.address == "/aiplayer/rms")
            {
                legacyCount++;
            }
        }
        
        logMessage("Received " + juce::String(telemetryCount) + " telemetry messages");
        logMessage("Received " + juce::String(legacyCount) + " legacy RMS messages");
        
        expect(telemetryCount > 0, "Should receive telemetry messages");
        expect(legacyCount > 0, "Should receive legacy messages for compatibility");
        
        // Cleanup
        tempDir.deleteRecursively();
    }
    
    void testBackwardCompatibility()
    {
        beginTest("Backward Compatibility - Legacy RMS Messages");
        
        MockOSCReceiver mockReceiver;
        mockReceiver.clearMessages();
        
        juce::File tempLog = juce::File::getSpecialLocation(juce::File::tempDirectory)
                                .getChildFile("compat.log");
        Logger logger(tempLog);
        OSCManager oscManager(logger);
        oscManager.connect("127.0.0.1", 9002);
        
        // Send telemetry with track ID (should send both formats)
        TelemetryData data;
        data.trackID = "TR1";
        data.instanceID = "compat-test";
        data.rmsLevel = 0.5f;
        data.bandEnergies[0] = -10.0f;
        data.bandEnergies[1] = -15.0f;
        data.bandEnergies[2] = -20.0f;
        data.bandEnergies[3] = -25.0f;
        
        oscManager.sendTelemetry(data);
        juce::Thread::sleep(50);
        
        auto messages = mockReceiver.getMessages();
        
        // Should have both new telemetry and legacy RMS
        bool hasNewFormat = false;
        bool hasLegacyFormat = false;
        
        for (const auto& msg : messages)
        {
            if (msg.address == "/aiplayer/telemetry")
            {
                hasNewFormat = true;
                expect(msg.bandEnergies[0] != 0.0f, "Should have band energy data");
            }
            else if (msg.address == "/aiplayer/rms")
            {
                hasLegacyFormat = true;
                expectEquals(msg.trackID, juce::String("TR1"));
                expectWithinAbsoluteError(msg.rmsValue, 0.5f, 0.001f);
            }
        }
        
        expect(hasNewFormat, "Should send new telemetry format");
        expect(hasLegacyFormat, "Should send legacy RMS format for compatibility");
        
        // Cleanup
        tempLog.deleteFile();
    }
};

static TelemetryIntegrationTests telemetryIntegrationTests;

} // namespace AIplayer