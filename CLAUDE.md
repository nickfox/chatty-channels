# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project consists of two main components:

1. **AIplayer**: A JUCE-based audio plugin (AU/VST3) that runs inside Logic Pro X
   - Captures RMS and FFT data from audio tracks
   - Sends telemetry via OSC to the Chatty Channels app
   - Located in `/AIplayer/AIplayer/`

2. **Chatty Channels**: A Swift/SwiftUI macOS control room app
   - Displays VU meters with realistic ballistics
   - Integrates with multiple LLM providers (OpenAI, Claude, Gemini, Grok)
   - Controls Logic Pro via AppleScript and MIDI
   - Located in `/ChattyChannels/`

## Build Commands

### AIplayer Plugin (JUCE/C++)
```bash
# Build using Xcode (preferred method)
cd /Users/nickfox137/Documents/chatty-channel/AIplayer/AIplayer/Builds/MacOSX
xcodebuild -scheme "AIplayer - All" -configuration Release build

# Build outputs will be in:
# - AIplayer.app (standalone)
# - AIplayer.component (AU plugin)
# - AIplayer.vst3 (VST3 plugin)
```

### Chatty Channels App (Swift)
```bash
# Build using Xcode
cd /Users/nickfox137/Documents/chatty-channel/ChattyChannels
xcodebuild -scheme "ChattyChannels" -configuration Release build

# Run tests
xcodebuild test -scheme "ChattyChannels"
```

## Architecture & Communication

### OSC Protocol
- **Port**: 9001 (Chatty Channels listens, AIplayer sends)
- **Message Format**: `/aiplayer/rms/<pluginID> <rmsValue>`
- **Plugin IDs**: Simple format like "TR1", "TR2" (stored in SQLite)

### Key Services
1. **OSCService**: Handles OSC communication with retry logic
2. **TrackMappingService**: Maps plugin instances to Logic tracks
3. **LevelMeterService**: Manages VU meter animations and ballistics
4. **LogicParameterService**: Controls Logic Pro via AppleScript
5. **CalibrationService**: Handles track identification (currently blocked)

## Current v0.7 Status & Issues

### Critical Blocker
Logic Pro track enumeration via AppleScript is not working in Logic Pro 11.2. The calibration system cannot map AIplayer plugins to specific tracks.

### AIplayer Plugin Issues
- Continuous "No audio buffer available for RMS calculation" errors
- Exception in sendRMSTelemetry
- Plugin needs debugging in `PluginProcessor.cpp`

### Working Features
- OSC communication infrastructure
- VU meter UI with realistic ballistics
- Multi-LLM chat integration
- PID controller for volume adjustments

## Development Tips

### When Working on AIplayer Plugin
1. Check `logs/AIplayer.log` for runtime errors
2. Focus on `PluginProcessor.cpp` for audio processing issues
3. Ensure proper buffer handling in `processBlock()`
4. Test OSC messages with `nc -u -l 9001` to monitor output

### When Working on Chatty Channels
1. Run test suite before making changes: `./tests/test_calibration_applescript.sh`
2. Use `SimulationService` for testing without Logic Pro
3. Check `OSCListener` logs for incoming messages
4. UI changes are NOT allowed in v0.7 (critical constraint)

### Testing Track Identification
```bash
# Test AppleScript track enumeration
./test_applescript.sh

# Test AXLayoutItem approach
./docs/logs/test_axlayoutitem.sh

# Monitor OSC messages
nc -u -l 9001
```

## Key Files to Understand

### AIplayer
- `Source/PluginProcessor.cpp` - Main audio processing and OSC sending
- `Source/RMSCircularBuffer.cpp` - RMS calculation logic

### Chatty Channels
- `OSCService.swift` - OSC communication with retry logic
- `TrackMappingService.swift` - Plugin-to-track mapping
- `CalibrationService.swift` - Track identification system
- `Services/LevelMeterService.swift` - VU meter data processing
- `Views/VUMeter/VUMeterView.swift` - VU meter UI

## Next Steps for v0.7

1. Fix AIplayer buffer/exception issues
2. Implement alternative track identification (MIDI or fix AXLayoutItem)
3. Complete OSC data flow from plugin to VU meters
4. Test end-to-end with real Logic Pro session

## Development Principles

- We want to minimize asking the user to do anything. ie. we are not asking the user to put a test tone generator on all the channels.