// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/TrackMappingService.swift
import Foundation

/// Service that provides a cached mapping from Logic Pro track names to their UUIDs.
/// The mapping is persisted to JSON on disk so subsequent calls avoid the AppleScript handshake.
///
/// Handshake output format expected from AppleScript runner:
///     UUID:TrackName\n
/// Example:
///     1111-AAAA:Kick
///     2222-BBBB:Snare
public struct TrackMappingService {

    // MARK: - Dependencies
    private let runner: ProcessRunner
    private let mappingFileURL: URL

    // MARK: - Init

    /// - Parameters:
    ///   - runner: Injectable `ProcessRunner` used to execute the AppleScript handshake.
    ///   - mappingFileURL: Location of the JSON file that caches the mapping.
    public init(runner: ProcessRunner = PlaybackSafeProcessRunner(),
                mappingFileURL: URL = TrackMappingService.defaultCacheURL) {
        self.runner = runner
        self.mappingFileURL = mappingFileURL
    }

    // MARK: - Public API

    /// Loads the mapping of `TrackName -> UUID`.
    /// If the cache file exists it is returned immediately,
    /// otherwise an AppleScript handshake is executed and the result stored.
    public func loadMapping() throws -> [String: String] {
        if FileManager.default.fileExists(atPath: mappingFileURL.path) {
            let data = try Data(contentsOf: mappingFileURL)
            let dict = try JSONDecoder().decode([String: String].self, from: data)
            return dict
        }

        // Run AppleScript handshake to obtain mapping
        let raw = try runner.run("/usr/bin/osascript",
                                 arguments: ["-e", Self.handshakeAppleScript])
        let mapping = Self.parseHandshake(output: raw)

        // Persist to cache
        let dir = mappingFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(mapping)
        try data.write(to: mappingFileURL, options: .atomic)

        return mapping
    }

    // MARK: - Parsing helpers

    private static func parseHandshake(output: String) -> [String: String] {
        var dict: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let uuid = String(parts[0])
            let track = String(parts[1])
            dict[track] = uuid
        }
        return dict
    }

    // MARK: - AppleScript source

    /// Enumerates all tracks in Logic Pro, printing `UUID:Name` on each line.
    private static let handshakeAppleScript = """
    tell application "Logic Pro"
        set outLines to ""
        repeat with tr in every track
            set outLines to outLines & (id of tr) & ":" & (name of tr) & linefeed
        end repeat
    end tell
    return outLines
    """

    // MARK: - Defaults

    public static var defaultCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("chatty_track_mapping.json")
    }
}
