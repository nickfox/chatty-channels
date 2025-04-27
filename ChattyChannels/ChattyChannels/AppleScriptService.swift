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
import OSLog

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
}

/// Thin wrapper for mixing-console AppleScript commands.
public final class AppleScriptService: AppleScriptServiceProtocol {
    
    // Dependency-injected runner
    private let runner: ProcessRunner
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "chatty",
                                category: "AppleScriptService")
    
    public init(runner: ProcessRunner = PlaybackSafeProcessRunner()) {
        self.runner = runner
    }
    
    // MARK: Public API
    
    /// Returns the current fader gain (dB) of the given track.
    /// - Parameter trackName: Exact track name as shown in Logic’s mixer.
    /// - Throws: `AppleScriptError` if the command fails or output can’t be parsed.
    public func getVolume(trackName: String) throws -> Float {
        let script = """
        tell application "Logic Pro"
            set _val to output volume of track named "\(trackName)"
        end tell
        return _val
        """
        let output = try runAppleScript(script)
        guard let value = Float(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AppleScriptError.parsingFailed(output)
        }
        return value
    }
    
    /// Sets the fader gain (dB) of the given track.
    /// - Parameters:
    ///   - trackName: Target track.
    ///   - db: New gain in decibels.
    public func setVolume(trackName: String, db: Float) throws {
        let script = """
        tell application "Logic Pro"
            set output volume of track named "\(trackName)" to \(db)
        end tell
        """
        _ = try runAppleScript(script) // ignore stdout
    }
    
    // MARK: Private helpers
    
    @discardableResult
    private func runAppleScript(_ source: String) throws -> String {
        logger.debug("Running AppleScript (hash): \(source.hashValue, privacy: .public)")
        let out = try runner.run("/usr/bin/osascript", arguments: ["-e", source])
        logger.debug("AppleScript returned: \(out, privacy: .private(mask: .hash))")
        return out
    }
}