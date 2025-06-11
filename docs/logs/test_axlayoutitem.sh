#!/bin/bash
# Test script to find track names using AXLayoutItem
# Based on the discovery that track names are in AXLayoutItem elements

echo "=== Looking for Track Names in AXLayoutItem Elements ==="
echo

osascript -e '
tell application "Logic Pro" to activate
delay 0.5

tell application "System Events"
    tell process "Logic Pro"
        set trackNames to {}
        set trackCounter to 1
        
        -- Get the main window
        set mainWindow to first window
        
        -- Find all UI elements
        set allElements to entire contents of mainWindow
        
        repeat with elem in allElements
            try
                -- Check if this is an AXLayoutItem
                if role of elem is "AXLayoutItem" then
                    -- Try to get the description which should contain track info
                    set elemDesc to description of elem
                    
                    -- Look for pattern like "Track 1 \"kick\""
                    if elemDesc contains "Track" then
                        set end of trackNames to elemDesc
                        log "Found: " & elemDesc
                    end if
                end if
            on error
                -- Skip elements that cause errors
            end try
        end repeat
        
        -- Return all found track names
        if length of trackNames > 0 then
            return "Found " & (length of trackNames) & " tracks:" & linefeed & (trackNames as string)
        else
            return "No tracks found in AXLayoutItem elements"
        end if
    end tell
end tell
'
