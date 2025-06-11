#!/bin/bash
# Test basic Logic Pro accessibility

echo "=== Testing Logic Pro Accessibility ==="
echo

# Test 1: Can we even talk to Logic Pro?
echo "Test 1: Basic Logic Pro activation"
osascript -e 'tell application "Logic Pro" to activate'
echo "Exit code: $?"
echo

# Test 2: Can we access System Events?
echo "Test 2: System Events access"
osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
echo "Exit code: $?"
echo

# Test 3: Can we see Logic Pro in System Events?
echo "Test 3: Logic Pro process visibility"
osascript -e 'tell application "System Events" to get name of process "Logic Pro"'
echo "Exit code: $?"
echo

# Test 4: Can we get the main window?
echo "Test 4: Logic Pro window access"
osascript -e 'tell application "System Events" to tell process "Logic Pro" to get name of first window'
echo "Exit code: $?"
echo

# Test 5: Simpler UI element access
echo "Test 5: Simple UI element count"
osascript -e 'tell application "System Events" to tell process "Logic Pro" to tell first window to count UI elements'
echo "Exit code: $?"
echo

# Test 6: Try the known working script
echo "Test 6: Direct AXLayoutItem search (simplified)"
osascript << 'EOF'
tell application "Logic Pro" to activate
delay 1

tell application "System Events"
    tell process "Logic Pro"
        set trackCount to 0
        try
            set w to first window
            set allElements to entire contents of w
            
            repeat with elem in allElements
                try
                    if role of elem is "AXLayoutItem" then
                        set d to description of elem
                        if d contains "Track" then
                            log d
                            set trackCount to trackCount + 1
                        end if
                    end if
                end try
            end repeat
            
            return "Found " & trackCount & " track elements"
        on error errMsg
            return "Error: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 7: Test the "playing" property that's causing calibration to fail
echo "Test 7: Logic Pro 'playing' property (broken version)"
osascript -e 'tell application "Logic Pro" to return playing'
echo "Exit code: $?"
echo

echo "Test 8: Logic Pro 'playing' property (fixed version)"
osascript -e 'tell application "Logic Pro"
    set isPlaying to playing
    return isPlaying
end tell'
echo "Exit code: $?"
echo

# Test 9: AppleScript audio insertion capabilities
echo "Test 9: Can we create a software instrument on a track?"
osascript << 'EOF'
tell application "Logic Pro"
    try
        -- Try to get track 1 and add a software instrument
        set track1 to track 1
        create software instrument track 1
        return "Success: Created software instrument"
    on error errMsg
        return "Error creating software instrument: " & errMsg
    end try
end tell
EOF
echo

# Test 10: Test oscillator or tone generator access
echo "Test 10: Can we access Logic's built-in Test Oscillator?"
osascript << 'EOF'
tell application "Logic Pro"
    try
        -- Look for test oscillator in the plugin menu
        -- This might not work but worth trying
        set result to "Investigating test oscillator access..."
        return result
    on error errMsg
        return "Error: " & errMsg
    end try
end tell
EOF
echo

# Test 11: Record enable button accessibility
echo "Test 11: Can we find and toggle record enable buttons via accessibility?"
osascript << 'EOF'
tell application "System Events"
    tell process "Logic Pro"
        try
            set w to first window
            -- Look for record enable buttons (typically red "R" buttons)
            set recButtons to every button of w whose title contains "R" or description contains "record"
            return "Found " & (count of recButtons) & " potential record buttons"
        on error errMsg
            return "Error finding record buttons: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 12: Metronome accessibility 
echo "Test 12: Can we find and trigger the metronome via accessibility?"
osascript << 'EOF'
tell application "System Events"
    tell process "Logic Pro"
        try
            set w to first window
            -- Look for metronome button (could be useful as a test signal)
            set metroButtons to every button of w whose title contains "metro" or description contains "metro" or title contains "click"
            return "Found " & (count of metroButtons) & " potential metronome buttons"
        on error errMsg
            return "Error finding metronome: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 13: Solo button investigation (alternative to mute)
echo "Test 13: Can we find Solo buttons and use them instead of mute?"
osascript << 'EOF'
tell application "System Events"
    tell process "Logic Pro"
        try
            set w to first window
            -- Look for solo buttons (typically "S" buttons, might be better than mute)
            set soloButtons to every button of w whose title contains "S" or description contains "solo"
            return "Found " & (count of soloButtons) & " potential solo buttons"
        on error errMsg
            return "Error finding solo buttons: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 14: Creative - Can we trigger keyboard shortcuts for test tone?
echo "Test 14: Can we trigger Logic's test tone via keyboard shortcut?"
osascript << 'EOF'
tell application "System Events"
    tell process "Logic Pro"
        try
            -- Some DAWs have test tone generators accessible via shortcuts
            -- This is a long shot but worth exploring
            key code 18 using {command down, option down} -- Random test shortcut
            delay 0.1
            return "Attempted test tone keyboard shortcut"
        on error errMsg
            return "Error with keyboard shortcut: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 15: Input monitoring buttons (creative signal source)
echo "Test 15: Can we find and toggle input monitoring buttons?"
osascript << 'EOF'
tell application "System Events"
    tell process "Logic Pro"
        try
            set w to first window
            -- Look for input monitoring buttons (might create detectable signal)
            set inputButtons to every button of w whose title contains "I" or description contains "input" or description contains "monitor"
            return "Found " & (count of inputButtons) & " potential input monitoring buttons"
        on error errMsg
            return "Error finding input monitoring: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 16: Plugin bypass buttons (another creative approach)
echo "Test 16: Can we find plugin bypass buttons on channel strips?"
osascript << 'EOF'
tell application "System Events"
    tell process "Logic Pro"
        try
            set w to first window
            -- Look for plugin bypass or enable buttons
            set bypassButtons to every button of w whose description contains "bypass" or description contains "plugin" or title contains "bypass"
            return "Found " & (count of bypassButtons) & " potential plugin bypass buttons"
        on error errMsg
            return "Error finding bypass buttons: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 17: Track selection as signal (very creative)
echo "Test 17: Can track selection itself be detected? (Track focus/selection)"
osascript << 'EOF'
tell application "System Events"
    tell process "Logic Pro"
        try
            set w to first window
            -- See if we can select different tracks and if that affects plugin behavior
            -- This is a long shot but some plugins might respond to track selection
            click (first button of w whose description contains "Track" or title contains "Track")
            return "Attempted track selection"
        on error errMsg
            return "Error with track selection: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 18: Pan controls (stereo position as identification signal)
echo "Test 18: Can we find and manipulate pan controls for identification?"
osascript << 'EOF'
tell application "System Events"
    tell process "Logic Pro"
        try
            set w to first window
            -- Look for pan knobs or sliders - could temporarily pan tracks hard left/right as identification
            set panControls to every slider of w whose description contains "pan" or title contains "pan"
            return "Found " & (count of panControls) & " potential pan controls"
        on error errMsg
            return "Error finding pan controls: " & errMsg
        end try
    end tell
end tell
EOF
echo

# Test 19: The really creative one - volume automation as identification
echo "Test 19: Can we create temporary volume automation as identification signal?"
osascript << 'EOF'
tell application "Logic Pro"
    try
        -- This is very experimental - try to create a brief volume change
        -- that plugins might be able to detect as an identification signature
        set track1 to track 1
        set output volume of track1 to -20
        delay 0.1
        set output volume of track1 to 0
        return "Attempted volume automation signature"
    on error errMsg
        return "Error with volume automation: " & errMsg
    end try
end tell
EOF
echo

# Test 20: AppleScript Introspection - What's actually available?
echo "Test 20: Logic Pro AppleScript introspection - get every property"
osascript << 'EOF'
tell application "Logic Pro"
    try
        get every property
    on error errMsg
        return "Error getting properties: " & errMsg
    end try
end tell
EOF
echo

echo "Test 21: Logic Pro AppleScript introspection - get every element"
osascript << 'EOF'
tell application "Logic Pro"
    try
        get every element
    on error errMsg
        return "Error getting elements: " & errMsg
    end try
end tell
EOF
echo

echo "Test 22: Logic Pro AppleScript introspection - get class"
osascript << 'EOF'
tell application "Logic Pro"
    try
        get class
    on error errMsg
        return "Error getting class: " & errMsg
    end try
end tell
EOF
echo

echo "Test 23: Logic Pro AppleScript introspection - application properties"
osascript << 'EOF'
tell application "Logic Pro"
    try
        properties
    on error errMsg
        return "Error getting application properties: " & errMsg
    end try
end tell
EOF
echo

echo "Test 24: Logic Pro AppleScript introspection - what commands are supported?"
osascript << 'EOF'
tell application "Logic Pro"
    try
        -- Try to get info about supported commands
        get info for (path to me)
    on error errMsg
        return "Error getting command info: " & errMsg
    end try
end tell
EOF
echo

echo "Test 25: Logic Pro AppleScript introspection - application elements"
osascript << 'EOF'
tell application "Logic Pro"
    try
        count elements
    on error errMsg
        return "Error counting elements: " & errMsg
    end try
end tell
EOF
echo

echo "Test 26: Logic Pro AppleScript introspection - application object model"
osascript << 'EOF'
tell application "Logic Pro"
    try
        -- Get the application object itself and see what it contains
        get application "Logic Pro"
    on error errMsg
        return "Error getting application object: " & errMsg
    end try
end tell
EOF
echo

echo "=== AppleScript Introspection Complete ==="
echo "=== Creative Outside-the-Box Accessibility Test Complete ==="
