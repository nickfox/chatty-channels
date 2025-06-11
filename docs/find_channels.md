# Find Channels Implementation Plan

## Status: CRITICAL FIX REQUIRED

### Problem Summary
The ChattyChannels app is only finding 2 channel strips instead of the expected 3 (kick, snare, bass). After code review of the working `accessibility-tester` project, the root cause has been identified.

### Root Cause Analysis
The `findMixer()` function in `AccessibilityTrackDiscoveryService.swift` is using flawed logic that finds the wrong AXLayoutArea. It counts all AXLayoutItem children without validating they are actual audio channel strips.

## Code Comparison Results

### Working Code (accessibility-tester/ContentView.swift)
```swift
private func findMixer(in window: AXUIElement) -> AXUIElement? {
    // Look for a layout area that contains multiple channel strips with mute buttons
    if let mixerArea = findElementRecursive(in: window, matching: { element in
        var roleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String,
              role == kAXLayoutAreaRole as String else { return false }
        
        // Check if this layout area has multiple children that look like channel strips
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement],
              children.count >= 3 else { return false } // At least 3 channels
        
        // Check if children contain both faders and mute buttons
        var hasChannelStrips = 0
        for child in children {
            if hasSliderAndMuteButton(child) {
                hasChannelStrips += 1
            }
        }
        
        if hasChannelStrips >= 3 {
            print("Found mixer area with \(hasChannelStrips) channel strips")
            return true
        }
        
        return false
    }) {
        return mixerArea
    }
}

private func hasSliderAndMuteButton(_ element: AXUIElement) -> Bool {
    var hasSlider = false
    var hasMuteButton = false
    
    // Check if this element contains both a slider and a mute button
    _ = findElementRecursive(in: element, matching: { child in
        var roleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return false }
        
        if role == kAXSliderRole as String {
            hasSlider = true
        } else if role == kAXButtonRole as String {
            var titleValue: AnyObject?
            var descValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descValue)
            
            let title = (titleValue as? String ?? "").lowercased()
            let desc = (descValue as? String ?? "").lowercased()
            
            if title.contains("mute") || desc.contains("mute") || title == "m" {
                hasMuteButton = true
            }
        }
        
        return false // Continue searching
    })
    
    return hasSlider && hasMuteButton
}
```

### Broken Code (ChattyChannels/AccessibilityTrackDiscoveryService.swift)
```swift
private func findMixer(in window: AXUIElement) -> AXUIElement? {
    var bestMixer: AXUIElement?
    var maxChannelStripCount = 0
    
    // Look for ALL AXLayoutArea elements and find the one with the most channel strips
    // This ensures we get the main mixer, not a partial view
    _ = findElementRecursive(in: window) { element in
        var roleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return false }
        
        if role == "AXLayoutArea" {
            // Check if this layout area contains channel strips (AXLayoutItem elements)
            var childrenValue: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { return false }
            
            var channelStripCount = 0
            for child in children {
                var childRoleValue: AnyObject?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRoleValue) == .success,
                   let childRole = childRoleValue as? String,
                   childRole == "AXLayoutItem" {
                    channelStripCount += 1
                }
            }
            
            // Keep track of the mixer with the most channel strips
            if channelStripCount > maxChannelStripCount {
                maxChannelStripCount = channelStripCount
                bestMixer = element
            }
        }
        
        return false // Continue searching to find all mixers
    }
}
```

### Key Differences

1. **Validation Logic**: Working code validates each child has both sliders AND mute buttons
2. **Selection Criteria**: Working code requires at least 3 validated channel strips; broken code just counts any AXLayoutItem
3. **Return Strategy**: Working code returns first valid mixer; broken code tries to find "best" mixer

## Implementation Plan

### Step 1: Replace findMixer() Method
Replace the current `findMixer()` method in `AccessibilityTrackDiscoveryService.swift` with the proven working version.

### Step 2: Add hasSliderAndMuteButton() Helper
Add the `hasSliderAndMuteButton()` validation function to properly identify channel strips.

### Step 3: Update findElementRecursive() Usage
Ensure the `findElementRecursive()` method is being used correctly with proper matching predicates.

### Step 4: Test and Verify
1. Build and test with Logic Pro session containing kick, snare, bass tracks
2. Verify all 3 channel strips are discovered
3. Confirm track names are extracted correctly

## Files to Modify

### Primary File
- `ChattyChannels/ChattyChannels/Services/AccessibilityTrackDiscoveryService.swift`
  - Replace `findMixer()` method (lines ~136-194)
  - Add `hasSliderAndMuteButton()` helper method
  - Update logging to match working version

### Dependencies
- Ensure `findElementRecursive()` method exists and works correctly
- Verify `isValidTrackName()` and `extractTrackName()` are not filtering out valid tracks

## Current Project State

### What's Fixed
- OSC port configuration (9001) in both AIplayer plugin and ChattyChannels app
- sendRMSTelemetry exception debugging with step-by-step error isolation
- Plugin compilation and basic connectivity

### What's Broken
- Channel strip discovery finding wrong AXLayoutArea
- Only 2 tracks found instead of 3 (kick, snare, bass)

### What's Working
- Basic accessibility permissions and Logic Pro app detection
- OSC communication infrastructure
- VU meter UI and ballistics

## Expected Outcome

After implementing this fix:
1. ChattyChannels should discover all 3 channel strips: kick, snare, bass
2. Accessibility discovery should find the correct main mixer area
3. Track mapping should generate TR1, TR2, TR3 for the three audio tracks
4. Oscillator-based calibration should work with all tracks

## Testing Strategy

1. **Before Fix**: Run current code and verify only 2 tracks found
2. **Apply Fix**: Replace findMixer() with working version
3. **After Fix**: Verify all 3 tracks (kick, snare, bass) are discovered
4. **Integration Test**: Run full calibration system with updated discovery

## Priority: CRITICAL

This fix is blocking the entire v0.7 track identification system. The oscillator-based calibration cannot work properly until the accessibility discovery finds all channel strips correctly.

## References

- Working code: `/Users/nickfox137/Documents/chatty-channel/accessibility-tester/accessibility-tester/ContentView.swift`
- Broken code: `/Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/Services/AccessibilityTrackDiscoveryService.swift`
- Documentation: `/Users/nickfox137/Documents/chatty-channel/docs/accessibility.md`
- Architecture: `/Users/nickfox137/Documents/chatty-channel/CLAUDE.md`