// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannelsTests/AppleScriptServiceTests.swift

import Testing
import Foundation
@testable import ChattyChannels

/// Mock runner to capture invocations and simulate output or errors.
private class MockProcessRunner: ProcessRunner {
    var lastLaunchPath: String?
    var lastArguments: [String]?
    var nextOutput: String = ""
    var nextError: Error?

    func run(_ launchPath: String, arguments: [String]) throws -> String {
        lastLaunchPath = launchPath
        lastArguments = arguments
        if let error = nextError {
            throw error
        }
        return nextOutput
    }
}

struct AppleScriptServiceTests {
    @Test
    func testGetVolumeReturnsParsedValue() throws {
        let mock = MockProcessRunner()
        // Simulate osascript returning " -3.5\n"
        mock.nextOutput = " -3.5\n"
        let service = AppleScriptService(runner: mock)

        let value = try service.getVolume(trackName: "Kick")
        #expect(value == -3.5, "Expected parsed volume to match output")

        // Verify it called the correct runner
        #expect(mock.lastLaunchPath == "/usr/bin/osascript")
        #expect(mock.lastArguments?.first == "-e")
        #expect(mock.lastArguments?.last?.contains("output volume of track named \"Kick\"") == true)
    }

    @Test
    func testGetVolumeThrowsParsingFailed() {
        let mock = MockProcessRunner()
        mock.nextOutput = "notANumber"
        let service = AppleScriptService(runner: mock)

        do {
            _ = try service.getVolume(trackName: "Kick")
            #expect(Bool(false), "Expected parsingFailed to be thrown for non-numeric output")
        } catch let error as AppleScriptError {
            switch error {
            case .parsingFailed:
                #expect(true)
            default:
                #expect(Bool(false), "Expected parsingFailed but got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected AppleScriptError but got \(error)")
        }
    }

    @Test
    func testSetVolumeInvokesRunnerWithCorrectScript() throws {
        let mock = MockProcessRunner()
        mock.nextOutput = ""  // setVolume ignores stdout
        let service = AppleScriptService(runner: mock)

        try service.setVolume(trackName: "Kick", db: -6.0)

        // Verify runner called with osascript path and script setting -6.0
        #expect(mock.lastLaunchPath == "/usr/bin/osascript")
        let scriptArg = mock.lastArguments?.last ?? ""
        #expect(scriptArg.contains("set output volume of track named \"Kick\" to -6.0"))
    }

    @Test
    func testExecutionFailedPropagatesError() {
        let mock = MockProcessRunner()
        mock.nextError = AppleScriptError.executionFailed("failure reason")
        let service = AppleScriptService(runner: mock)

        do {
            _ = try service.getVolume(trackName: "Kick")
            #expect(Bool(false), "Expected executionFailed to propagate")
        } catch let error as AppleScriptError {
            switch error {
            case .executionFailed(let msg):
                #expect(msg.contains("failure reason"))
            default:
                #expect(Bool(false), "Expected executionFailed but got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected AppleScriptError but got \(error)")
        }
    }
}