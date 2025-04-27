// /Users/nickfox137/Documents/chatty-channel/ChattyChannelsTests/MappingTests.swift

import Testing
import Foundation
@testable import ChattyChannels

private class MockProcessRunner: ProcessRunner {
    var callCount = 0
    var output: String = ""
    
    func run(_ launchPath: String, arguments: [String]) throws -> String {
        callCount += 1
        return output
    }
}

struct MappingTests {
    @Test
    func testHandshakeMapping() throws {
        // Use a temporary file for mapping cache.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let mappingFileURL = tempDir.appendingPathComponent("mapping_test.json")
        // Ensure the file does not exist prior to testing.
        try? FileManager.default.removeItem(at: mappingFileURL)
        
        let runner = MockProcessRunner()
        // Simulate AppleScript handshake output: each line has format "UUID:TrackName"
        runner.output = "1111-AAAA:Kick\n2222-BBBB:Snare\n"
        
        // Create the TrackMappingService with injected runner and custom mapping file URL.
        let service = TrackMappingService(runner: runner, mappingFileURL: mappingFileURL)
        let mapping = try service.loadMapping()
        
        #expect(mapping["Kick"] == "1111-AAAA", "Expected Kick track mapping to be '1111-AAAA'")
        #expect(mapping["Snare"] == "2222-BBBB", "Expected Snare track mapping to be '2222-BBBB'")
        #expect(runner.callCount == 1, "Runner should be called once since mapping file did not exist initially")
        
        // Second call should load from file cache without invoking the runner.
        let mappingCached = try service.loadMapping()
        #expect(mappingCached["Kick"] == "1111-AAAA", "Cached Kick mapping should persist")
        #expect(runner.callCount == 1, "Runner should not be called again after caching")
        
        // Clean up the temporary mapping file.
        try? FileManager.default.removeItem(at: mappingFileURL)
    }
}