// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/PlaybackSafeProcessRunner.swift

import Foundation

/**
 A `ProcessRunner` decorator that retries failed executions to avoid transient
 errors caused by Logic Pro transport state (e.g. during playback).
 
 The implementation is purposely simple: it re-invokes the underlying runner
 up to `maxRetries` times, pausing `retryDelay` seconds between attempts.
 */
public struct PlaybackSafeProcessRunner: ProcessRunner {
    
    // MARK: ‑ Dependencies
    private let underlying: ProcessRunner
    
    // MARK: ‑ Configuration
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    
    // MARK: ‑ Init
    
    /// Creates a playback-safe runner.
    /// - Parameters:
    ///   - underlying: Concrete runner used to launch the process. Defaults to
    ///                 `DefaultProcessRunner`.
    ///   - maxRetries: Number of additional attempts after the initial failure.
    ///                 Must be ≥ 0. Defaults to 1 (total attempts = 2).
    ///   - retryDelay: Time (seconds) to wait between retries. Defaults to 0.1.
    public init(
        underlying: ProcessRunner = DefaultProcessRunner(),
        maxRetries: Int = 1,
        retryDelay: TimeInterval = 0.1
    ) {
        precondition(maxRetries >= 0, "maxRetries must be non-negative")
        precondition(retryDelay >= 0, "retryDelay must be non-negative")
        self.underlying  = underlying
        self.maxRetries  = maxRetries
        self.retryDelay  = retryDelay
    }
    
    // MARK: ‑ ProcessRunner
    
    /// Executes the command, retrying on failure according to the configuration.
    public func run(_ launchPath: String, arguments: [String]) throws -> String {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                return try underlying.run(launchPath, arguments: arguments)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    if retryDelay > 0 {
                        Thread.sleep(forTimeInterval: retryDelay)
                    }
                    continue
                }
            }
        }
        // All attempts failed; propagate the final error.
        throw lastError!
    }
}