// ChattyChannels/ChattyChannels/Services/AccessibilityTrackDiscoveryService.swift
import Foundation
import ApplicationServices
import AppKit
import OSLog

/// Service that discovers Logic Pro tracks using macOS Accessibility APIs.
/// This provides a robust alternative to AppleScript-based track discovery,
/// which has become unreliable in Logic Pro 11.2+.
public class AccessibilityTrackDiscoveryService {
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "AccessibilityTrackDiscoveryService")
    
    /// Represents a discovered Logic Pro track.
    public struct DiscoveredTrack {
        public let trackNumber: Int
        public let trackName: String
        public let simpleID: String // TR1, TR2, etc.
        public let channelStripElement: AXUIElement
    }
    
    public init() {}
    
    /// Discovers all tracks in Logic Pro using accessibility APIs.
    /// Returns dictionary mapping track names to simple IDs (TR1, TR2, etc.)
    public func discoverTracks() throws -> [String: String] {
        logger.info("Starting accessibility-based track discovery")
        
        // Check if we have accessibility permissions
        guard checkAccessibilityPermissions() else {
            let error = "Accessibility permissions not granted"
            logger.error("\(error)")
            throw AccessibilityError.permissionsNotGranted
        }
        
        // Find Logic Pro application
        guard let logicApp = findLogicProApplication() else {
            let error = "Logic Pro application not found or not running"
            logger.error("\(error)")
            throw AccessibilityError.applicationNotFound
        }
        logger.info("Found Logic Pro application")
        
        // Get the main window
        guard let mainWindow = getMainWindow(from: logicApp) else {
            let error = "Could not find Logic Pro main window"
            logger.error("\(error)")
            throw AccessibilityError.windowNotFound
        }
        logger.info("Found Logic Pro main window")
        
        // Find the mixer area
        guard let mixer = findMixer(in: mainWindow) else {
            let error = "Could not find mixer area in Logic Pro window"
            logger.error("\(error)")
            throw AccessibilityError.mixerNotFound
        }
        logger.info("Found mixer area")
        
        // Discover channel strips
        let discoveredTracks = discoverChannelStrips(in: mixer)
        logger.info("Discovered \(discoveredTracks.count) channel strips")
        
        // Convert to the expected format: [trackName: simpleID]
        var trackMapping: [String: String] = [:]
        for track in discoveredTracks {
            trackMapping[track.trackName] = track.simpleID
            logger.info("Mapped track: '\(track.trackName)' -> '\(track.simpleID)'")
        }
        
        logger.info("Track discovery completed successfully with \(trackMapping.count) tracks")
        return trackMapping
    }
    
    // MARK: - Private Methods
    
    /// Verifies accessibility permissions and prompts user if needed.
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            logger.warning("Accessibility permissions not granted. User will be prompted.")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        logger.info("Accessibility permissions check: \(trusted ? "granted" : "not granted")")
        return trusted
    }
    
    /// Finds the Logic Pro application by bundle identifier.
    private func findLogicProApplication() -> AXUIElement? {
        logger.debug("Searching for Logic Pro application")
        
        // Check if Logic Pro is running
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10")
        guard let logicApp = runningApps.first else {
            logger.error("Logic Pro (com.apple.logic10) is not running")
            return nil
        }
        
        logger.info("Found Logic Pro running with PID: \(logicApp.processIdentifier)")
        
        // Create accessibility element for the application
        let appElement = AXUIElementCreateApplication(logicApp.processIdentifier)
        return appElement
    }
    
    /// Gets the main window from Logic Pro application.
    private func getMainWindow(from app: AXUIElement) -> AXUIElement? {
        logger.debug("Getting main window from Logic Pro application")
        
        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
        
        guard result == .success,
              let windows = windowsValue as? [AXUIElement],
              !windows.isEmpty else {
            logger.error("Failed to get windows from Logic Pro application")
            return nil
        }
        
        logger.info("Found \(windows.count) windows in Logic Pro")
        
        // Use the first window (main window)
        let mainWindow = windows[0]
        
        // Log window details for debugging
        if let windowTitle = getElementAttribute(mainWindow, kAXTitleAttribute as CFString) as? String {
            logger.info("Using main window with title: '\(windowTitle)'")
        } else {
            logger.info("Using main window (no title available)")
        }
        
        return mainWindow
    }
    
    /// Finds the mixer area (AXLayoutArea with channel strips) in the main window.
    private func findMixer(in window: AXUIElement) -> AXUIElement? {
        logger.debug("Searching for mixer area in Logic Pro window")
        
        // First look for layout areas and identify the mixer by its content
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
                logger.info("Found mixer area with \(hasChannelStrips) channel strips")
                return true
            }
            
            return false
        }) {
            return mixerArea
        }
        
        logger.error("No suitable mixer area found")
        return nil
    }
    
    /// Validates that an element contains both a slider and a mute button (indicating it's a channel strip).
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
    
    /// Enumerates channel strips (AXLayoutItem elements) and extracts track information.
    private func discoverChannelStrips(in mixer: AXUIElement) -> [DiscoveredTrack] {
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(mixer, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            logger.error("Failed to get children of mixer area")
            return []
        }
        
        var discoveredTracks: [DiscoveredTrack] = []
        var trackNumber = 1
        
        for (_, child) in children.enumerated() {
            var roleValue: AnyObject?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String,
                  role == "AXLayoutItem" else { continue }
            
            // Get the description to extract track name
            if let description = getElementAttribute(child, kAXDescriptionAttribute as CFString) as? String {
                // Check if this is a valid track (exclude known non-track elements)
                if isValidTrackName(description) {
                    let trackName = extractTrackName(from: description)
                    let simpleID = "TR\(trackNumber)"
                    
                    let track = DiscoveredTrack(
                        trackNumber: trackNumber,
                        trackName: trackName,
                        simpleID: simpleID,
                        channelStripElement: child
                    )
                    
                    discoveredTracks.append(track)
                    logger.info("Discovered track \(trackNumber): '\(trackName)' (simpleID: \(simpleID))")
                    trackNumber += 1
                }
            }
        }
        
        return discoveredTracks
    }
    
    /// Determines if a description represents a valid audio track
    ///
    /// Uses exclusion logic rather than inclusion to be more permissive of actual track names
    ///
    /// - Parameter description: The description from the channel strip
    /// - Returns: true if this appears to be a valid audio track
    private func isValidTrackName(_ description: String) -> Bool {
        let lowercased = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Exclude known non-track elements
        let nonTrackElements = [
            "stereo out",
            "master",
            "main out", 
            "monitor",
            "headphone",
            "cue",
            "return",
            "bus send",
            "aux send",
            "output",
            "input"
        ]
        
        // Check if description matches any non-track elements
        for nonTrack in nonTrackElements {
            if lowercased.contains(nonTrack) {
                return false
            }
        }
        
        // If it's not empty and not a known non-track element, consider it a track
        return !lowercased.isEmpty
    }
    
    /// Extracts track name from accessibility description (e.g., "Track 1 \"kick\"" -> "kick").
    private func extractTrackName(from description: String) -> String {
        // Find the content between quotes (handle both regular and smart quotes)
        let quoteCharacters = CharacterSet(charactersIn: "\"\u{201C}\u{201D}")
        
        // Find first quote
        if let firstQuoteRange = description.rangeOfCharacter(from: quoteCharacters),
           let remainingString = description[firstQuoteRange.upperBound...].rangeOfCharacter(from: quoteCharacters) {
            let extractedName = String(description[firstQuoteRange.upperBound..<remainingString.lowerBound])
            return extractedName
        }
        
        // Fallback: try to extract from patterns like "Track 1" or "Audio 1"
        let patterns = ["Track ", "Audio ", "Channel "]
        for pattern in patterns {
            if let range = description.range(of: pattern) {
                let afterPattern = String(description[range.upperBound...])
                if let spaceIndex = afterPattern.firstIndex(of: " ") {
                    let trackNumber = String(afterPattern[..<spaceIndex])
                    let fallbackName = "\(pattern.trimmingCharacters(in: .whitespaces)) \(trackNumber)"
                    return fallbackName
                }
            }
        }
        
        // Final fallback: use the full description, cleaned up
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Mutes a specific track by name using accessibility APIs
    /// This is the core functionality needed for oscillator-based calibration
    public func muteTrack(byName trackName: String) throws {
        logger.info("Attempting to mute track: '\(trackName)'")
        
        let discoveredTracks = try getDiscoveredTracks()
        
        // Find the track with matching name
        guard let track = discoveredTracks.first(where: { $0.trackName == trackName }) else {
            let error = "Track '\(trackName)' not found in discovered tracks"
            logger.error("\(error)")
            throw AccessibilityError.trackNotFound(trackName)
        }
        
        logger.debug("Found track '\(trackName)' at position \(track.trackNumber)")
        
        // Find and toggle the mute button
        guard let muteButton = findMuteButton(in: track.channelStripElement) else {
            let error = "Could not find mute button for track '\(trackName)'"
            logger.error("\(error)")
            throw AccessibilityError.muteButtonNotFound(trackName)
        }
        
        // Check current mute state
        let currentlyMuted = getMuteState(button: muteButton)
        logger.debug("Track '\(trackName)' current mute state: \(currentlyMuted ? "muted" : "unmuted")")
        
        // If not already muted, mute it
        if !currentlyMuted {
            let result = AXUIElementPerformAction(muteButton, kAXPressAction as CFString)
            if result == .success {
                // Wait for UI to update
                Thread.sleep(forTimeInterval: 0.1)
                
                // Verify mute state changed
                let newState = getMuteState(button: muteButton)
                if newState {
                    logger.info("Successfully muted track '\(trackName)'")
                } else {
                    logger.warning("Track '\(trackName)' may not have muted correctly")
                }
            } else {
                let error = "Failed to press mute button for track '\(trackName)'"
                logger.error("\(error)")
                throw AccessibilityError.muteActionFailed(trackName)
            }
        } else {
            logger.info("Track '\(trackName)' was already muted")
        }
    }
    
    /// Unmutes a specific track by name using accessibility APIs
    public func unmuteTrack(byName trackName: String) throws {
        logger.info("Attempting to unmute track: '\(trackName)'")
        
        let discoveredTracks = try getDiscoveredTracks()
        
        // Find the track with matching name
        guard let track = discoveredTracks.first(where: { $0.trackName == trackName }) else {
            let error = "Track '\(trackName)' not found in discovered tracks"
            logger.error("\(error)")
            throw AccessibilityError.trackNotFound(trackName)
        }
        
        logger.debug("Found track '\(trackName)' at position \(track.trackNumber)")
        
        // Find and toggle the mute button
        guard let muteButton = findMuteButton(in: track.channelStripElement) else {
            let error = "Could not find mute button for track '\(trackName)'"
            logger.error("\(error)")
            throw AccessibilityError.muteButtonNotFound(trackName)
        }
        
        // Check current mute state
        let currentlyMuted = getMuteState(button: muteButton)
        logger.debug("Track '\(trackName)' current mute state: \(currentlyMuted ? "muted" : "unmuted")")
        
        // If currently muted, unmute it
        if currentlyMuted {
            let result = AXUIElementPerformAction(muteButton, kAXPressAction as CFString)
            if result == .success {
                // Wait for UI to update
                Thread.sleep(forTimeInterval: 0.1)
                
                // Verify mute state changed
                let newState = getMuteState(button: muteButton)
                if !newState {
                    logger.info("Successfully unmuted track '\(trackName)'")
                } else {
                    logger.warning("Track '\(trackName)' may not have unmuted correctly")
                }
            } else {
                let error = "Failed to press mute button for track '\(trackName)'"
                logger.error("\(error)")
                throw AccessibilityError.muteActionFailed(trackName)
            }
        } else {
            logger.info("Track '\(trackName)' was already unmuted")
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Gets all discovered tracks (cached discovery to avoid repeated accessibility calls)
    private func getDiscoveredTracks() throws -> [DiscoveredTrack] {
        // For now, perform fresh discovery each time
        // TODO: Consider caching if performance becomes an issue
        
        // Check if we have accessibility permissions
        guard checkAccessibilityPermissions() else {
            throw AccessibilityError.permissionsNotGranted
        }
        
        // Find Logic Pro application
        guard let logicApp = findLogicProApplication() else {
            throw AccessibilityError.applicationNotFound
        }
        
        // Get the main window
        guard let mainWindow = getMainWindow(from: logicApp) else {
            throw AccessibilityError.windowNotFound
        }
        
        // Find the mixer area
        guard let mixer = findMixer(in: mainWindow) else {
            throw AccessibilityError.mixerNotFound
        }
        
        // Discover channel strips
        return discoverChannelStrips(in: mixer)
    }
    
    /// Finds the mute button within a channel strip
    private func findMuteButton(in channelStrip: AXUIElement) -> AXUIElement? {
        logger.debug("Searching for mute button in channel strip")
        
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
            
            let isMuteButton = title.contains("mute") || desc.contains("mute") || title == "m"
            if isMuteButton {
                logger.debug("Found mute button with title: '\(title)', description: '\(desc)'")
            }
            
            return isMuteButton
        }
    }
    
    /// Gets the current mute state of a mute button
    private func getMuteState(button: AXUIElement) -> Bool {
        var valueObj: AnyObject?
        let result = AXUIElementCopyAttributeValue(button, kAXValueAttribute as CFString, &valueObj)
        
        if result != .success {
            // No value attribute, check if button is selected/pressed
            var selectedObj: AnyObject?
            if AXUIElementCopyAttributeValue(button, kAXSelectedAttribute as CFString, &selectedObj) == .success {
                if let selected = selectedObj as? Bool {
                    logger.debug("Mute button selected state: \(selected)")
                    return selected
                }
            }
            
            logger.debug("Could not read mute button state, assuming unmuted")
            return false
        }
        
        // Handle different value types that Logic Pro might return
        if let value = valueObj as? Int {
            logger.debug("Mute button value (Int): \(value)")
            return value != 0
        } else if let value = valueObj as? Bool {
            logger.debug("Mute button value (Bool): \(value)")
            return value
        } else if let value = valueObj as? NSNumber {
            logger.debug("Mute button value (NSNumber): \(value)")
            return value.boolValue
        } else if let value = valueObj as? String {
            logger.debug("Mute button value (String): '\(value)'")
            // Logic Pro might return "1" or "0" as strings
            return value == "1" || value.lowercased() == "true" || value.lowercased() == "on"
        } else {
            // Try to get more info about the value
            logger.debug("Unknown mute button value type: \(type(of: valueObj)), value: \(String(describing: valueObj))")
            
            // Last resort: check if the button has any indication it's "on"
            var titleObj: AnyObject?
            if AXUIElementCopyAttributeValue(button, kAXTitleAttribute as CFString, &titleObj) == .success,
               let title = titleObj as? String {
                logger.debug("Checking button title for state: '\(title)'")
                // Some apps change the title when muted
                return title.lowercased().contains("unmute") || title.lowercased().contains("on")
            }
            
            return false
        }
    }

    // MARK: - Utility Methods
    
    /// Recursively searches accessibility element tree for matching elements.
    private func findElementRecursive(in element: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        // Check current element
        if predicate(element) {
            return element
        }
        
        // Check children recursively
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        
        for child in children {
            if let found = findElementRecursive(in: child, matching: predicate) {
                return found
            }
        }
        
        return nil
    }
    
    /// Safe wrapper for AXUIElementCopyAttributeValue that returns nil on failure.
    private func getElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }
    
    /// Debug method to explore the accessibility hierarchy
    private func debugExploreHierarchy(_ element: AXUIElement, prefix: String, maxDepth: Int = 3, currentDepth: Int = 0) {
        guard currentDepth < maxDepth else { return }
        
        var roleValue: AnyObject?
        var titleValue: AnyObject?
        var descValue: AnyObject?
        var childrenValue: AnyObject?
        
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        
        let role = roleValue as? String ?? "unknown"
        let title = titleValue as? String ?? ""
        let desc = descValue as? String ?? ""
        let childCount = (childrenValue as? [AXUIElement])?.count ?? 0
        
        let indent = String(repeating: "  ", count: currentDepth)
        logger.debug("\(indent)\(prefix): Role=\(role), Title='\(title)', Desc='\(desc)', Children=\(childCount)")
        
        // If this is a layout area, log more details
        if role == kAXLayoutAreaRole as String {
            logger.info("\(indent)FOUND LAYOUT AREA at \(prefix) with \(childCount) children")
            
            // Check if children have sliders and mute buttons
            if let children = childrenValue as? [AXUIElement] {
                var sliderCount = 0
                var muteButtonCount = 0
                
                for (index, child) in children.enumerated() {
                    if hasSliderAndMuteButton(child) {
                        logger.info("\(indent)  Child \(index) has slider and mute button")
                        sliderCount += 1
                        muteButtonCount += 1
                    }
                }
                
                logger.info("\(indent)  Total channel strips with slider+mute: \(sliderCount)")
            }
        }
        
        // Explore children
        if let children = childrenValue as? [AXUIElement], currentDepth < maxDepth - 1 {
            for (index, child) in children.enumerated() {
                if index < 10 { // Limit to first 10 children
                    debugExploreHierarchy(child, prefix: "\(prefix)/Child[\(index)]", maxDepth: maxDepth, currentDepth: currentDepth + 1)
                }
            }
        }
    }
}

// MARK: - Error Types

/// Errors that can occur during accessibility-based track discovery.
public enum AccessibilityError: LocalizedError {
    case permissionsNotGranted
    case applicationNotFound
    case windowNotFound
    case mixerNotFound
    case trackNotFound(String)
    case muteButtonNotFound(String)
    case muteActionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .permissionsNotGranted:
            return "Accessibility permissions not granted. Please enable accessibility access for Chatty Channels in System Preferences."
        case .applicationNotFound:
            return "Logic Pro application not found or not running."
        case .windowNotFound:
            return "Could not find Logic Pro main window."
        case .mixerNotFound:
            return "Could not find mixer area in Logic Pro window. Make sure the mixer is visible."
        case .trackNotFound(let trackName):
            return "Track '\(trackName)' not found in Logic Pro mixer."
        case .muteButtonNotFound(let trackName):
            return "Could not find mute button for track '\(trackName)'. Make sure the mixer is visible and the track has a mute control."
        case .muteActionFailed(let trackName):
            return "Failed to perform mute action on track '\(trackName)'. The accessibility action may have been rejected."
        }
    }
}