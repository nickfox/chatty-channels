#!/bin/bash
# Test the calibration AppleScript syntax

echo "=== Testing Calibration AppleScript Syntax ==="
echo

# Test the fixed syntax with ≠ operator
echo "Test: Track muting logic with ≠ operator"
osascript << 'EOF'
tell application "Logic Pro"
    set targetTrackNum to 1
    set trackCounter to 1
    
    -- Test the comparison syntax
    if trackCounter ≠ targetTrackNum then
        return "trackCounter is not equal to targetTrackNum"
    else
        return "trackCounter equals targetTrackNum"
    end if
end tell
EOF
echo "Exit code: $?"
echo

# Test with actual track iteration (simplified)
echo "Test: Track iteration and muting"
osascript << 'EOF'
tell application "Logic Pro"
    set outputString to ""
    set targetTrackNum to 1
    set trackCounter to 1
    
    -- Get current playback state
    set wasPlaying to is playing
    set outputString to outputString & wasPlaying & linefeed
    
    -- Try to iterate first 3 tracks
    try
        repeat with i from 1 to 3
            set outputString to outputString & "Track " & i & ": "
            if i ≠ targetTrackNum then
                set outputString to outputString & "would mute" & linefeed
            else
                set outputString to outputString & "would unmute" & linefeed
            end if
        end repeat
    on error errMsg
        set outputString to outputString & "Error: " & errMsg
    end try
    
    return outputString
end tell
EOF
echo "Exit code: $?"
echo

echo "=== Test Complete ==="
