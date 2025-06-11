// ChattyChannels/ChattyChannels/AppleScriptService.swift
//
// Provides a thin, test-friendly wrapper around `osascript` so that
// ChattyChannels can read & write Logic Pro track volumes from Swift.
//
// The service is intentionally “dumb”: it composes plain AppleScript strings
// and executes them via an injectable `ProcessRunner` so unit-tests can supply
// a mock runner without spawning a real shell.
//
// In v0.5 we only support one track (“Kick”), but the API is generic.
// Playback-safe retry logic (T-02) will be layered on top of this file.

import Foundation
import ApplicationServices
import AppKit
import OSLog
import Combine // Added for ObservableObject

// MARK: - Error definitions

/// Errors thrown by `AppleScriptService`.
public enum AppleScriptError: LocalizedError {
    case executionFailed(String)    // The `osascript` process returned non-zero
    case parsingFailed(String)      // Could not coerce stdout -> Float
    
    public var errorDescription: String? {
        switch self {
        case .executionFailed(let msg): return "AppleScript execution failed: \(msg)"
        case .parsingFailed(let msg):   return "AppleScript output parse error: \(msg)"
        }
    }
}

// MARK: - ProcessRunner protocol (dependency-injection point)

/// Abstraction over `Process` so we can unit-test AppleScript calls deterministically.
public protocol ProcessRunner {
    /// Launches a process synchronously and returns captured stdout/stderr.
    /// Throws if the underlying process exits with non-zero or if launch fails.
    func run(_ launchPath: String, arguments: [String]) throws -> String
}

/// Default implementation that shells out to `/usr/bin/osascript`.
public struct DefaultProcessRunner: ProcessRunner {
    public init() {}
    
    public func run(_ launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments      = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        
        guard process.terminationStatus == 0 else {
            throw AppleScriptError.executionFailed(output)
        }
        return output
    }
}

// MARK: - AppleScriptService

/// Defines the interface for a service that controls Logic Pro through AppleScript.
///
/// This protocol allows for dependency injection and testing by abstracting the
/// actual AppleScript execution from the client code.
public protocol AppleScriptServiceProtocol {
    /// Returns the current fader gain (dB) of the given track.
    /// - Parameter trackName: Exact track name as shown in Logic's mixer.
    /// - Throws: An error if the command fails or output can't be parsed.
    /// - Returns: The current gain in decibels.
    func getVolume(trackName: String) throws -> Float
    
    /// Sets the fader gain (dB) of the given track.
    /// - Parameters:
    ///   - trackName: Target track.
    ///   - db: New gain in decibels.
    /// - Throws: An error if the command fails.
    func setVolume(trackName: String, db: Float) throws

    /// Actively probes a track by inserting a test tone and managing playback.
    /// - Parameters:
    ///   - logicTrackUUID: The UUID of the track to probe.
    ///   - frequency: The frequency of the test tone in Hz.
    ///   - probeLevel: The level of the test tone in dBFS.
    ///   - duration: The duration of the probe in seconds.
    /// - Throws: An error if any AppleScript command fails or parsing fails.
    func probeTrack(logicTrackUUID: String, frequency: Double, probeLevel: Float, duration: Double) async throws
    
    /// Test input gain movement on channel 1 and monitor RMS changes from all plugins.
    /// This is a validation test to confirm input gain changes affect plugin RMS readings.
    /// Input gain is pre-plugin, unlike volume faders which are post-plugin.
    /// - Parameter oscService: The OSC service to use for RMS polling
    /// - Throws: An error if accessibility or input gain control fails
    func testInputGainMovementChannel1(oscService: OSCService) async throws
}

/// Thin wrapper for mixing-console AppleScript commands.
public final class AppleScriptService: AppleScriptServiceProtocol, ObservableObject { // Added ObservableObject
    
    // Dependency-injected runner
    private let runner: ProcessRunner
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels",
                                category: "AppleScriptService")
    
    public init(runner: ProcessRunner = PlaybackSafeProcessRunner()) {
        self.runner = runner
    }
    
    // MARK: Public API
    
    /// Returns the current fader gain (dB) of the given track.
    /// - Parameter trackName: Exact track name as shown in Logic’s mixer.
    /// - Throws: `AppleScriptError` if the command fails or output can’t be parsed.
    public func getVolume(trackName: String) throws -> Float {
        logger.info("Attempting to get volume for track: \(trackName, privacy: .public)")
        let script = """
        tell application "Logic Pro"
            set _val to output volume of track named "\(trackName)"
        end tell
        return _val
        """
        do {
            let output = try runAppleScript(script)
            guard let value = Float(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                logger.error("Failed to parse volume for track '\(trackName, privacy: .public)'. Output (hash): \(output.hashValue, privacy: .public)")
                throw AppleScriptError.parsingFailed(output)
            }
            logger.info("Successfully got volume for track '\(trackName, privacy: .public)': \(value, privacy: .public) dB")
            return value
        } catch {
            logger.error("Failed to get volume for track '\(trackName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error // Re-throw the original error
        }
    }
    
    /// Sets the fader gain (dB) of the given track.
    /// - Parameters:
    ///   - trackName: Target track.
    ///   - db: New gain in decibels.
    public func setVolume(trackName: String, db: Float) throws {
        logger.info("Attempting to set volume for track: \(trackName, privacy: .public) to \(db, privacy: .public) dB")
        let script = """
        tell application "Logic Pro"
            set output volume of track named "\(trackName)" to \(db)
        end tell
        """
        do {
            _ = try runAppleScript(script) // ignore stdout
            logger.info("Successfully set volume for track '\(trackName, privacy: .public)' to \(db, privacy: .public) dB")
        } catch {
            logger.error("Failed to set volume for track '\(trackName, privacy: .public)' to \(db, privacy: .public) dB: \(error.localizedDescription, privacy: .public)")
            throw error // Re-throw the original error
        }
    }

    /// Test input gain movement on channel 1 and monitor RMS changes from all plugins.
    /// This is a validation test to confirm input gain changes affect plugin RMS readings.
    /// Input gain is pre-plugin, unlike volume faders which are post-plugin.
    public func testInputGainMovementChannel1(oscService: OSCService) async throws {
        logger.info("Starting input gain movement test on channel 1...")
        
        guard checkAccessibilityPermissions() else {
            throw AppleScriptError.executionFailed("Accessibility permissions not granted")
        }
        
        guard let logicApp = findLogicProApplication() else {
            throw AppleScriptError.executionFailed("Logic Pro not found or not running")
        }
        
        guard let mainWindow = getMainWindow(from: logicApp) else {
            throw AppleScriptError.executionFailed("Could not find Logic Pro main window")
        }
        
        guard let mixer = findMixer(in: mainWindow) else {
            throw AppleScriptError.executionFailed("Could not find mixer area")
        }
        
        let channelStrips = getChannelStrips(from: mixer)
        guard channelStrips.count > 0 else {
            throw AppleScriptError.executionFailed("No channel strips found")
        }
        
        // Get channel 1 (index 0)
        let channel1Strip = channelStrips[0]
        guard let inputGainSlider = findInputGainSlider(in: channel1Strip) else {
            throw AppleScriptError.executionFailed("Could not find input gain slider for channel 1")
        }
        
        // Get baseline RMS readings from all plugins
        logger.info("=== BASELINE RMS READINGS ===")
        await pollAllPluginRMS(oscService: oscService, label: "BASELINE")
        
        // Move input gain UP
        logger.info("Moving channel 1 input gain UP...")
        try moveInputGainUp(slider: inputGainSlider, channelName: "channel1")
        
        // Wait 2 seconds, then poll RMS
        try await Task.sleep(nanoseconds: 2_000_000_000)
        logger.info("=== RMS AFTER INPUT GAIN UP ===")
        await pollAllPluginRMS(oscService: oscService, label: "INPUT GAIN UP")
        
        // Move input gain DOWN  
        logger.info("Moving channel 1 input gain DOWN...")
        try moveInputGainDown(slider: inputGainSlider, channelName: "channel1")
        
        // Wait 2 seconds, then poll RMS
        try await Task.sleep(nanoseconds: 2_000_000_000)
        logger.info("=== RMS AFTER INPUT GAIN DOWN ===")
        await pollAllPluginRMS(oscService: oscService, label: "INPUT GAIN DOWN")
        
        logger.info("Input gain movement test completed.")
    }
    
    /// Poll RMS from all plugins at low frequency (< 10Hz)
    private func pollAllPluginRMS(oscService: OSCService, label: String) async {
        let queryID = UUID().uuidString
        oscService.broadcastRMSQuery(queryID: queryID)
        
        // Wait 500ms for responses (< 10Hz polling)
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        let rmsData = oscService.getCurrentQueryResponses()
        logger.info("RMS Poll (\(label)): Found \(rmsData.count) plugin responses")
        
        for (tempID, rmsValue) in rmsData {
            let rmsDb = rmsValue > 0 ? 20 * log10(rmsValue) : -120.0
            logger.info("  Plugin \(tempID.prefix(8))...: \(String(format: "%.1f", rmsDb)) dBFS (linear: \(String(format: "%.6f", rmsValue)))")
        }
        
        // Clear the query for next poll
        oscService.clearCurrentQuery()
    }
    
    /// Move volume fader up using AXIncrement actions
    private func moveFaderUp(slider: AXUIElement, channelName: String) throws {
        // Get current value
        var valueObj: AnyObject?
        guard AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
              let currentValue = (valueObj as? NSNumber)?.doubleValue else {
            throw AppleScriptError.executionFailed("Could not read current fader value")
        }
        
        logger.info("Channel 1 current fader value: \(currentValue)")
        
        // Move up by ~60 points (6 increments of ~10 points each)
        // This should create a significant, detectable change
        for i in 0..<6 {
            let result = AXUIElementPerformAction(slider, "AXIncrement" as CFString)
            if result != .success {
                logger.warning("AXIncrement action \(i+1) failed")
            }
            Thread.sleep(forTimeInterval: 0.05) // 50ms between increments
        }
        
        // Verify new value
        if AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
           let newValue = (valueObj as? NSNumber)?.doubleValue {
            let change = newValue - currentValue
            logger.info("Channel 1 fader moved: \(currentValue) -> \(newValue) (change: +\(change))")
        }
    }
    
    /// Move volume fader down using AXDecrement actions
    private func moveFaderDown(slider: AXUIElement, channelName: String) throws {
        // Get current value
        var valueObj: AnyObject?
        guard AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
              let currentValue = (valueObj as? NSNumber)?.doubleValue else {
            throw AppleScriptError.executionFailed("Could not read current fader value")
        }
        
        logger.info("Channel 1 current fader value: \(currentValue)")
        
        // Move down by ~60 points (6 decrements of ~10 points each)
        for i in 0..<6 {
            let result = AXUIElementPerformAction(slider, "AXDecrement" as CFString)
            if result != .success {
                logger.warning("AXDecrement action \(i+1) failed")
            }
            Thread.sleep(forTimeInterval: 0.05) // 50ms between decrements
        }
        
        // Verify new value
        if AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
           let newValue = (valueObj as? NSNumber)?.doubleValue {
            let change = newValue - currentValue
            logger.info("Channel 1 fader moved: \(currentValue) -> \(newValue) (change: \(change))")
        }
    }
    
    /// Find volume slider in a channel strip using the patterns from accessibility.md
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
    
    /// Find input gain slider in a channel strip using the patterns from accessibility.md
    private func findInputGainSlider(in channelStrip: AXUIElement) -> AXUIElement? {
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
        
        // Look for input gain specifically (range should be -8 to 10 according to accessibility.md)
        for (slider, title, desc) in allSliders {
            if title.lowercased().contains("input") || title.lowercased().contains("gain") ||
               desc.lowercased().contains("input gain") {
                return slider
            }
        }
        
        // Fallback: find slider with the expected input gain range (-8 to 10)
        for (slider, _, desc) in allSliders {
            var minValueObj: AnyObject?, maxValueObj: AnyObject?
            if AXUIElementCopyAttributeValue(slider, kAXMinValueAttribute as CFString, &minValueObj) == .success,
               AXUIElementCopyAttributeValue(slider, kAXMaxValueAttribute as CFString, &maxValueObj) == .success,
               let minValue = (minValueObj as? NSNumber)?.doubleValue,
               let maxValue = (maxValueObj as? NSNumber)?.doubleValue {
                // Input gain typically has range -8 to +10 (18 units total)
                let range = maxValue - minValue
                if abs(minValue - (-8)) < 2 && abs(maxValue - 10) < 2 && range > 15 && range < 25 {
                    logger.debug("Found input gain slider by range: min=\(minValue), max=\(maxValue), desc='\(desc)'")
                    return slider
                }
            }
        }
        
        logger.warning("Could not find input gain slider. Available sliders:")
        for (_, title, desc) in allSliders {
            logger.warning("  Slider - title: '\(title)', desc: '\(desc)'")
        }
        return nil
    }
    
    /// Move input gain up using AXIncrement actions
    private func moveInputGainUp(slider: AXUIElement, channelName: String) throws {
        // Get current value
        var valueObj: AnyObject?
        guard AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
              let currentValue = (valueObj as? NSNumber)?.doubleValue else {
            throw AppleScriptError.executionFailed("Could not read current input gain value")
        }
        
        logger.info("Channel 1 current input gain value: \(currentValue)")
        
        // Move up by significant amount (input gain range is only -8 to +10)
        // Let's move up by ~6 units (should be very detectable)
        for i in 0..<6 {
            let result = AXUIElementPerformAction(slider, "AXIncrement" as CFString)
            if result != .success {
                logger.warning("AXIncrement action \(i+1) failed on input gain")
            }
            Thread.sleep(forTimeInterval: 0.1) // 100ms between increments for input gain
        }
        
        // Verify new value
        if AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
           let newValue = (valueObj as? NSNumber)?.doubleValue {
            let change = newValue - currentValue
            logger.info("Channel 1 input gain moved: \(currentValue) -> \(newValue) (change: +\(change))")
        }
    }
    
    /// Move input gain down using AXDecrement actions
    private func moveInputGainDown(slider: AXUIElement, channelName: String) throws {
        // Get current value
        var valueObj: AnyObject?
        guard AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
              let currentValue = (valueObj as? NSNumber)?.doubleValue else {
            throw AppleScriptError.executionFailed("Could not read current input gain value")
        }
        
        logger.info("Channel 1 current input gain value: \(currentValue)")
        
        // Move down by significant amount
        for i in 0..<6 {
            let result = AXUIElementPerformAction(slider, "AXDecrement" as CFString)
            if result != .success {
                logger.warning("AXDecrement action \(i+1) failed on input gain")
            }
            Thread.sleep(forTimeInterval: 0.1) // 100ms between decrements for input gain
        }
        
        // Verify new value
        if AXUIElementCopyAttributeValue(slider, kAXValueAttribute as CFString, &valueObj) == .success,
           let newValue = (valueObj as? NSNumber)?.doubleValue {
            let change = newValue - currentValue
            logger.info("Channel 1 input gain moved: \(currentValue) -> \(newValue) (change: \(change))")
        }
    }

    /// Actively probes a track by using accessibility APIs for mute control.
    public func probeTrack(logicTrackUUID: String, frequency: Double, probeLevel: Float = -12.0, duration: Double) async throws {
        var originalMuteStates: [Int: Bool] = [:]

        logger.info("Starting probe for track UUID: \(logicTrackUUID), Freq: \(frequency) Hz, Level: \(probeLevel) dB, Duration: \(duration)s")
        
        // Extract track number from simple ID like "TR1" -> 1
        let trackNumber: Int
        if logicTrackUUID.hasPrefix("TR") {
            trackNumber = Int(logicTrackUUID.dropFirst(2)) ?? 1
        } else {
            trackNumber = Int(logicTrackUUID) ?? 1
        }

        // --- 1. Mute all tracks except target using accessibility APIs ---
        do {
            originalMuteStates = try muteAllExceptTrack(trackNumber)
            logger.info("ProbeTrack: Successfully configured mute states via accessibility APIs")
        } catch {
            logger.warning("ProbeTrack: Failed to configure mute states via accessibility APIs: \(error.localizedDescription)")
            // Continue without muting - this is not critical for basic calibration
        }

        // --- 2. Wait for the probe duration ---
        logger.debug("ProbeTrack: Waiting for duration: \(duration)s")
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        // --- 3. Restore original mute states using accessibility APIs ---
        if !originalMuteStates.isEmpty {
            do {
                try restoreMuteStates(originalMuteStates)
                logger.info("ProbeTrack: Successfully restored mute states via accessibility APIs")
            } catch {
                logger.warning("ProbeTrack: Failed to restore mute states via accessibility APIs: \(error.localizedDescription)")
            }
        }
        
        logger.info("ProbeTrack completed successfully for UUID: \(logicTrackUUID, privacy: .public)")
    }
    
    // MARK: - Accessibility helpers for track mute control
    
    /// Mutes all tracks except the specified track number using accessibility APIs.
    private func muteAllExceptTrack(_ targetTrackNumber: Int) throws -> [Int: Bool] {
        logger.debug("Muting all tracks except track \(targetTrackNumber) using accessibility APIs")
        
        guard checkAccessibilityPermissions() else {
            throw AppleScriptError.executionFailed("Accessibility permissions not granted")
        }
        
        guard let logicApp = findLogicProApplication() else {
            throw AppleScriptError.executionFailed("Logic Pro not found or not running")
        }
        
        guard let mainWindow = getMainWindow(from: logicApp) else {
            throw AppleScriptError.executionFailed("Could not find Logic Pro main window")
        }
        
        guard let mixer = findMixer(in: mainWindow) else {
            throw AppleScriptError.executionFailed("Could not find mixer area")
        }
        
        let channelStrips = getChannelStrips(from: mixer)
        var originalMuteStates: [Int: Bool] = [:]
        
        for (index, channelStrip) in channelStrips.enumerated() {
            let trackNumber = index + 1 // 1-based track numbering
            
            if let muteButton = findMuteButton(in: channelStrip) {
                // Store original mute state
                let currentMuteState = getMuteState(button: muteButton)
                originalMuteStates[trackNumber] = currentMuteState
                
                // Set desired mute state
                let shouldMute = (trackNumber != targetTrackNumber)
                if currentMuteState != shouldMute {
                    toggleMute(button: muteButton)
                    logger.debug("Track \(trackNumber): Mute state changed from \(currentMuteState) to \(shouldMute)")
                }
            } else {
                logger.warning("Could not find mute button for track \(trackNumber)")
            }
        }
        
        return originalMuteStates
    }
    
    /// Restores the original mute states using accessibility APIs.
    private func restoreMuteStates(_ originalStates: [Int: Bool]) throws {
        logger.debug("Restoring mute states for \(originalStates.count) tracks using accessibility APIs")
        
        guard let logicApp = findLogicProApplication() else {
            throw AppleScriptError.executionFailed("Logic Pro not found")
        }
        
        guard let mainWindow = getMainWindow(from: logicApp) else {
            throw AppleScriptError.executionFailed("Could not find Logic Pro main window")
        }
        
        guard let mixer = findMixer(in: mainWindow) else {
            throw AppleScriptError.executionFailed("Could not find mixer area")
        }
        
        let channelStrips = getChannelStrips(from: mixer)
        
        for (index, channelStrip) in channelStrips.enumerated() {
            let trackNumber = index + 1
            
            guard let originalState = originalStates[trackNumber] else { continue }
            
            if let muteButton = findMuteButton(in: channelStrip) {
                let currentState = getMuteState(button: muteButton)
                if currentState != originalState {
                    toggleMute(button: muteButton)
                    logger.debug("Track \(trackNumber): Restored mute state from \(currentState) to \(originalState)")
                }
            }
        }
    }
    
    // MARK: - Accessibility utility methods (based on docs/accessibility.md)
    
    private func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func findLogicProApplication() -> AXUIElement? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10")
        guard let logicApp = runningApps.first else { return nil }
        return AXUIElementCreateApplication(logicApp.processIdentifier)
    }
    
    private func getMainWindow(from app: AXUIElement) -> AXUIElement? {
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement],
              !windows.isEmpty else { return nil }
        return windows[0]
    }
    
    private func findMixer(in window: AXUIElement) -> AXUIElement? {
        return findElementRecursive(in: window) { element in
            var roleValue: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String,
                  role == "AXLayoutArea" else { return false }
            
            var childrenValue: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { return false }
            
            let channelStripCount = children.filter { child in
                var childRoleValue: AnyObject?
                return AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRoleValue) == .success &&
                       (childRoleValue as? String) == "AXLayoutItem"
            }.count
            
            return channelStripCount >= 2
        }
    }
    
    private func getChannelStrips(from mixer: AXUIElement) -> [AXUIElement] {
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(mixer, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return [] }
        
        return children.filter { child in
            var roleValue: AnyObject?
            return AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success &&
                   (roleValue as? String) == "AXLayoutItem"
        }
    }
    
    private func findMuteButton(in channelStrip: AXUIElement) -> AXUIElement? {
        return findElementRecursive(in: channelStrip) { element in
            var roleValue: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String,
                  role == kAXButtonRole as String else { return false }
            
            var titleValue: AnyObject?
            var descValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
            
            let title = (titleValue as? String ?? "").lowercased()
            let desc = (descValue as? String ?? "").lowercased()
            
            return title.contains("mute") || desc.contains("mute") || title == "m"
        }
    }
    
    private func getMuteState(button: AXUIElement) -> Bool {
        var valueObj: AnyObject?
        guard AXUIElementCopyAttributeValue(button, kAXValueAttribute as CFString, &valueObj) == .success else {
            return false
        }
        
        if let value = valueObj as? Int {
            return value != 0
        } else if let value = valueObj as? Bool {
            return value
        } else if let value = valueObj as? NSNumber {
            return value.boolValue
        }
        return false
    }
    
    private func toggleMute(button: AXUIElement) {
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        if result == .success {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    
    private func findElementRecursive(in element: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        if predicate(element) {
            return element
        }
        
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
    
    // MARK: Private helpers
    
    @discardableResult
    private func runAppleScript(_ source: String) throws -> String {
        logger.debug("Running AppleScript (hash): \(source.hashValue, privacy: .public)")
        let out = try runner.run("/usr/bin/osascript", arguments: ["-e", source])
        // Avoid logging potentially large output from script1 unless necessary for deep debugging
        if !source.contains("tempOriginalMutesString") { // Heuristic to avoid logging large mute list
             logger.debug("AppleScript returned: \(out.prefix(200), privacy: .private(mask: .hash))")
        } else {
             logger.debug("AppleScript (getAndPrepare) returned output of length: \(out.count)")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
