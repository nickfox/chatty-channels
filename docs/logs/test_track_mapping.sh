#!/bin/bash
# Test the updated TrackMappingService with AXLayoutItem approach

echo "=== Testing Track Mapping Service with AXLayoutItem ==="
echo

# Create a simple Swift test to verify the AppleScript works
cat > /tmp/test_track_mapping.swift << 'EOF'
import Foundation

// Test the AppleScript directly
let script = """
on run
    tell application "Logic Pro" to activate
    delay 0.5
    
    tell application "System Events"
        tell process "Logic Pro"
            set outLines to ""
            set track_counter to 1
            
            -- Get the main window
            set mainWindow to first window
            
            -- Find all UI elements in the window
            set allElements to entire contents of mainWindow
            
            -- Look for AXLayoutItem elements containing track information
            repeat with elem in allElements
                try
                    -- Check if this is an AXLayoutItem
                    if role of elem is "AXLayoutItem" then
                        -- Get the description which contains track info
                        set elemDesc to description of elem
                        
                        -- Check if it matches pattern "Track N \"name\""
                        if elemDesc contains "Track " then
                            -- For testing, just output the raw description
                            set outLines to outLines & "Found: " & elemDesc & linefeed
                        end if
                    end if
                on error errMsg
                    -- Skip elements that cause errors
                end try
            end repeat
            
            if outLines is "" then
                return "No AXLayoutItem elements with track info found"
            else
                return outLines
            end if
        end tell
    end tell
end run
"""

// Execute the script
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", script]

let pipe = Pipe()
process.standardOutput = pipe
process.standardError = pipe

do {
    try process.run()
    process.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? "No output"
    
    print("Script output:")
    print(output)
    print("\nExit code: \(process.terminationStatus)")
} catch {
    print("Error running script: \(error)")
}
EOF

# Compile and run the test
echo "Compiling test..."
swiftc /tmp/test_track_mapping.swift -o /tmp/test_track_mapping

echo "Running test..."
/tmp/test_track_mapping

echo
echo "=== Test complete ==="
