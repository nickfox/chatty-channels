/*
  ==============================================================================

    FFTProcessorTests.cpp
    Created: 18 Jun 2025
    Author:  Nick Fox

    Unit tests for FFT processing components.

  ==============================================================================
*/

#include <JuceHeader.h>
#include "../Audio/FFTProcessor.h"
#include "../Audio/BandEnergyAnalyzer.h"
#include "../Audio/FrequencyAnalyzer.h"
#include "../Core/Logger.h"
#include <cmath>

namespace AIplayer {

class FFTProcessorTests : public juce::UnitTest
{
public:
    FFTProcessorTests() : UnitTest("FFT Processor Tests", "AIplayer") {}
    
    void runTest() override
    {
        testFFTProcessorBasics();
        testSineWaveFFT();
        testCircularBuffer();
        testFFTComputationTiming();
        testBandEnergyAnalyzer();
        testFrequencyBandMapping();
        testKickDrumSimulation();
        testPerformance();
    }
    
private:
    void testFFTProcessorBasics()
    {
        beginTest("FFT Processor Construction and Basic Properties");
        
        FFTProcessor processor(10); // 1024 samples
        
        expect(processor.getFFTSize() == 1024);
        expect(processor.getMagnitudeSpectrumSize() == 512);
        expect(!processor.isFFTReady());
        
        // Test with different FFT orders
        FFTProcessor smallProcessor(8); // 256 samples
        expect(smallProcessor.getFFTSize() == 256);
        
        FFTProcessor largeProcessor(12); // 4096 samples
        expect(largeProcessor.getFFTSize() == 4096);
    }
    
    void testSineWaveFFT()
    {
        beginTest("FFT of Single Sine Wave");
        
        const int fftOrder = 10;
        const int fftSize = 1 << fftOrder;
        const double sampleRate = 44100.0;
        const float testFrequency = 1000.0f; // 1 kHz
        
        FFTProcessor processor(fftOrder);
        
        // Generate sine wave
        juce::AudioBuffer<float> buffer(1, fftSize);
        for (int i = 0; i < fftSize; ++i)
        {
            float sample = std::sin(2.0f * juce::MathConstants<float>::pi * 
                                  testFrequency * i / sampleRate);
            buffer.setSample(0, i, sample);
        }
        
        // Process audio
        processor.processAudioBlock(buffer, sampleRate);
        
        // Compute FFT
        bool computed = processor.computeFFT();
        expect(computed, "FFT computation should succeed");
        expect(processor.isFFTReady());
        
        // Check magnitude spectrum
        const float* magnitudes = processor.getMagnitudeSpectrum();
        const float binWidth = processor.getBinWidth();
        expect(std::abs(binWidth - (sampleRate / fftSize)) < 0.01f);
        
        // Find peak bin
        int peakBin = 0;
        float peakMagnitude = 0.0f;
        for (int i = 0; i < processor.getMagnitudeSpectrumSize(); ++i)
        {
            if (magnitudes[i] > peakMagnitude)
            {
                peakMagnitude = magnitudes[i];
                peakBin = i;
            }
        }
        
        // Check peak is at expected frequency
        float peakFrequency = peakBin * binWidth;
        float frequencyError = std::abs(peakFrequency - testFrequency);
        expect(frequencyError < binWidth, "Peak should be at test frequency");
        
        // Log results for debugging
        logMessage("Peak found at " + juce::String(peakFrequency) + " Hz (expected " + 
                  juce::String(testFrequency) + " Hz)");
        logMessage("Peak magnitude: " + juce::String(peakMagnitude));
    }
    
    void testCircularBuffer()
    {
        beginTest("Circular Buffer Functionality");
        
        FFTProcessor processor(8); // 256 samples for faster test
        const double sampleRate = 44100.0;
        
        // Process multiple small buffers
        for (int block = 0; block < 10; ++block)
        {
            juce::AudioBuffer<float> buffer(2, 64); // Stereo, 64 samples
            
            // Fill with test pattern
            for (int ch = 0; ch < 2; ++ch)
            {
                for (int i = 0; i < 64; ++i)
                {
                    buffer.setSample(ch, i, block * 0.1f + i * 0.001f);
                }
            }
            
            processor.processAudioBlock(buffer, sampleRate);
        }
        
        // After enough blocks, FFT should be computable
        bool computed = processor.computeFFT();
        expect(computed, "FFT should be computable after sufficient samples");
    }
    
    void testFFTComputationTiming()
    {
        beginTest("FFT Computation Timing");
        
        FFTProcessor processor(10);
        const double sampleRate = 44100.0;
        
        // Fill with noise
        juce::AudioBuffer<float> buffer(1, 1024);
        juce::Random random;
        for (int i = 0; i < 1024; ++i)
        {
            buffer.setSample(0, i, random.nextFloat() * 2.0f - 1.0f);
        }
        
        processor.processAudioBlock(buffer, sampleRate);
        
        // Time FFT computation
        auto startTime = juce::Time::getMillisecondCounterHiRes();
        bool computed = processor.computeFFT();
        auto endTime = juce::Time::getMillisecondCounterHiRes();
        
        expect(computed);
        
        double computeTime = endTime - startTime;
        logMessage("FFT computation time: " + juce::String(computeTime, 2) + " ms");
        
        // Should be fast (< 1ms on modern hardware)
        expect(computeTime < 5.0, "FFT should compute in under 5ms");
    }
    
    void testBandEnergyAnalyzer()
    {
        beginTest("Band Energy Analyzer Basic Functionality");
        
        BandEnergyAnalyzer analyzer;
        
        // Create test magnitude spectrum with energy in specific bands
        const int numBins = 512;
        const float binWidth = 44100.0f / 1024.0f; // ~43 Hz per bin
        
        std::vector<float> magnitudes(numBins, 0.0f);
        
        // Add energy in low band (20-250 Hz)
        int lowStartBin = 20.0f / binWidth;
        int lowEndBin = 250.0f / binWidth;
        for (int i = lowStartBin; i <= lowEndBin; ++i)
        {
            if (i < numBins) magnitudes[i] = 0.5f;
        }
        
        // Analyze
        analyzer.analyzeBands(magnitudes.data(), numBins, binWidth, 44100.0);
        expect(analyzer.isAnalysisReady());
        
        // Check band energies
        float lowEnergy = analyzer.getBandEnergy(0);
        float lowMidEnergy = analyzer.getBandEnergy(1);
        float highMidEnergy = analyzer.getBandEnergy(2);
        float highEnergy = analyzer.getBandEnergy(3);
        
        logMessage("Band energies: Low=" + juce::String(lowEnergy, 1) + 
                  " dB, LowMid=" + juce::String(lowMidEnergy, 1) + 
                  " dB, HighMid=" + juce::String(highMidEnergy, 1) + 
                  " dB, High=" + juce::String(highEnergy, 1) + " dB");
        
        // Low band should have highest energy
        expect(lowEnergy > lowMidEnergy);
        expect(lowEnergy > highMidEnergy);
        expect(lowEnergy > highEnergy);
    }
    
    void testFrequencyBandMapping()
    {
        beginTest("Frequency Band Boundaries");
        
        BandEnergyAnalyzer analyzer;
        
        // Test band boundaries
        float low, high;
        
        analyzer.getBandFrequencyRange(0, low, high);
        expectEquals(low, 20.0f);
        expectEquals(high, 250.0f);
        
        analyzer.getBandFrequencyRange(1, low, high);
        expectEquals(low, 250.0f);
        expectEquals(high, 2000.0f);
        
        analyzer.getBandFrequencyRange(2, low, high);
        expectEquals(low, 2000.0f);
        expectEquals(high, 8000.0f);
        
        analyzer.getBandFrequencyRange(3, low, high);
        expectEquals(low, 8000.0f);
        expectEquals(high, 20000.0f);
        
        // Test band names
        expect(juce::String(BandEnergyAnalyzer::getBandName(0)) == "Low");
        expect(juce::String(BandEnergyAnalyzer::getBandName(1)) == "Low-Mid");
        expect(juce::String(BandEnergyAnalyzer::getBandName(2)) == "High-Mid");
        expect(juce::String(BandEnergyAnalyzer::getBandName(3)) == "High");
    }
    
    void testKickDrumSimulation()
    {
        beginTest("Kick Drum Frequency Analysis");
        
        // Create a simple kick drum simulation
        // Kick = low sine (60 Hz) with exponential decay + click transient
        const int sampleRate = 44100;
        const int numSamples = sampleRate / 4; // 250ms
        const float fundamentalFreq = 60.0f;
        
        juce::AudioBuffer<float> kickBuffer(1, numSamples);
        
        for (int i = 0; i < numSamples; ++i)
        {
            float t = i / float(sampleRate);
            
            // Exponential decay envelope
            float envelope = std::exp(-5.0f * t);
            
            // Low frequency component
            float lowFreq = std::sin(2.0f * juce::MathConstants<float>::pi * fundamentalFreq * t);
            
            // Click transient (first 5ms)
            float click = 0.0f;
            if (t < 0.005f)
            {
                click = (1.0f - t / 0.005f) * 0.3f;
            }
            
            float sample = envelope * (lowFreq + click);
            kickBuffer.setSample(0, i, sample);
        }
        
        // Process through FFT
        FFTProcessor processor(11); // 2048 samples for better low freq resolution
        processor.processAudioBlock(kickBuffer, sampleRate);
        processor.computeFFT();
        
        // Analyze bands
        BandEnergyAnalyzer analyzer;
        analyzer.analyzeBands(processor.getMagnitudeSpectrum(), 
                            processor.getMagnitudeSpectrumSize(),
                            processor.getBinWidth(),
                            sampleRate);
        
        // Get band energies
        auto energies = analyzer.getAllBandEnergies();
        
        logMessage("Kick drum band energies:");
        for (int i = 0; i < 4; ++i)
        {
            logMessage("  " + juce::String(BandEnergyAnalyzer::getBandName(i)) + 
                      ": " + juce::String(energies[i], 1) + " dB");
        }
        
        // Verify kick drum characteristics
        // Low band should be dominant
        expect(energies[0] > energies[1], "Low band should dominate in kick drum");
        expect(energies[0] > energies[2], "Low band should be louder than high-mid");
        expect(energies[0] > energies[3], "Low band should be louder than high");
        
        // There should be some energy in low-mid from the click
        expect(energies[1] > -60.0f, "Should have some low-mid energy from transient");
    }
    
    void testPerformance()
    {
        beginTest("Performance Test - Multiple Instances");
        
        // Simulate multiple plugin instances
        const int numInstances = 10;
        std::vector<std::unique_ptr<FFTProcessor>> processors;
        std::vector<std::unique_ptr<BandEnergyAnalyzer>> analyzers;
        
        // Create instances
        for (int i = 0; i < numInstances; ++i)
        {
            processors.push_back(std::make_unique<FFTProcessor>(10));
            analyzers.push_back(std::make_unique<BandEnergyAnalyzer>());
        }
        
        // Generate test audio
        juce::AudioBuffer<float> buffer(2, 512);
        juce::Random random;
        for (int ch = 0; ch < 2; ++ch)
        {
            for (int i = 0; i < 512; ++i)
            {
                buffer.setSample(ch, i, random.nextFloat() * 0.5f - 0.25f);
            }
        }
        
        // Process multiple blocks
        const int numBlocks = 100;
        auto startTime = juce::Time::getMillisecondCounterHiRes();
        
        for (int block = 0; block < numBlocks; ++block)
        {
            // Feed audio to all instances
            for (auto& processor : processors)
            {
                processor->processAudioBlock(buffer, 44100.0);
            }
            
            // Compute FFT every 10 blocks (lazy computation)
            if (block % 10 == 9)
            {
                for (int i = 0; i < numInstances; ++i)
                {
                    if (processors[i]->computeFFT())
                    {
                        analyzers[i]->analyzeBands(
                            processors[i]->getMagnitudeSpectrum(),
                            processors[i]->getMagnitudeSpectrumSize(),
                            processors[i]->getBinWidth(),
                            44100.0
                        );
                    }
                }
            }
        }
        
        auto endTime = juce::Time::getMillisecondCounterHiRes();
        double totalTime = endTime - startTime;
        double timePerInstance = totalTime / numInstances;
        
        logMessage("Total processing time for " + juce::String(numInstances) + 
                  " instances: " + juce::String(totalTime, 2) + " ms");
        logMessage("Average time per instance: " + juce::String(timePerInstance, 2) + " ms");
        
        // Should handle multiple instances efficiently
        expect(timePerInstance < 50.0, "Should process efficiently with multiple instances");
    }
};

static FFTProcessorTests fftProcessorTests;

} // namespace AIplayer