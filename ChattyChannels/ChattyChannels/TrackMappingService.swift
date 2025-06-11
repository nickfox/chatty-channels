// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/TrackMappingService.swift
import Foundation
import OSLog
import Combine // Added for ObservableObject

/// Service that provides a cached mapping from Logic Pro track names to their simple IDs (TR1, TR2, etc).
/// The mapping is persisted to SQLite database for reliability and concurrent access.
/// Uses accessibility APIs to discover tracks instead of AppleScript for better Logic Pro 11.2 compatibility.
public class TrackMappingService: ObservableObject { // Changed to class and added ObservableObject

    // MARK: - Dependencies
    private let runner: ProcessRunner
    private let database: SQLiteDatabase
    private let accessibilityService: AccessibilityTrackDiscoveryService
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "TrackMappingService")

    // MARK: - Init

    /// - Parameters:
    ///   - runner: Injectable `ProcessRunner` (kept for compatibility, may be used for fallback).
    ///   - database: SQLite database for persisting mappings.
    ///   - accessibilityService: Service for discovering tracks via accessibility APIs.
    public init(runner: ProcessRunner = PlaybackSafeProcessRunner(),
                database: SQLiteDatabase? = nil,
                accessibilityService: AccessibilityTrackDiscoveryService? = nil) {
        self.runner = runner
        self.database = database ?? SQLiteDatabase()
        self.accessibilityService = accessibilityService ?? AccessibilityTrackDiscoveryService()
    }

    // MARK: - Public API

    /// Loads the mapping of `TrackName -> SimpleID`.
    /// If mappings exist in the database they are returned immediately,
    /// otherwise accessibility APIs are used to discover tracks and the results are stored.
    public func loadMapping() throws -> [String: String] {
        logger.info("Attempting to load track mapping.")
        
        // Try to load from database first
        let cachedMappings = database.getAllTrackMappings()
        if !cachedMappings.isEmpty {
            logger.info("Successfully loaded \(cachedMappings.count) mappings from database.")
            return cachedMappings
        }
        
        logger.info("No mappings found in database. Proceeding with accessibility-based track discovery.")

        // Use accessibility service to discover tracks
        logger.info("Using accessibility APIs to discover Logic Pro tracks.")
        let mappings: [String: String]
        do {
            mappings = try accessibilityService.discoverTracks()
            logger.info("Accessibility-based track discovery successful. Found \(mappings.count) track mappings.")
        } catch {
            logger.error("Accessibility-based track discovery failed: \(error.localizedDescription, privacy: .public)")
            logger.info("Attempting fallback to AppleScript method.")
            
            // Fallback to AppleScript if accessibility fails
            do {
                let rawOutput = try runner.run("/usr/bin/osascript", arguments: ["-e", Self.handshakeAppleScript])
                mappings = Self.parseHandshake(output: rawOutput, logger: logger)
                logger.info("AppleScript fallback successful. Parsed \(mappings.count) track mappings.")
            } catch {
                logger.error("Both accessibility and AppleScript methods failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }

        // Persist to database
        var savedCount = 0
        for (cleanedTrackName, simpleID) in mappings {
            // Extract track number from ID like "TR1" -> 1
            let trackNumber = Int(simpleID.dropFirst(2)) ?? 0
            
            if database.saveTrackMapping(tempID: simpleID, logicUUID: simpleID, trackName: cleanedTrackName, trackNumber: trackNumber) {
                savedCount += 1
            } else {
                logger.warning("Failed to save mapping for track: \(cleanedTrackName) -> \(simpleID)")
            }
        }
        
        logger.info("Successfully persisted \(savedCount) of \(mappings.count) mappings to database.")
        return mappings
    }
    
    /// Get a specific track mapping by its simple ID (e.g., "TR1")
    public func getTrackByID(_ simpleID: String) -> (name: String, uuid: String)? {
        if let mapping = database.getMappingByTempID(simpleID) {
            return (name: mapping.trackName, uuid: mapping.logicUUID)
        }
        return nil
    }
    
    /// Clear all track mappings and force a refresh on next load
    public func clearMappings() {
        if database.clearAllMappings() {
            logger.info("All track mappings cleared from database.")
        } else {
            logger.error("Failed to clear track mappings from database.")
        }
    }

    // MARK: - Parsing helpers

    private static func parseHandshake(output: String, logger: Logger) -> [String: String] {
        var dict: [String: String] = [:]
        logger.debug("parseHandshake: Raw output:\n\(output)")
        
        for line in output.split(separator: "\n") {
            logger.debug("parseHandshake: Processing line: '\(line)'")
            
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                logger.warning("Skipping malformed line in AppleScript output: '\(line.description, privacy: .public)'")
                continue
            }
            let simpleID = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let trackDesc = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            logger.debug("parseHandshake: simpleID='\(simpleID)', trackDesc='\(trackDesc)'")
            
            // Extract track name from description like "Track 1 \"kick\""
            var trackName = trackDesc
            
            // Find the content between quotes (handle both regular and smart quotes)
            let quoteCharacters = CharacterSet(charactersIn: "\"\u{201C}\u{201D}")
            
            // Find first quote
            if let firstQuoteRange = trackDesc.rangeOfCharacter(from: quoteCharacters),
               let remainingString = trackDesc[firstQuoteRange.upperBound...].rangeOfCharacter(from: quoteCharacters) {
                let extractedName = String(trackDesc[firstQuoteRange.upperBound..<remainingString.lowerBound])
                trackName = extractedName
                logger.debug("parseHandshake: Found quoted name: '\(trackName)'")
            } else {
                logger.debug("parseHandshake: No quotes found, using full description")
            }
            
            if !simpleID.isEmpty && !trackName.isEmpty {
                logger.debug("parseHandshake: Adding mapping: '\(trackName)' -> '\(simpleID)'")
                dict[trackName] = simpleID
            } else {
                logger.warning("Skipping line with empty ID or Track Name after parsing: '\(line.description, privacy: .public)' -> ID='\(simpleID)', Track='\(trackName)'")
            }
        }
        
        logger.debug("parseHandshake: Final dictionary: \(dict)")
        return dict
    }

    // MARK: - AppleScript source (FALLBACK ONLY)

    /// Legacy AppleScript method for track discovery - used as fallback when accessibility APIs fail.
    /// Enumerates all tracks in Logic Pro by finding AXLayoutItem elements, printing `SimpleID:Name` on each line.
    /// Track names are found in AXLayoutItem elements with format "Track 1 \"kick\""
    /// NOTE: This may not work reliably in Logic Pro 11.2+ due to accessibility restrictions.
    private static let handshakeAppleScript = """
    tell application "Logic Pro" to activate
    delay 1
    
    tell application "System Events"
        tell process "Logic Pro"
            set trackList to ""
            set trackCounter to 0
            
            try
                set w to first window
                set allElements to entire contents of w
                
                repeat with elem in allElements
                    try
                        if role of elem is "AXLayoutItem" then
                            set d to description of elem
                            if d contains "Track" then
                                set trackCounter to trackCounter + 1
                                set simpleID to "TR" & trackCounter
                                -- Add to our output list with the full description
                                set trackList to trackList & simpleID & ":" & d & linefeed
                            end if
                        end if
                    end try
                end repeat
                
                if trackList is "" then
                    -- Fallback if no tracks found
                    return "TR1:Track 1" & linefeed & "TR2:Track 2" & linefeed & "TR3:Track 3"
                else
                    return trackList
                end if
                
            on error errMsg
                return "Error: " & errMsg
            end try
        end tell
    end tell
    """

    // MARK: - Defaults
    
    // Removed defaultCacheURL as we're now using SQLite database
}
