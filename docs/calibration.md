# Calibration System Design - v0.7

## Overview

The calibration system identifies which AIplayer plugin instance is running on which Logic Pro track by using a combination of accessibility-based muting and OSC query/response mechanisms.

## Current Status

### Fixed Issues
- **VU Meter Timing**: Corrected from 60 Hz to 24 Hz to match AIplayer plugin's RMS transmission rate
- **AppleScript Compatibility**: Replaced broken Logic Pro 11.2 AppleScript with accessibility APIs for track muting

### Pending Implementation
- OSC query system for active RMS requests
- Bidirectional plugin identification protocol

## Architecture

### 1. Track Discovery
- Use accessibility APIs to enumerate Logic Pro tracks
- Store track list with names and UUIDs in SQLite database
- Map tracks to simple IDs (TR1, TR2, etc.)

### 2. Calibration Process

#### Phase 1: Setup
1. Mute all tracks using accessibility APIs (`AppleScriptService.swift`)
2. Clear unidentified RMS cache in OSCService
3. Get baseline RMS readings from all plugins

#### Phase 2: Systematic Identification
For each track in sequence:
1. **Unmute single track** using accessibility APIs
2. **Broadcast query** to all plugins via OSC: `/aiplayer/query_rms`
3. **Wait for responses** from plugins via OSC: `/aiplayer/rms_response`
4. **Identify active plugin** by comparing RMS levels before/after unmute
5. **Send assignment** to identified plugin: `/aiplayer/track_uuid_assignment`
6. **Mute track again** and move to next

### 3. OSC Communication Protocol

#### Query Broadcast Mechanism
```
Address: /aiplayer/query_rms
Arguments: [string queryID]
Destination: Broadcast to all known plugin receiver ports
Method: Send to ports 9000-9010 (AIplayer tries multiple ports)
```

#### Plugin Response Format
```
Address: /aiplayer/rms_response  
Arguments: [string queryID, string tempInstanceID, float currentRMS]
Source: Individual plugin instances
Destination: ChattyChannels port 9001
```

#### Track Assignment
```
Address: /aiplayer/track_uuid_assignment
Arguments: [string tempInstanceID, string logicTrackUUID]
Destination: Specific plugin IP:port (from RMS cache)
```

## Plugin Identification Logic

### How Queries Are Broadcast
1. **Port Range Broadcasting**: Send query to ports 9000-9010 on localhost
2. **Query ID**: Generate unique UUID for each calibration session to avoid stale responses
3. **Timeout**: Wait 500ms for responses before processing

### How Plugins Are Identified
1. **Baseline Comparison**: Compare RMS before unmute vs after unmute
2. **Threshold Detection**: Active plugin should show RMS > -50 dBFS and delta > +30 dB
3. **Unique Selection**: Choose plugin with highest RMS delta for the track
4. **Conflict Resolution**: If multiple plugins respond, select based on highest signal level

### Response Validation
- Verify queryID matches current calibration session
- Check tempInstanceID format and uniqueness
- Validate RMS value is reasonable (> 0, < 1.0)
- Confirm sender IP/port matches cached unidentified data

## Implementation Details

### Required OSC Message Handlers

#### In AIplayer Plugin (`PluginProcessor.cpp`)
```cpp
// Add to oscMessageReceived()
else if (message.getAddressPattern() == "/aiplayer/query_rms")
{
    if (message.size() == 1 && message[0].isString())
    {
        juce::String queryID = message[0].getString();
        float currentRMS = getCurrentRMSLevel(); // Get latest RMS
        
        // Respond with our current RMS level
        juce::OSCMessage response("/aiplayer/rms_response");
        response.addString(queryID);
        response.addString(tempInstanceID);
        response.addFloat32(currentRMS);
        
        if (!sender.send(response))
            logMessage(LogLevel::Warning, "Failed to send RMS response for query: " + queryID);
    }
}
```

#### In ChattyChannels (`OSCListener.swift`)
```swift
case "/aiplayer/rms_response":
    await handleRMSResponse(message)

private func handleRMSResponse(_ message: OSCMessage) async {
    guard message.arguments.count >= 3,
          let queryID = message.arguments[0] as? String,
          let tempInstanceID = message.arguments[1] as? String,
          let currentRMS = message.arguments[2] as? Float else {
        logger.error("Invalid RMS response message format")
        return
    }
    
    // Forward to calibration service
    await calibrationService.processRMSResponse(
        queryID: queryID, 
        tempInstanceID: tempInstanceID, 
        currentRMS: currentRMS
    )
}
```

### CalibrationService Updates

```swift
// Add query management
private var currentQueryID: String?
private var queryResponses: [String: (tempID: String, rms: Float)] = [:]

func queryAllPluginsForRMS() async -> [String: Float] {
    currentQueryID = UUID().uuidString
    queryResponses.removeAll()
    
    // Broadcast query to all possible plugin ports
    for port in 9000...9010 {
        oscService.sendQuery(queryID: currentQueryID!, toPort: port)
    }
    
    // Wait for responses
    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    
    // Return collected responses
    return queryResponses.mapValues { $0.rms }
}

func processRMSResponse(queryID: String, tempInstanceID: String, currentRMS: Float) {
    guard queryID == currentQueryID else {
        logger.warning("Received response for stale query: \(queryID)")
        return
    }
    
    queryResponses[tempInstanceID] = (tempID: tempInstanceID, rms: currentRMS)
    logger.debug("Received RMS response: \(tempInstanceID) = \(currentRMS)")
}
```

## Error Handling

### Plugin Communication Failures
- **No Response**: Skip track and log warning
- **Multiple Responses**: Select highest RMS delta
- **Invalid Response**: Ignore and continue

### Logic Pro Integration Issues  
- **Mute Failed**: Continue with warning, may affect identification accuracy
- **Track Enumeration Failed**: Abort calibration with clear error message

### Network Issues
- **Port Binding Failed**: Try alternative ports 9001-9005
- **Send Failures**: Retry up to 3 times with exponential backoff

## Testing Strategy

### Unit Tests
- OSC packet encoding/decoding
- Query broadcast mechanism  
- Response validation logic
- Track muting via accessibility APIs

### Integration Tests
- End-to-end calibration with mock Logic Pro
- Multi-plugin response handling
- Network failure scenarios

### Manual Testing
- Real Logic Pro session with multiple AIplayer instances
- Track muting verification
- VU meter update validation at 24 Hz

## Future Enhancements

- **Auto-detection**: Identify stereo out and master bus tracks automatically
- **Conflict Resolution**: Handle duplicate track names gracefully  
- **Performance**: Cache accessibility elements for faster muting
- **Reliability**: Add OSC message checksums and sequence numbers