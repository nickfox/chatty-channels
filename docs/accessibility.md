# Logic Pro Accessibility Control - Findings and Implementation Guide

## Overview
This document summarizes our findings from building an accessibility-based Logic Pro controller app. The goal was to understand how to programmatically control Logic Pro's mixer using macOS accessibility APIs, specifically targeting volume faders and mute buttons.

## Key Discoveries

### 1. Logic Pro's UI Structure
Logic Pro's mixer is organized hierarchically:
```
Window
├── Mixer Area (AXLayoutArea)
│   ├── Channel Strip 0 (AXLayoutItem) - "kick"
│   ├── Channel Strip 1 (AXLayoutItem) - "snare" 
│   ├── Channel Strip 2 (AXLayoutItem) - "bass"
│   ├── Channel Strip 3 (AXLayoutItem) - "Stereo Out"
│   └── Channel Strip 4 (AXLayoutItem) - "Master"
```

Each channel strip contains:
- **Volume Fader**: `AXSlider` with description "volume fader" (range 0-233)
- **Pan Control**: `AXSlider` with description "pan" (range -64 to 63)
- **Input Gain**: `AXSlider` with description "input gain" (range -8 to 10)
- **Mute Button**: `AXButton` with "mute" in title/description

### 2. Critical Accessibility Methods

#### Volume Control - What DOESN'T Work:
- **`AXUIElementSetAttributeValue`**: Only allows minimal changes (~1-2 points) despite requesting larger values
- Logic Pro appears to have internal safety constraints preventing large volume jumps

#### Volume Control - What WORKS:
- **`AXUIElementPerformAction` with `AXIncrement`/`AXDecrement`**: Each action moves ~10 points
- This provides smooth, predictable volume changes
- Can achieve visible 25% movements (58+ points) reliably

#### Mute Control - What WORKS:
- **`AXUIElementPerformAction` with `kAXPressAction`**: Standard button press action
- **State Reading**: Use `kAXValueAttribute` to read current mute state (Int, Bool, or NSNumber)
- **State Verification**: Read state before and after button press to confirm toggle
- **Reliable Toggle**: Works consistently across all channel types
- **Button Identification**: Look for buttons with "mute" in title/description, or single "m" title

### 3. Logic Pro Volume Scale
- **Range**: 0-233 points (not the typical 0.0-1.0 range)
- **Current values**: Typically around 170-180 for normal levels
- **25% increment**: ~58 points (233 × 0.25)
- **Movement per action**: ~10 points per AXIncrement/AXDecrement

### 4. Channel Identification Strategy
Channels are identified by:
1. **Index-based targeting**: Channel strips appear in order (0=first audio channel)
2. **Description matching**: Each channel has a description (track name)
3. **Generic identifiers**: Look for "Audio 1", "Track 1", "Channel 1", etc.

## Implementation Code Patterns

### Finding the Mixer
```swift
private func findMixer(in window: AXUIElement) -> AXUIElement? {
    // Look for AXLayoutArea containing multiple channel strips
    // Each channel strip should have both sliders and mute buttons
}
```

### Channel Strip Access
```swift
private func getChannelStrip(from mixer: AXUIElement, at index: Int) -> AXUIElement? {
    // Get child at specific index
    // Channel strips are AXLayoutItem elements with descriptive names
}
```

### Volume Fader Control
```swift
private func findVolumeSlider(in channelStrip: AXUIElement) -> AXUIElement? {
    var allSliders: [(AXUIElement, String, String)] = []
    
    // Collect all sliders in the channel strip
    _ = findElementRecursive(in: channelStrip) { element in
        var roleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String,
              role == kAXSliderRole as String else { return false }
        
        var titleValue: AnyObject?, descValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        
        let title = titleValue as? String ?? ""
        let desc = descValue as? String ?? ""
        allSliders.append((element, title, desc))
        return false // Continue searching
    }
    
    // Look for volume-related keywords first
    for (slider, title, desc) in allSliders {
        if title.lowercased().contains("volume") || title.lowercased().contains("fader") ||
           desc.lowercased().contains("volume") || desc.lowercased().contains("fader") {
            return slider
        }
    }
    
    // Fallback: find slider with widest range (main volume fader has 0-233 range)
    var bestSlider: AXUIElement?
    var bestRange: Double = 0
    
    for (slider, _, _) in allSliders {
        var minValueObj: AnyObject?, maxValueObj: AnyObject?
        if AXUIElementCopyAttributeValue(slider, kAXMinValueAttribute as CFString, &minValueObj) == .success,
           AXUIElementCopyAttributeValue(slider, kAXMaxValueAttribute as CFString, &maxValueObj) == .success,
           let minValue = (minValueObj as? NSNumber)?.doubleValue,
           let maxValue = (maxValueObj as? NSNumber)?.doubleValue {
            let range = maxValue - minValue
            if range > bestRange {
                bestRange = range
                bestSlider = slider
            }
        }
    }
    
    return bestSlider
}

private func toggleVolume(slider: AXUIElement, channelIndex: Int, channelName: String) {
    // Get current value
    var valueObj: AnyObject?
    guard AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
          let currentValue = (valueObj as? NSNumber)?.doubleValue else { return }
    
    // Get min/max range for percentage calculation
    var minValueObj: AnyObject?, maxValueObj: AnyObject?
    guard AXUIElementCopyAttributeValue(slider, kAXMinValueAttribute as CFString, &minValueObj) == .success,
          AXUIElementCopyAttributeValue(slider, kAXMaxValueAttribute as CFString, &maxValueObj) == .success,
          let minValue = (minValueObj as? NSNumber)?.doubleValue,
          let maxValue = (maxValueObj as? NSNumber)?.doubleValue else { return }
    
    // Calculate 25% movement
    let totalRange = maxValue - minValue
    let percentageIncrement = totalRange * 0.25
    
    let newValue: Double
    if currentValue < (minValue + maxValue) / 2.0 {
        newValue = min(maxValue, currentValue + percentageIncrement)
        print("Channel \(channelIndex + 1) (\(channelName)): \(currentValue) -> \(newValue) (+\(percentageIncrement))")
    } else {
        newValue = max(minValue, currentValue - percentageIncrement)
        print("Channel \(channelIndex + 1) (\(channelName)): \(currentValue) -> \(newValue) (-\(percentageIncrement))")
    }
    
    // Use AXIncrement/AXDecrement actions (each moves ~10 points)
    var actions: CFArray?
    guard AXUIElementCopyActionNames(slider, &actions) == .success,
          let actionList = actions as? [String],
          (actionList.contains("AXIncrement") || actionList.contains("AXDecrement")) else { return }
    
    let targetChange = newValue - currentValue
    let action = targetChange > 0 ? "AXIncrement" : "AXDecrement"
    let actionCount = Int(abs(targetChange) / 10.0)
    
    for _ in 0..<actionCount {
        AXUIElementPerformAction(slider, action as CFString)
        Thread.sleep(forTimeInterval: 0.01)
    }
    
    // Verify final value
    Thread.sleep(forTimeInterval: 0.1)
    if AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
       let finalValue = (valueObj as? NSNumber)?.doubleValue {
        let actualChange = abs(finalValue - currentValue)
        print("Channel \(channelIndex + 1) (\(channelName)): Final value \(finalValue) (moved \(actualChange) points)")
    }
}
```

### Mute Button Control
```swift
private func findMuteButton(in channelStrip: AXUIElement) -> AXUIElement? {
    return findElementRecursive(in: channelStrip) { element in
        var roleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String,
              role == kAXButtonRole as String else { return false }
        
        // Check title and description for "mute"
        var titleValue: AnyObject?
        var descValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        
        let title = (titleValue as? String ?? "").lowercased()
        let desc = (descValue as? String ?? "").lowercased()
        
        return title.contains("mute") || desc.contains("mute") || title == "m"
    }
}

private func toggleMute(button: AXUIElement) {
    // Read current state
    var valueObj: AnyObject?
    let currentState: Bool
    if AXUIElementCopyAttributeValue(button, kAXValueAttribute as CFString, &valueObj) == .success {
        if let value = valueObj as? Int {
            currentState = value != 0
        } else if let value = valueObj as? Bool {
            currentState = value
        } else if let value = valueObj as? NSNumber {
            currentState = value.boolValue
        } else {
            currentState = false
        }
    } else {
        currentState = false
    }
    
    // Press the button
    let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
    
    if result == .success {
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify state change
        if AXUIElementCopyAttributeValue(button, kAXValueAttribute as CFString, &valueObj) == .success {
            let newState = (valueObj as? NSNumber)?.boolValue ?? false
            print("Mute toggled: \(currentState ? "ON" : "OFF") -> \(newState ? "ON" : "OFF")")
        }
    }
}
```

## Required Permissions & Setup

### Entitlements
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

### Info.plist
```xml
<key>NSAppleEventsUsageDescription</key>
<string>This app needs accessibility access to control Logic Pro</string>
```

### Runtime Permission Check
```swift
let trusted = AXIsProcessTrusted()
if !trusted {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    AXIsProcessTrustedWithOptions(options as CFDictionary)
}
```

## Best Practices for Parent App Implementation

### 1. Error Handling
- Always check `AXIsProcessTrusted()` before operations
- Verify Logic Pro is running: `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10")`
- Handle cases where mixer is not visible or accessible

### 2. User Feedback
- Provide clear console logging: `"Channel 1 (kick): 160.0 -> 210.0 (+50.0)"`
- Show channel name, current value, target value, and actual movement
- Indicate success/failure of operations

### 3. Performance Considerations
- Use small delays between actions (0.01s) for smooth animation
- Batch operations when possible
- Cache slider references rather than searching repeatedly

### 4. Safety Constraints
- Respect Logic Pro's apparent safety limits (don't force huge jumps)
- Use incremental actions rather than direct value setting
- Verify actual movement matches expectations

### 5. Channel Mapping
- Map logical channel numbers (1, 2, 3...) to array indices (0, 1, 2...)
- Store channel names for user-friendly identification
- Handle dynamic channel configurations (tracks added/removed)

## Integration Notes for Chatty Channels

1. **Use AXIncrement/AXDecrement exclusively** for volume changes
2. **Calculate movement in 10-point increments** for accurate targeting
3. **Implement channel discovery** to map track names to indices
4. **Provide real-time feedback** showing which channel is being controlled
5. **Handle Logic Pro not running** gracefully
6. **Consider caching** mixer structure for performance

## Testing Methodology
This test app proved invaluable for understanding Logic Pro's accessibility behavior without polluting the main application. The iterative approach of testing different methods (direct setting vs incremental actions) revealed the key insights needed for reliable control.

**Key Lesson**: Professional audio software often implements safety constraints that aren't immediately obvious. Testing with a dedicated test app allows discovery of these limitations and workarounds.