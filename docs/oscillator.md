# Oscillator-Based Track Calibration Plan

## Overview

This document outlines a new approach to track calibration that uses JUCE oscillators in the AIplayer plugins to generate unique test tones, combined with accessibility-based mute control to create a robust, automated track mapping system.

## Problem Statement

The current AppleScript-based calibration fails in Logic Pro 11.2+ because:
- `every track` enumeration no longer works
- `mute of aTrack` property access is blocked
- Cannot insert test oscillators via AppleScript
- Relies on existing audio content which may not exist

## Proposed Solution

### Core Concept
Each AIplayer plugin generates a unique frequency test tone on command. The Chatty Channels app mutes channels one by one using accessibility APIs and monitors which plugin's RMS drops to silence, creating a direct channel-to-plugin mapping.

### Key Advantages
- **Deterministic**: Each plugin gets a unique frequency signature
- **Automated**: No manual user setup required
- **Precise**: Direct correlation between mute action and RMS response
- **Independent**: Not affected by Logic Pro's AppleScript restrictions
- **Reliable**: Uses existing OSC infrastructure

## Technical Implementation

### Phase 1: AIplayer Plugin Enhancement

#### 1.1 Add JUCE Oscillator Component
```cpp
// In PluginProcessor.h
class AIplayerAudioProcessor : public juce::AudioProcessor {
private:
    // Existing members...
    
    // Calibration oscillator
    juce::dsp::Oscillator<float> calibrationOscillator;
    bool isGeneratingTone = false;
    float toneFrequency = 440.0f;
    float toneAmplitude = 0.1f; // -20 dBFS
    std::atomic<bool> toneEnabled{false};
};
```

#### 1.2 OSC Command Handler
Add new OSC message handlers:
- `/aiplayer/start_tone <frequency> <amplitude>` - Start generating test tone
- `/aiplayer/stop_tone` - Stop test tone generation
- `/aiplayer/tone_status` - Query current tone status

```cpp
// New OSC handlers in PluginProcessor.cpp
void handleStartTone(const juce::OSCMessage& message) {
    if (message.size() >= 2) {
        float freq = message[0].getFloat32();
        float amp = message[1].getFloat32();
        startCalibrationTone(freq, amp);
    }
}

void handleStopTone(const juce::OSCMessage& message) {
    stopCalibrationTone();
}

void startCalibrationTone(float frequency, float amplitude) {
    calibrationOscillator.setFrequency(frequency);
    toneAmplitude = amplitude;
    toneEnabled.store(true);
    isGeneratingTone = true;
}
```

#### 1.3 Audio Processing Integration
```cpp
// In processBlock()
void AIplayerAudioProcessor::processBlock(AudioBuffer<float>& buffer, MidiBuffer& midiMessages) {
    // Existing RMS processing...
    
    // Add calibration tone if enabled
    if (toneEnabled.load() && isGeneratingTone) {
        auto* leftChannel = buffer.getWritePointer(0);
        auto* rightChannel = buffer.getNumChannels() > 1 ? buffer.getWritePointer(1) : nullptr;
        
        for (int sample = 0; sample < buffer.getNumSamples(); ++sample) {
            float toneValue = calibrationOscillator.processSample(0.0f) * toneAmplitude;
            leftChannel[sample] += toneValue;
            if (rightChannel) rightChannel[sample] += toneValue;
        }
    }
    
    // Continue with existing RMS calculation...
}
```

### Phase 2: ChattyChannels Calibration Service

#### 2.1 Enhanced Calibration Flow
```swift
// In CalibrationService.swift
public func startOscillatorBasedCalibration() async {
    logger.info("Starting oscillator-based calibration")
    
    // 1. Discover tracks using accessibility APIs
    let trackMappings = try trackMappingService.loadMapping()
    
    // 2. Assign unique frequencies to each track
    let frequencyAssignments = assignUniqueFrequencies(trackMappings)
    
    // 3. Send tone generation commands to all plugins
    try await sendToneCommands(frequencyAssignments)
    
    // 4. Mute channels one by one and identify plugins
    let mappings = try await identifyPluginsByMuting(trackMappings)
    
    // 5. Stop all tones and update database
    try await stopAllTones()
    try await updateTrackMappings(mappings)
    
    logger.info("Oscillator calibration completed successfully")
}
```

#### 2.2 Frequency Assignment Strategy
```swift
private func assignUniqueFrequencies(_ trackMappings: [String: String]) -> [String: FrequencyAssignment] {
    var assignments: [String: FrequencyAssignment] = [:]
    let baseFrequency: Float = 100.0 // Start at 100 Hz
    let frequencyStep: Float = 100.0 // Increment by 100 Hz
    
    for (index, (trackName, simpleID)) in trackMappings.enumerated() {
        let frequency = baseFrequency + (Float(index) * frequencyStep)
        assignments[simpleID] = FrequencyAssignment(
            frequency: frequency,
            amplitude: -20.0, // dBFS
            trackName: trackName
        )
    }
    return assignments
}

struct FrequencyAssignment {
    let frequency: Float
    let amplitude: Float
    let trackName: String
}
```

#### 2.3 Plugin Identification Process
```swift
private func identifyPluginsByMuting(_ trackMappings: [String: String]) async throws -> [String: String] {
    var identifiedMappings: [String: String] = [:]
    
    // Get baseline RMS from all plugins
    let baselineRMS = oscService.getAllPluginRMSData()
    logger.info("Baseline RMS collected from \(baselineRMS.count) plugins")
    
    // Test each track by muting it
    for (trackName, simpleID) in trackMappings {
        logger.info("Testing track: \(trackName) (\(simpleID))")
        
        // Mute this specific track using accessibility APIs
        try await accessibilityService.muteTrack(byName: trackName)
        
        // Wait for audio to settle
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Get RMS data after muting
        let mutedRMS = oscService.getAllPluginRMSData()
        
        // Find which plugin's RMS dropped significantly
        if let silentPluginID = findSilentPlugin(baseline: baselineRMS, muted: mutedRMS) {
            identifiedMappings[silentPluginID] = simpleID
            logger.info("Identified mapping: Plugin \(silentPluginID) -> Track \(trackName) (\(simpleID))")
        }
        
        // Unmute the track
        try await accessibilityService.unmuteTrack(byName: trackName)
        
        // Brief pause between tests
        try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
    }
    
    return identifiedMappings
}
```

#### 2.4 Silent Plugin Detection
```swift
private func findSilentPlugin(baseline: [String: RMSData], muted: [String: RMSData]) -> String? {
    let silenceThreshold: Float = -60.0 // dBFS
    let dropThreshold: Float = 30.0     // dB drop required
    
    for (pluginID, baselineData) in baseline {
        guard let mutedData = muted[pluginID] else { continue }
        
        let rmsDrop = baselineData.rms - mutedData.rms
        let isSilent = mutedData.rms < silenceThreshold
        
        if rmsDrop > dropThreshold || isSilent {
            logger.info("Plugin \(pluginID): RMS dropped from \(baselineData.rms) to \(mutedData.rms) (drop: \(rmsDrop) dB)")
            return pluginID
        }
    }
    
    return nil
}
```

### Phase 3: OSC Protocol Extensions

#### 3.1 New OSC Message Types
```
// From Chatty Channels to AIplayer
/aiplayer/start_tone <float:frequency> <float:amplitude_db>
/aiplayer/stop_tone
/aiplayer/tone_status

// From AIplayer to Chatty Channels (responses)
/aiplayer/tone_started <string:instance_id> <float:frequency>
/aiplayer/tone_stopped <string:instance_id>
/aiplayer/tone_error <string:instance_id> <string:error_message>
```

#### 3.2 Enhanced OSCService Methods
```swift
// In OSCService.swift
public func startToneGeneration(pluginID: String, frequency: Float, amplitude: Float) async throws {
    let message = OSCMessage(
        address: "/aiplayer/start_tone",
        values: [frequency, amplitude]
    )
    try sendReliableMessage(to: pluginID, message: message)
}

public func stopToneGeneration(pluginID: String) async throws {
    let message = OSCMessage(address: "/aiplayer/stop_tone")
    try sendReliableMessage(to: pluginID, message: message)
}

public func getAllPluginRMSData() -> [String: RMSData] {
    // Return current RMS data for all known plugins
    return currentRMSCache
}
```

### Phase 4: Accessibility Integration

#### 4.1 Track-Specific Mute Control
```swift
// In AccessibilityTrackDiscoveryService.swift or new service
public func muteTrackByName(_ trackName: String) throws {
    let tracks = try discoverTracks()
    guard let trackID = tracks[trackName] else {
        throw AccessibilityError.trackNotFound
    }
    
    // Find the specific track and mute it
    try muteSpecificTrack(trackID)
}

public func unmuteTrackByName(_ trackName: String) throws {
    // Similar implementation for unmuting
}
```

## Error Handling & Edge Cases

### 4.1 Common Failure Scenarios
1. **Plugin not responding to OSC**: Timeout handling, retry logic
2. **Accessibility permissions denied**: Graceful fallback to manual mapping
3. **Logic Pro not running**: Clear error messages
4. **Multiple plugins with same RMS**: Frequency conflict resolution
5. **Audio interface issues**: Buffer underruns during tone generation

### 4.2 Validation & Verification
```swift
private func validateCalibrationResults(_ mappings: [String: String]) -> Bool {
    // Check for duplicate mappings
    let uniqueValues = Set(mappings.values)
    guard uniqueValues.count == mappings.count else {
        logger.error("Duplicate track assignments detected")
        return false
    }
    
    // Verify all expected tracks are mapped
    let expectedTracks = trackMappingService.getAllExpectedTracks()
    for expectedTrack in expectedTracks {
        guard mappings.values.contains(expectedTrack) else {
            logger.warning("Track \(expectedTrack) not mapped to any plugin")
        }
    }
    
    return true
}
```

## Testing Strategy

### 5.1 Unit Tests
- **OSC message handling**: Mock OSC endpoints
- **Frequency assignment logic**: Ensure unique frequencies
- **RMS drop detection**: Simulated data with known drops
- **Accessibility mute control**: Mock Logic Pro interface

### 5.2 Integration Tests
- **Full calibration flow**: End-to-end with real Logic Pro
- **Error recovery**: Test with missing plugins, accessibility failures
- **Performance**: Calibration time and resource usage

### 5.3 Manual Testing Scenarios
1. **Fresh Logic Pro session** with AIplayer on multiple tracks
2. **Existing session** with complex routing
3. **Missing accessibility permissions** - verify graceful handling
4. **Logic Pro not running** - clear error reporting

## Implementation Timeline

### Sprint 1: AIplayer Plugin Enhancement
- [ ] Add JUCE oscillator component to PluginProcessor
- [ ] Implement OSC tone command handlers
- [ ] Integrate tone generation with audio processing
- [ ] Add comprehensive logging for tone operations

### Sprint 2: Chatty Channels Calibration Service
- [ ] Implement frequency assignment algorithm
- [ ] Create oscillator-based calibration flow
- [ ] Add plugin identification by mute testing
- [ ] Integrate with existing CalibrationService

### Sprint 3: OSC Protocol & Accessibility
- [ ] Extend OSC message types and handlers
- [ ] Add track-specific mute control via accessibility
- [ ] Implement error handling and validation
- [ ] Add comprehensive test coverage

### Sprint 4: Testing & Refinement
- [ ] End-to-end testing with Logic Pro 11.2
- [ ] Performance optimization
- [ ] Error handling refinement
- [ ] Documentation updates

## Success Criteria

1. **Accuracy**: 100% correct plugin-to-track mapping in test scenarios
2. **Reliability**: Consistent results across multiple calibration runs
3. **Performance**: Complete calibration in under 30 seconds for 8 tracks
4. **User Experience**: Clear progress indication and error reporting
5. **Compatibility**: Works with Logic Pro 11.2+ without AppleScript limitations

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| JUCE oscillator performance impact | High | Limit tone generation to calibration only |
| OSC message reliability | Medium | Implement retry logic and confirmation |
| Accessibility API changes | Medium | Maintain AppleScript fallback where possible |
| Audio interface conflicts | Low | Use conservative amplitude levels |
| Logic Pro UI changes | Low | Regular testing with Logic Pro updates |

## Conclusion

This oscillator-based approach provides a robust, automated solution to track calibration that sidesteps Logic Pro's AppleScript limitations. By leveraging JUCE's built-in audio capabilities and the existing OSC infrastructure, we can create a reliable mapping system that works regardless of Logic Pro's accessibility restrictions.

The approach is technically sound, builds on existing code, and provides clear error handling and validation. Implementation can be done incrementally, allowing for testing and refinement at each stage.