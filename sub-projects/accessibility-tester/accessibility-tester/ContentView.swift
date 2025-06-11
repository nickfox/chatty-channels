//
//  ContentView.swift
//  accessibility-tester
//
//  Created by Nick on 6/8/25.
//

import SwiftUI
import ApplicationServices

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Button("Toggle Channel 1 Mute") {
                toggleChannel1Mute()
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            Button("Toggle Channel 1 Volume") {
                toggleChannel1Volume()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(width: 300, height: 150)
        .padding()
    }
    
    private func toggleChannel1Mute() {
        print("Attempting to control Logic Pro...")
        
        // First check without prompting
        let trusted = AXIsProcessTrusted()
        print("Current accessibility status: \(trusted ? "Trusted" : "Not Trusted")")
        
        if !trusted {
            // Now prompt if needed
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            if !accessEnabled {
                print("Please grant accessibility access in System Settings > Privacy & Security > Accessibility")
                print("After granting access, you may need to restart the app")
                return
            }
        }
        
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10")
        
        guard let logicApp = runningApps.first else {
            print("Logic Pro is not running")
            return
        }
        
        let pid = logicApp.processIdentifier
        print("Logic Pro PID: \(pid)")
        
        let appElement = AXUIElementCreateApplication(pid)
        
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        
        print("Window access result: \(result.rawValue)")
        
        guard result == .success else {
            print("Failed to get windows. Error code: \(result.rawValue)")
            print("Make sure you've granted accessibility permissions to this app")
            return
        }
        
        guard let windows = value as? [AXUIElement], !windows.isEmpty else {
            print("No windows found or wrong type. Value type: \(type(of: value))")
            return
        }
        
        print("Found \(windows.count) window(s)")
        
        let mainWindow = windows[0]
        
        // Try to expand mixer view first
        expandMixerView(in: mainWindow)
        
        if let mixer = findMixer(in: mainWindow) {
            print("\nSearching for channel strips...")
            
            // Target channel 1 (first audio channel, index 0)
            if let channelStrip = getChannelStrip(from: mixer, at: 0) {
                var titleValue: AnyObject?
                var descValue: AnyObject?
                AXUIElementCopyAttributeValue(channelStrip, kAXTitleAttribute as CFString, &titleValue)
                AXUIElementCopyAttributeValue(channelStrip, kAXDescriptionAttribute as CFString, &descValue)
                
                let title = titleValue as? String ?? ""
                let desc = descValue as? String ?? ""
                print("Targeting channel 1 (index 0): Title='\(title)', Desc='\(desc)'")
                
                if let muteButton = findMuteButton(in: channelStrip) {
                    toggleMute(button: muteButton)
                } else {
                    print("Could not find mute button in channel strip")
                }
            } else {
                print("Could not find channel strip at index 0")
            }
        } else {
            print("Could not find mixer. Make sure the mixer is visible in Logic Pro")
        }
    }
    
    private func toggleChannel1Volume() {
        print("Attempting to control Logic Pro volume...")
        
        // First check without prompting
        let trusted = AXIsProcessTrusted()
        print("Current accessibility status: \(trusted ? "Trusted" : "Not Trusted")")
        
        if !trusted {
            // Now prompt if needed
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            if !accessEnabled {
                print("Please grant accessibility access in System Settings > Privacy & Security > Accessibility")
                print("After granting access, you may need to restart the app")
                return
            }
        }
        
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10")
        
        guard let logicApp = runningApps.first else {
            print("Logic Pro is not running")
            return
        }
        
        let pid = logicApp.processIdentifier
        print("Logic Pro PID: \(pid)")
        
        let appElement = AXUIElementCreateApplication(pid)
        
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        
        print("Window access result: \(result.rawValue)")
        
        guard result == .success else {
            print("Failed to get windows. Error code: \(result.rawValue)")
            return
        }
        
        guard let windows = value as? [AXUIElement], !windows.isEmpty else {
            print("No windows found or wrong type. Value type: \(type(of: value))")
            return
        }
        
        print("Found \(windows.count) window(s)")
        
        let mainWindow = windows[0]
        
        // Try to expand mixer view first
        expandMixerView(in: mainWindow)
        
        if let mixer = findMixer(in: mainWindow) {
            print("\nSearching for volume fader...")
            
            // Target channel 1 (first audio channel, index 0)
            if let channelStrip = getChannelStrip(from: mixer, at: 0) {
                var titleValue: AnyObject?
                var descValue: AnyObject?
                AXUIElementCopyAttributeValue(channelStrip, kAXTitleAttribute as CFString, &titleValue)
                AXUIElementCopyAttributeValue(channelStrip, kAXDescriptionAttribute as CFString, &descValue)
                
                let title = titleValue as? String ?? ""
                let desc = descValue as? String ?? ""
                
                if let volumeSlider = findVolumeSlider(in: channelStrip) {
                    toggleVolume(slider: volumeSlider, channelIndex: 0, channelName: desc)
                } else {
                    print("Could not find volume slider in channel strip")
                }
            } else {
                print("Could not find channel strip at index 0")
            }
        } else {
            print("Could not find mixer. Make sure the mixer is visible in Logic Pro")
        }
    }
    
    private func expandMixerView(in window: AXUIElement) {
        print("Attempting to expand mixer view...")
        
        // Search for various buttons that might expand the mixer view
        let expandButton = findElementRecursive(in: window) { element in
            var roleValue: AnyObject?
            var titleValue: AnyObject?
            var descValue: AnyObject?
            
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String,
                  (role == kAXButtonRole as String || role == kAXMenuButtonRole as String || role == kAXPopUpButtonRole as String) else { return false }
            
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
            
            let title = (titleValue as? String ?? "").lowercased()
            let desc = (descValue as? String ?? "").lowercased()
            
            // Look for various mixer view options
            let keywords = ["all", "tracks", "mixer", "view", "single", "selected", "channel"]
            for keyword in keywords {
                if title.contains(keyword) || desc.contains(keyword) {
                    print("Found potential mixer control: '\(title)' / '\(desc)'")
                    return true
                }
            }
            
            return false
        }
        
        if let button = expandButton {
            print("Attempting to click mixer view control...")
            let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
            if result == .success {
                print("Successfully clicked mixer control")
                Thread.sleep(forTimeInterval: 0.8) // Wait for view to update
            } else {
                print("Failed to click mixer control")
            }
        } else {
            // Try using Logic Pro's menu to show all mixer channels
            print("No mixer view button found, trying menu approach...")
            tryMenuApproach()
        }
    }
    
    private func tryMenuApproach() {
        // Try to use Logic Pro's View menu to show all mixer channels
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first?.processIdentifier ?? 0
        let appElement = AXUIElementCreateApplication(pid)
        
        // Look for menu bar
        var menuBarValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
           let menuBar = menuBarValue {
            
            // Look for "View" menu
            if findMenuWithTitle(in: menuBar, title: "View") != nil {
                print("Found View menu, looking for mixer options...")
                // This would require more complex menu navigation
            } else {
                print("Could not find View menu")
            }
        }
    }
    
    private func findMenuWithTitle(in menuBar: AnyObject, title: String) -> AXUIElement? {
        let menuBarElement = menuBar as! AXUIElement
        
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        
        for child in children {
            var titleValue: AnyObject?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue) == .success,
               let menuTitle = titleValue as? String,
               menuTitle.lowercased().contains(title.lowercased()) {
                return child
            }
        }
        return nil
    }
    
    private func sendKeyboardShortcut() {
        print("Trying keyboard shortcut to show all mixer channels...")
        
        // Create and post keyboard events for Command+Option+M (common Logic Pro mixer shortcut)
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key down events
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) // Command
        let optDown = CGEvent(keyboardEventSource: source, virtualKey: 0x3A, keyDown: true) // Option
        let mDown = CGEvent(keyboardEventSource: source, virtualKey: 0x2E, keyDown: true)   // M
        
        // Key up events
        let mUp = CGEvent(keyboardEventSource: source, virtualKey: 0x2E, keyDown: false)
        let optUp = CGEvent(keyboardEventSource: source, virtualKey: 0x3A, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        // Set modifier flags
        cmdDown?.flags = .maskCommand
        optDown?.flags = [.maskCommand, .maskAlternate]
        mDown?.flags = [.maskCommand, .maskAlternate]
        mUp?.flags = [.maskCommand, .maskAlternate]
        optUp?.flags = .maskCommand
        
        // Post events in sequence
        cmdDown?.post(tap: .cghidEventTap)
        optDown?.post(tap: .cghidEventTap)
        mDown?.post(tap: .cghidEventTap)
        
        Thread.sleep(forTimeInterval: 0.1)
        
        mUp?.post(tap: .cghidEventTap)
        optUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        Thread.sleep(forTimeInterval: 0.5) // Wait for Logic to respond
        print("Keyboard shortcut sent")
    }
    
    private func findMixer(in window: AXUIElement) -> AXUIElement? {
        // Look for the actual mixer section with channel strips and mute buttons
        print("Searching for mixer with channel strips...")
        
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
        
        // Fallback to previous approach
        print("No dedicated mixer area found, trying layout areas with sliders...")
        if let layoutArea = findLayoutAreaWithSliders(in: window) {
            print("Found layout area with sliders")
            return layoutArea
        }
        
        return nil
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
    
    private func findElementRecursive(in element: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        if predicate(element) {
            return element
        }
        
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            if let found = findElementRecursive(in: child, matching: predicate) {
                return found
            }
        }
        
        return nil
    }
    
    private func findLayoutAreaWithSliders(in element: AXUIElement) -> AXUIElement? {
        return findElementRecursive(in: element) { element in
            var roleValue: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String,
                  role == kAXLayoutAreaRole as String else { return false }
            
            // Check if this layout area contains sliders
            var childrenValue: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { return false }
            
            // Look for children that might be channel strips (groups containing sliders)
            for child in children {
                if containsSlider(child) {
                    return true
                }
            }
            
            return false
        }
    }
    
    private func containsSlider(_ element: AXUIElement) -> Bool {
        var roleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String,
           role == kAXSliderRole as String {
            return true
        }
        
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return false
        }
        
        for child in children {
            if containsSlider(child) {
                return true
            }
        }
        
        return false
    }
    
    private func findLayoutArea(in mixer: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(mixer, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            var roleValue: AnyObject?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String,
               role == kAXLayoutAreaRole as String {
                return child
            }
        }
        return nil
    }
    
    private func findChannel1(in layoutArea: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(layoutArea, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return nil
        }
        
        // Look for a channel strip that contains "1" or "Audio 1" in its labels
        for child in children {
            if isChannel1(child) {
                return child
            }
        }
        
        return nil
    }
    
    private func isChannel1(_ element: AXUIElement) -> Bool {
        // Check if this element or its children contain channel 1 identifiers
        return findElementRecursive(in: element) { elem in
            var titleValue: AnyObject?
            var descValue: AnyObject?
            
            AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleValue)
            AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descValue)
            
            let title = titleValue as? String ?? ""
            let desc = descValue as? String ?? ""
            
            // Look for generic channel 1 identifiers only - no hardcoded track names
            let identifiers = ["Audio 1", "Track 1", "Channel 1", "Ch 1"]
            for identifier in identifiers {
                if title.contains(identifier) || desc.contains(identifier) {
                    print("Found channel identifier: '\(identifier)' in element (title: '\(title)', desc: '\(desc)')")
                    return true
                }
            }
            
            // Also check for just "1" if it's a static text element
            var roleValue: AnyObject?
            if AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String,
               role == kAXStaticTextRole as String {
                if title == "1" {
                    print("Found channel number '1' in static text")
                    return true
                }
            }
            
            return false
        } != nil
    }
    
    private func getChannelStrip(from layoutArea: AXUIElement, at index: Int) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(layoutArea, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return nil
        }
        
        print("Layout area has \(children.count) children")
        
        // Let's examine what these children are
        for (i, child) in children.enumerated() {
            var roleValue: AnyObject?
            var titleValue: AnyObject?
            var descValue: AnyObject?
            
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descValue)
            
            let role = roleValue as? String ?? "unknown"
            let title = titleValue as? String ?? ""
            let desc = descValue as? String ?? ""
            
            if i < 5 {  // Show first 5 to understand the structure
                print("Child \(i): Role=\(role), Title='\(title)', Desc='\(desc)'")
            }
        }
        
        if index < children.count {
            return children[index]
        } else {
            print("Requested index \(index) is out of bounds")
            return nil
        }
    }
    
    private func findMuteButton(in channelStrip: AXUIElement) -> AXUIElement? {
        return findElementRecursive(in: channelStrip) { element in
            var roleValue: AnyObject?
            var titleValue: AnyObject?
            
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String,
                  role == kAXButtonRole as String else { return false }
            
            // Check if it has "Mute" in title or description
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String,
               title.lowercased().contains("mute") {
                return true
            }
            
            var descValue: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue) == .success,
               let desc = descValue as? String,
               desc.lowercased().contains("mute") {
                return true
            }
            
            return false
        }
    }
    
    private func toggleMute(button: AXUIElement) {
        // Check current state of mute button
        var valueObj: AnyObject?
        let currentState: Bool
        
        if AXUIElementCopyAttributeValue(button, kAXValueAttribute as CFString, &valueObj) == .success {
            if let value = valueObj as? Int {
                currentState = value != 0
                print("Mute button current state: \(currentState ? "ON (muted)" : "OFF (unmuted)")")
            } else if let value = valueObj as? Bool {
                currentState = value
                print("Mute button current state: \(currentState ? "ON (muted)" : "OFF (unmuted)")")
            } else if let value = valueObj as? NSNumber {
                currentState = value.boolValue
                print("Mute button current state: \(currentState ? "ON (muted)" : "OFF (unmuted)")")
            } else {
                print("Unknown mute button value type: \(type(of: valueObj)), value: \(String(describing: valueObj))")
                currentState = false
            }
        } else {
            print("Could not read mute button state")
            currentState = false
        }
        
        // Press the button to toggle
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        
        if result == .success {
            print("Successfully clicked mute button")
            
            // Wait a moment for the action to complete
            Thread.sleep(forTimeInterval: 0.1)
            
            // Check new state
            if AXUIElementCopyAttributeValue(button, kAXValueAttribute as CFString, &valueObj) == .success {
                if let value = valueObj as? Int {
                    let newState = value != 0
                    print("Mute button new state: \(newState ? "ON (muted)" : "OFF (unmuted)")")
                    print("Mute toggled: \(currentState ? "ON" : "OFF") -> \(newState ? "ON" : "OFF")")
                } else if let value = valueObj as? Bool {
                    let newState = value
                    print("Mute button new state: \(newState ? "ON (muted)" : "OFF (unmuted)")")
                    print("Mute toggled: \(currentState ? "ON" : "OFF") -> \(newState ? "ON" : "OFF")")
                } else if let value = valueObj as? NSNumber {
                    let newState = value.boolValue
                    print("Mute button new state: \(newState ? "ON (muted)" : "OFF (unmuted)")")
                    print("Mute toggled: \(currentState ? "ON" : "OFF") -> \(newState ? "ON" : "OFF")")
                }
            }
        } else {
            print("Failed to click mute button. Error code: \(result.rawValue)")
            
            // Show available actions
            var actions: CFArray?
            if AXUIElementCopyActionNames(button, &actions) == .success,
               let actionList = actions as? [String] {
                print("Available actions for mute button: \(actionList)")
            }
        }
    }
    
    private func findVolumeSlider(in channelStrip: AXUIElement) -> AXUIElement? {
        var allSliders: [(AXUIElement, String, String)] = []
        
        // First, collect all sliders in the channel strip
        _ = findElementRecursive(in: channelStrip) { element in
            var roleValue: AnyObject?
            
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String,
                  role == kAXSliderRole as String else { return false }
            
            // Get title and description for this slider
            var titleValue: AnyObject?
            var descValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
            
            let title = titleValue as? String ?? ""
            let desc = descValue as? String ?? ""
            
            allSliders.append((element, title, desc))
            return false // Continue searching for all sliders
        }
        
        print("Found \(allSliders.count) sliders in channel strip:")
        for (index, (slider, title, desc)) in allSliders.enumerated() {
            // Also get current value and range for each slider
            var valueObj: AnyObject?
            var minValueObj: AnyObject?
            var maxValueObj: AnyObject?
            
            let currentValue = AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success ? (valueObj as? NSNumber)?.doubleValue ?? 0 : 0
            let minValue = AXUIElementCopyAttributeValue(slider, kAXMinValueAttribute as CFString, &minValueObj) == .success ? (minValueObj as? NSNumber)?.doubleValue ?? 0 : 0
            let maxValue = AXUIElementCopyAttributeValue(slider, kAXMaxValueAttribute as CFString, &maxValueObj) == .success ? (maxValueObj as? NSNumber)?.doubleValue ?? 0 : 0
            
            print("  Slider \(index): Title='\(title)', Desc='\(desc)', Value=\(currentValue), Range=\(minValue)-\(maxValue)")
        }
        
        // Look for the main volume fader - typically this would be:
        // 1. The slider with the widest range (0-233 as we've seen)
        // 2. Or one with "volume" or "fader" in its description
        // 3. Or the tallest/main slider (but we can't easily get size info)
        
        // First try to find one with volume-related keywords
        for (slider, title, desc) in allSliders {
            let titleLower = title.lowercased()
            let descLower = desc.lowercased()
            
            if titleLower.contains("volume") || titleLower.contains("fader") || titleLower.contains("level") ||
               descLower.contains("volume") || descLower.contains("fader") || descLower.contains("level") {
                print("Selected slider with volume keyword: Title='\(title)', Desc='\(desc)'")
                return slider
            }
        }
        
        // If no volume keywords found, look for the slider with the widest range (likely the main fader)
        var bestSlider: AXUIElement?
        var bestRange: Double = 0
        
        for (slider, title, desc) in allSliders {
            var minValueObj: AnyObject?
            var maxValueObj: AnyObject?
            
            if AXUIElementCopyAttributeValue(slider, kAXMinValueAttribute as CFString, &minValueObj) == .success,
               AXUIElementCopyAttributeValue(slider, kAXMaxValueAttribute as CFString, &maxValueObj) == .success,
               let minValue = (minValueObj as? NSNumber)?.doubleValue,
               let maxValue = (maxValueObj as? NSNumber)?.doubleValue {
                
                let range = maxValue - minValue
                if range > bestRange {
                    bestRange = range
                    bestSlider = slider
                    print("Found slider with larger range (\(range)): Title='\(title)', Desc='\(desc)'")
                }
            }
        }
        
        if let slider = bestSlider {
            print("Selected slider with widest range (\(bestRange))")
            return slider
        }
        
        // Fallback to first slider if we found any
        if let firstSlider = allSliders.first {
            print("Fallback: using first slider found")
            return firstSlider.0
        }
        
        return nil
    }
    
    private func toggleVolume(slider: AXUIElement, channelIndex: Int, channelName: String) {
        // Get current volume level
        var valueObj: AnyObject?
        
        guard AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success else {
            print("Could not read current volume value")
            return
        }
        
        let currentValue: Double
        if let value = valueObj as? Double {
            currentValue = value
        } else if let value = valueObj as? Float {
            currentValue = Double(value)
        } else if let value = valueObj as? NSNumber {
            currentValue = value.doubleValue
        } else {
            print("Unknown volume value type: \(type(of: valueObj)), value: \(String(describing: valueObj))")
            return
        }
        
        // Get the slider's min/max values to calculate proper percentage
        var minValueObj: AnyObject?
        var maxValueObj: AnyObject?
        guard AXUIElementCopyAttributeValue(slider, kAXMinValueAttribute as CFString, &minValueObj) == .success,
              AXUIElementCopyAttributeValue(slider, kAXMaxValueAttribute as CFString, &maxValueObj) == .success,
              let minValue = (minValueObj as? NSNumber)?.doubleValue,
              let maxValue = (maxValueObj as? NSNumber)?.doubleValue else {
            print("Could not read slider min/max values")
            return
        }
        
        // Calculate 25% of the total range for visible movement
        let totalRange = maxValue - minValue
        let percentageIncrement = totalRange * 0.25
        
        let newValue: Double
        if currentValue < (minValue + maxValue) / 2.0 {
            // We're in the lower half, go up by 25%
            newValue = min(maxValue, currentValue + percentageIncrement)
            print("Channel \(channelIndex + 1) (\(channelName)): \(currentValue) -> \(newValue) (+\(percentageIncrement))")
        } else {
            // We're in the upper half, go down by 25%
            newValue = max(minValue, currentValue - percentageIncrement)
            print("Channel \(channelIndex + 1) (\(channelName)): \(currentValue) -> \(newValue) (-\(percentageIncrement))")
        }
        
        // Use AXIncrement/AXDecrement actions for smooth movement
        var actions: CFArray?
        guard AXUIElementCopyActionNames(slider, &actions) == .success,
              let actionList = actions as? [String],
              (actionList.contains("AXIncrement") || actionList.contains("AXDecrement")) else {
            print("AXIncrement/AXDecrement actions not available")
            return
        }
        
        let targetChange = newValue - currentValue
        let action = targetChange > 0 ? "AXIncrement" : "AXDecrement"
        
        // Each action appears to move ~10 points based on our testing
        let actionCount = Int(abs(targetChange) / 10.0)
        
        for i in 0..<actionCount {
            AXUIElementPerformAction(slider, action as CFString)
            Thread.sleep(forTimeInterval: 0.01) // Small delay for smooth animation
        }
        
        // Final verification
        Thread.sleep(forTimeInterval: 0.1)
        var finalValueObj: AnyObject?
        if AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &finalValueObj) == .success {
            if let finalValue = (finalValueObj as? NSNumber)?.doubleValue {
                let actualChange = abs(finalValue - currentValue)
                print("Channel \(channelIndex + 1) (\(channelName)): Final value \(finalValue) (moved \(actualChange) points)")
            }
        }
    }
    
    private func logicValueToDecibels(_ value: Double) -> Double {
        // Logic Pro's fader scale approximation:
        // 0.0 = -∞ dB
        // 0.75 = 0 dB
        // 1.0 = +6 dB
        
        if value <= 0 {
            return -96.0  // Effectively -∞
        } else if value <= 0.75 {
            // From -∞ to 0 dB (value 0.0 to 0.75)
            // Using a logarithmic scale
            return 96.0 * (value / 0.75 - 1.0)
        } else {
            // From 0 dB to +6 dB (value 0.75 to 1.0)
            // Linear scale: 6 dB over 0.25 range
            return 24.0 * (value - 0.75)
        }
    }
    
    private func decibelsToLogicValue(_ db: Double) -> Double {
        if db <= -96.0 {
            return 0.0
        } else if db <= 0.0 {
            // From -96 dB to 0 dB maps to value 0.0 to 0.75
            return 0.75 * (1.0 + db / 96.0)
        } else if db <= 6.0 {
            // From 0 dB to +6 dB maps to value 0.75 to 1.0
            return 0.75 + db / 24.0
        } else {
            // Cap at maximum
            return 1.0
        }
    }
    
    private func exploreFullHierarchy(_ element: AXUIElement) {
        var allGroups: [(element: AXUIElement, path: String)] = []
        exploreAndCollectGroups(element, level: 0, path: "Window", collector: &allGroups)
        
        print("\nFound \(allGroups.count) groups in the hierarchy:")
        for (groupElement, path) in allGroups {
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(groupElement, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? "untitled"
            print("  \(path) -> Title: '\(title)'")
        }
        
        print("\nSearching for Mixer or channel strips...")
    }
    
    private func exploreAndCollectGroups(_ element: AXUIElement, level: Int, path: String, collector: inout [(element: AXUIElement, path: String)]) {
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? "unknown"
        
        if role == kAXGroupRole as String {
            collector.append((element: element, path: path))
        }
        
        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for (index, child) in children.enumerated() {
                let childPath = "\(path)/Child[\(index)]"
                exploreAndCollectGroups(child, level: level + 1, path: childPath, collector: &collector)
            }
        }
    }
}

#Preview {
    ContentView()
}
