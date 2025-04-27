import Testing
import Foundation
@testable import ChattyChannels

private class MockProcessRunner: ProcessRunner {
    var responses: [Result<String, Error>] = []
    var callCount = 0

    func run(_ launchPath: String, arguments: [String]) throws -> String {
        callCount += 1
        guard !responses.isEmpty else {
            fatalError("No response configured for call \(callCount)")
        }
        let result = responses.removeFirst()
        switch result {
        case .success(let output): return output
        case .failure(let error): throw error
        }
    }
}

struct PlaybackSafeTests {
    @Test
    func testSucceedsAfterRetries() throws {
        let mock = MockProcessRunner()
        // Fail three times then succeed (4 total attempts)
        let sampleError = AppleScriptError.executionFailed("fail")
        mock.responses = [
            .failure(sampleError),
            .failure(sampleError),
            .failure(sampleError),
            .success("ok")
        ]
        let runner = PlaybackSafeProcessRunner(underlying: mock, maxRetries: 3, retryDelay: 0)
        let output = try runner.run("/usr/bin/osascript", arguments: ["-e", "script"])
        #expect(output == "ok")
        #expect(mock.callCount == 4) // Expect 4 calls (1 initial + 3 retries)
    }

    @Test
    func testFailsAfterMaxRetries() throws {
        let mock = MockProcessRunner()
        let sampleError = AppleScriptError.executionFailed("fail")
        // Provide 4 failure responses to cover all attempts
        mock.responses = [
            .failure(sampleError),
            .failure(sampleError),
            .failure(sampleError),
            .failure(sampleError)
        ]
        let runner = PlaybackSafeProcessRunner(underlying: mock, maxRetries: 3, retryDelay: 0)
        do {
            _ = try runner.run("/usr/bin/osascript", arguments: [])
            #expect(Bool(false), "Expected to throw after max retries")
        } catch let error as AppleScriptError {
            // Should be the last error
            switch error {
            case .executionFailed(let msg):
                #expect(msg.contains("fail"))
            default:
                #expect(Bool(false), "Expected executionFailed but got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected AppleScriptError but got \(error)")
        }
        #expect(mock.callCount == 4) // Expect 4 calls (1 initial + 3 retries)
    }
}
