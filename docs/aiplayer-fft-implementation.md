# AIplayer FFT Implementation Plan

## ⚠️ CRITICAL WARNING: DO NOT MODIFY CHATTY CHANNELS UI ⚠️
**The ChattyChannels Swift UI is extremely fragile and must NOT be touched during this implementation. Any UI modifications can break the entire interface and are very difficult to fix. Only modify the backend OSC handling code. UI changes will be planned separately in a future phase.**

## Project Structure
- **AIplayer (JUCE Audio Plugin)**: `/Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Builds/MacOSX/AIplayer.xcodeproj`
- **ChattyChannels (Swift Control Room)**: `/Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels.xcodeproj`

Both projects use Xcode for building and development.

## Overview
This document outlines the implementation plan for adding FFT-based frequency analysis to the AIplayer plugin, focusing on TR1 (kick channel) for initial development and testing.

## Phase 1: Basic FFT Infrastructure (Step by Step)

### Step 1: Add FFT Components to PluginProcessor.h
```cpp
// New includes needed
#include <juce_dsp/juce_dsp.h>

// New private members for FFT
private:
    // FFT components
    static constexpr int fftOrder = 10; // 2^10 = 1024 samples
    static constexpr int fftSize = 1 << fftOrder;
    juce::dsp::FFT fft{fftOrder};
    
    // Circular buffer for FFT input
    juce::AudioBuffer<float> fftBuffer;
    int fftBufferWritePos = 0;
    std::array<float, fftSize> fftData;
    std::array<float, fftSize / 2> magnitudeData;
    
    // Window function
    juce::dsp::WindowingFunction<float> window{fftSize, 
        juce::dsp::WindowingFunction<float>::hann};
    
    // Band energy results
    std::atomic<float> bandEnergy[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    
    // FFT processing control
    std::atomic<bool> shouldComputeFFT{false};
    std::atomic<int> fftComputeCounter{0};
    static constexpr int fftComputeInterval = 10; // Every 10 RMS updates
```

### Step 2: Initialize FFT Buffer in Constructor
```cpp
// In PluginProcessor constructor
fftBuffer.setSize(1, fftSize);
fftBuffer.clear();
```

### Step 3: Collect Audio Data for FFT
Add to `processBlock()` after RMS calculation:
```cpp
// Collect samples for FFT (mono mix)
auto* fftWritePointer = fftBuffer.getWritePointer(0);
for (int sample = 0; sample < buffer.getNumSamples(); ++sample) {
    float monoSample = 0.0f;
    for (int channel = 0; channel < totalNumInputChannels; ++channel) {
        monoSample += buffer.getSample(channel, sample);
    }
    monoSample /= totalNumInputChannels; // Average for mono
    
    // Write to circular buffer
    fftWritePointer[fftBufferWritePos] = monoSample;
    fftBufferWritePos = (fftBufferWritePos + 1) % fftSize;
}

// Trigger FFT computation periodically
fftComputeCounter++;
if (fftComputeCounter >= fftComputeInterval) {
    shouldComputeFFT = true;
    fftComputeCounter = 0;
}
```

### Step 4: Add FFT Computation Method
```cpp
void computeFFT() {
    if (!shouldComputeFFT.exchange(false)) {
        return;
    }
    
    // Copy circular buffer to FFT input (with proper ordering)
    auto* fftWritePointer = fftBuffer.getReadPointer(0);
    for (int i = 0; i < fftSize; ++i) {
        int bufferIndex = (fftBufferWritePos + i) % fftSize;
        fftData[i] = fftWritePointer[bufferIndex];
    }
    
    // Apply window function
    window.multiplyWithWindowingTable(fftData.data(), fftSize);
    
    // Perform FFT
    fft.performFrequencyOnlyForwardTransform(fftData.data());
    
    // Calculate magnitude spectrum
    for (int i = 0; i < fftSize / 2; ++i) {
        magnitudeData[i] = fftData[i] / (fftSize / 2);
    }
    
    // Extract band energies
    calculateBandEnergies();
}

void calculateBandEnergies() {
    const float sampleRate = getSampleRate();
    const float binWidth = sampleRate / fftSize;
    
    // Define frequency bands
    const float bandLimits[5] = {20.0f, 250.0f, 2000.0f, 8000.0f, 20000.0f};
    
    // Calculate bin indices for each band
    for (int band = 0; band < 4; ++band) {
        int startBin = static_cast<int>(bandLimits[band] / binWidth);
        int endBin = static_cast<int>(bandLimits[band + 1] / binWidth);
        
        // Clamp to valid range
        startBin = juce::jlimit(0, fftSize / 2 - 1, startBin);
        endBin = juce::jlimit(0, fftSize / 2 - 1, endBin);
        
        // Sum energy in band
        float energy = 0.0f;
        for (int bin = startBin; bin <= endBin; ++bin) {
            energy += magnitudeData[bin] * magnitudeData[bin];
        }
        
        // Convert to dB
        float energyDb = 20.0f * std::log10(std::max(energy, 1e-10f));
        bandEnergy[band].store(energyDb);
    }
}
```

### Step 5: Call FFT from Timer Callback
Modify the existing timer callback:
```cpp
void timerCallback() override {
    // Existing RMS code...
    sendRMSUpdate();
    
    // Compute FFT if needed
    computeFFT();
    
    // For now, log band energies for TR1 (testing)
    if (currentTrackID == "TR1") {
        logMessage(LogLevel::Debug, 
            String::formatted("TR1 Band Energies: Low=%.1f dB, LowMid=%.1f dB, HighMid=%.1f dB, High=%.1f dB",
            bandEnergy[0].load(), bandEnergy[1].load(), 
            bandEnergy[2].load(), bandEnergy[3].load()));
    }
}
```

## Phase 2: OSC Integration (After Basic FFT Works)

### ⚠️ REMINDER: NO UI MODIFICATIONS ⚠️
**When updating ChattyChannels to handle new OSC messages, ONLY modify the backend message handling in OSCListener.swift. DO NOT touch any SwiftUI views, VUMeterView, or any UI-related files.**

### Step 1: Extend OSC Message Format
```cpp
void sendTelemetryUpdate() {
    if (!oscSender || currentTrackID.isEmpty()) return;
    
    // New telemetry message format
    juce::OSCMessage telemetryMessage("/aiplayer/telemetry");
    telemetryMessage.addString(currentTrackID); // e.g., "TR1"
    telemetryMessage.addFloat32(currentRMS);
    telemetryMessage.addFloat32(bandEnergy[0].load()); // Low
    telemetryMessage.addFloat32(bandEnergy[1].load()); // Low-Mid
    telemetryMessage.addFloat32(bandEnergy[2].load()); // High-Mid
    telemetryMessage.addFloat32(bandEnergy[3].load()); // High
    
    if (!oscSender->send(telemetryMessage)) {
        logMessage(LogLevel::Warning, "Failed to send telemetry update");
    }
}
```

## FFT Testing Strategy with Voxengo SPAN

### Test Setup

#### Logic Pro Configuration
```
Track 1 (TR1) - Kick:
├── AIplayer plugin (our FFT implementation)
├── Voxengo SPAN (reference analyzer)
└── Audio content (kick drum)

Master Bus:
└── Voxengo SPAN (for overall mix reference)
```

### Phase 1: Synthetic Test Signals

#### Test 1.1: Single Frequency Validation
```cpp
// Add test tone generator to AIplayer (temporary)
void generateTestTone(AudioBuffer<float>& buffer, float frequency) {
    const float sampleRate = getSampleRate();
    static float phase = 0.0f;
    
    for (int sample = 0; sample < buffer.getNumSamples(); ++sample) {
        float value = 0.5f * std::sin(2.0f * M_PI * frequency * phase);
        for (int channel = 0; channel < buffer.getNumChannels(); ++channel) {
            buffer.setSample(channel, sample, value);
        }
        phase += 1.0f / sampleRate;
        if (phase >= 1.0f) phase -= 1.0f;
    }
}
```

**Test Cases**:
1. **100 Hz tone** → Should show peak in Band 1 (20-250 Hz)
2. **1 kHz tone** → Should show peak in Band 2 (250-2k Hz)
3. **5 kHz tone** → Should show peak in Band 3 (2k-8k Hz)
4. **12 kHz tone** → Should show peak in Band 4 (8k-20k Hz)

**Validation**: Compare our band energy values with SPAN's frequency display

#### Test 1.2: White/Pink Noise
- Generate white noise → Should show relatively flat spectrum
- Compare overall spectral shape with SPAN
- Verify band energy ratios match expected values

### Phase 2: Real Kick Drum Testing

#### Test 2.1: Kick Drum Analysis
**Expected Results**:
```
Band 1 (20-250 Hz):   High energy (-10 to -20 dB)
Band 2 (250-2k Hz):   Medium energy (-20 to -30 dB)
Band 3 (2k-8k Hz):    Low energy (-30 to -40 dB)
Band 4 (8k-20k Hz):   Very low energy (-40 to -50 dB)
```

**Test Procedure**:
1. Load a kick drum sample on TR1
2. Set SPAN to show spectrum analyzer
3. Play kick hit repeatedly
4. Log our FFT band values
5. Screenshot SPAN for comparison

#### Test 2.2: Different Kick Types
Test various kick drums to ensure accuracy:
- **808 Kick**: Very low frequency content (30-60 Hz)
- **Rock Kick**: More mid presence (60-120 Hz + 2-4 kHz beater)
- **Electronic Kick**: Often has sub-bass (20-40 Hz)

### Phase 3: Performance Testing

#### Test 3.1: CPU Usage Monitoring
```cpp
// Add performance timing to computeFFT()
void computeFFT() {
    auto startTime = Time::getMillisecondCounterHiRes();
    
    // ... existing FFT code ...
    
    auto endTime = Time::getMillisecondCounterHiRes();
    float computeTime = endTime - startTime;
    
    if (currentTrackID == "TR1") {
        logMessage(LogLevel::Debug, 
            String::formatted("FFT compute time: %.2f ms", computeTime));
    }
}
```

**Metrics to Track**:
- FFT computation time (target: <1ms)
- Overall CPU usage in Logic Pro
- Memory usage per plugin instance

#### Test 3.2: Multi-Instance Stress Test
1. Duplicate AIplayer to 10 tracks
2. Monitor total CPU usage
3. Verify no audio dropouts
4. Check if all instances compute FFT correctly

### Phase 4: Accuracy Validation

#### Test 4.1: Calibration Test
Create a measurement protocol:
```
1. Generate 1 kHz sine at -20 dBFS
2. Measure in SPAN: note exact dB level
3. Compare with our Band 2 energy
4. Calculate offset if any
5. Apply calibration factor if needed
```

#### Test 4.2: Dynamic Range Test
- Test with very quiet signals (-60 dBFS)
- Test with loud signals (-6 dBFS)
- Verify band energy scaling is consistent

### Debugging Tools

#### Console Output Format
```cpp
// Enhanced debug output for testing
void logFFTDebug() {
    String debugMsg = String::formatted(
        "[FFT] TR1 | RMS: %.1f dB | Bands: [%.1f, %.1f, %.1f, %.1f] dB | CPU: %.1f%%",
        20.0f * log10(currentRMS),
        bandEnergy[0].load(),
        bandEnergy[1].load(),
        bandEnergy[2].load(),
        bandEnergy[3].load(),
        getCPUUsage()
    );
    logMessage(LogLevel::Debug, debugMsg);
}
```

#### Visual Comparison Method
1. **Screenshot SPAN** with kick playing
2. **Log our values** at the same moment
3. **Create comparison table**:
```
Frequency Range | SPAN Reading | Our Reading | Difference
20-250 Hz      | -15 dB       | -16 dB      | 1 dB
250-2k Hz      | -25 dB       | -24 dB      | 1 dB
...
```

### Test Automation Script
Create a test harness that:
1. Generates test signals
2. Captures both SPAN and our readings
3. Calculates accuracy metrics
4. Produces test report

### Success Criteria
- **Accuracy**: Within ±2 dB of SPAN readings
- **Performance**: <1% CPU per instance
- **Stability**: No crashes or glitches over 1 hour
- **Consistency**: Reproducible results across sessions

### Quick Daily Test
For rapid iteration during development:
1. Load standard kick sample
2. Check Band 1 shows strong energy
3. Verify CPU usage acceptable
4. Compare visually with SPAN
5. Check OSC messages sending correctly

## Building and Testing

### Building AIplayer Plugin
1. Open Xcode project: `/Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Builds/MacOSX/AIplayer.xcodeproj`
2. Select the AU (Audio Unit) target
3. Build with Cmd+B
4. Plugin will be installed to `~/Library/Audio/Plug-Ins/Components/AIplayer.component`
5. Restart Logic Pro to load the updated plugin

### Building ChattyChannels
1. Open Xcode project: `/Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels.xcodeproj`
2. Build and run with Cmd+R
3. Ensure ChattyChannels is running before starting Logic Pro
4. **DO NOT modify any UI files during v0.8 implementation**

## Implementation Order

1. **Today**: 
   - Add FFT components to PluginProcessor.h
   - Initialize buffers in constructor
   - Add sample collection to processBlock()
   - Build in Xcode and test

2. **Next Session**:
   - Implement computeFFT() method
   - Add calculateBandEnergies()
   - Test with simple sine wave generator
   - Rebuild and verify in Logic Pro

3. **Following Session**:
   - Integrate with timer callback
   - Test with actual kick drum on TR1
   - Verify band energy values
   - Check logs at `~/Documents/chatty-channel/logs/AIplayer.log`

4. **Final Integration**:
   - Replace RMS-only OSC with telemetry message
   - Update ChattyChannels Xcode project to receive new format (BACKEND ONLY - NO UI CHANGES)
   - Test end-to-end with VU meters (existing UI should continue working)
   - **DO NOT modify any SwiftUI views, VUMeterView, or UI components**

This incremental approach lets us verify each component works correctly before moving to the next, reducing debugging complexity. Starting with just TR1 (kick) is perfect since kicks have predictable frequency content mainly in the low band.
