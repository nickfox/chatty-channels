# New Calibration Procedure

## Overview
This document describes the simplified calibration procedure for identifying which AIPlayer plugin is on which Logic Pro track. The approach uses a single test tone (137Hz) broadcast to all plugins, then systematically unmutes tracks one at a time to identify plugin-to-track mappings.

## Core Principle
- **One track unmuted at a time** = only one plugin will have RMS > 0
- All muted tracks will have RMS values at or near 0
- The plugin with RMS > 0 is definitively on the unmuted track

## Detailed Procedure

### 1. Setup Phase
1. Discover all tracks using accessibility API (excluding Stereo Out and Master)
2. Mute ALL tracks using accessibility API
3. Broadcast 137Hz tone at -10dB to all plugin ports (9000-9010)
4. Wait 2 seconds for tone generation to stabilize

### 2. Track Identification Loop
For each track in order (e.g., kick = TR1, snare = TR2, bass = TR3):

1. Unmute ONLY the current track via accessibility API
2. Wait 0.5 seconds for audio to settle
3. Send RMS query to all plugins
4. Identify the ONE plugin with RMS > 0
5. Assign that plugin's tempID to this track number (TR1, TR2, etc.)
6. Store the mapping in the database
7. Mute the track again before proceeding to the next

### 3. Cleanup Phase
1. Stop the 137Hz tone on all plugins
2. Send track assignments to each identified plugin via OSC
3. Clear unidentified RMS cache entries

## Expected RMS Values
- **Muted track**: RMS ≈ 0.0001 (-80dB or lower)
- **Unmuted track**: RMS ≈ 0.1 (-20dB or higher with 137Hz @ -10dB)

The large difference ensures unambiguous identification.

## Database Storage
The Swift app stores:
- Plugin tempID ↔ Track Number (TR1, TR2, etc.) mapping
- Track name ↔ Track Number mapping

## Implementation Notes

### Key Functions to Modify

1. **`startOscillatorBasedCalibration()`**
   - Remove frequency assignment per track
   - Use single 137Hz tone for all plugins

2. **`identifyPluginsByMuting()`** → rename to **`identifyPluginsByUnmuting()`**
   - Start with all tracks muted
   - Unmute one track at a time
   - Query for positive RMS instead of RMS drop

3. **`findSilentPlugin()`** → rename to **`findActivePlugin()`**
   - Look for plugin with RMS > threshold
   - Return the plugin with highest RMS value

### Timing Parameters
- Initial tone stabilization: 2 seconds
- Per-track settle time: 0.5 seconds
- Total calibration time: ~2 + (0.5 × number_of_tracks) seconds

### Error Handling
- If no plugin shows RMS > 0 for a track: Log warning, continue
- If multiple plugins show high RMS: Take the highest (shouldn't happen)
- If plugin already assigned: Skip in subsequent checks

## Advantages of This Approach
1. **Simplicity**: Binary decision (RMS > 0 or not)
2. **Reliability**: No ambiguity about which plugin is active
3. **Speed**: Single frequency, minimal wait times
4. **Robustness**: Large RMS difference between states

## Testing Considerations
- Verify all tracks start muted
- Confirm only one track unmutes at a time
- Check RMS threshold is appropriate for detection
- Validate track assignment persistence
