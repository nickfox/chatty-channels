//
//  ChattyChannelsTests.swift
//  ChattyChannelsTests
//
//  Created by Nick on 4/1/25.
//

import Testing
import OSCKit // Need OSCKit for OSCMessage
@testable import ChattyChannels

struct ChattyChannelsTests {

    @Test func example() async throws {
        // Placeholder test
        #expect(true == true)
    }

    @Test func testOSCParameterChangeMessageFormat() throws {
        // Define test data
        let testParameterID = "GAIN"
        let testValue: Float = -12.5
        let expectedAddressPattern: OSCAddressPattern = "/aiplayer/set_parameter"

        // Simulate the message creation logic from OSCService.sendParameterChange
        // Arguments must match PluginProcessor: String (ID), Float (Value)
        let oscMessage = OSCMessage(expectedAddressPattern, values: [testParameterID, testValue])

        // --- Assertions ---
        #expect(oscMessage.addressPattern == expectedAddressPattern, "OSC address pattern should be \(expectedAddressPattern)")
        #expect(oscMessage.values.count == 2, "OSC message should have 2 arguments")

        // Check argument types (OSCKit stores them in an array of Any)
        let arg1 = try #require(oscMessage.values[0] as? String) // Use #require to fail test if cast fails
        let arg2 = try #require(oscMessage.values[1] as? Float)  // Use #require for Float cast

        #expect(arg1 == testParameterID, "First argument should be the parameter ID string")
        #expect(arg2 == testValue, "Second argument should be the float value")

        // Optional: Check specific type encoding if OSCKit provides it,
        // but checking the Swift type after casting is usually sufficient.
    }

    @Test func testNetworkServicePromptConstruction_Placeholder() {
        // TODO: Refactor NetworkService or use network mocking to properly test prompt construction.
        // This placeholder confirms the test suite structure.
        let service = NetworkService()
        let input = "Test user input"
        // let expectedStart = "You are an AI assistant integrated..." // Start of system prompt
        // In a real test with mocking, we would capture the request body
        // and assert that body.contents[0].parts[0].text starts with expectedStart
        // and contains the input string.
        #expect(true, "Placeholder test for NetworkService prompt construction")
    }

    @Test func testParameterCommandDecoding_Valid() throws {
        let validJsonString = """
        {"command": "set_parameter", "parameter_id": "GAIN", "value": -3.5}
        """
        let jsonData = Data(validJsonString.utf8)
        let decoder = JSONDecoder()

        let decodedCommand = try decoder.decode(ParameterCommand.self, from: jsonData)

        #expect(decodedCommand.command == "set_parameter")
        #expect(decodedCommand.parameter_id == "GAIN")
        #expect(decodedCommand.value == -3.5)
    }

    @Test func testParameterCommandDecoding_InvalidJson() {
        let invalidJsonString = """
        {"command": "set_parameter", "parameter_id": "GAIN", "value": "-3.5 // Missing closing brace
        """
        let jsonData = Data(invalidJsonString.utf8)
        let decoder = JSONDecoder()

        // Expect decoding to throw an error
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(ParameterCommand.self, from: jsonData)
        }
    }

     @Test func testParameterCommandDecoding_WrongCommand() throws {
        let wrongCommandJsonString = """
        {"command": "other_action", "parameter_id": "GAIN", "value": -3.5}
        """
        let jsonData = Data(wrongCommandJsonString.utf8)
        let decoder = JSONDecoder()

        // Decoding should succeed, but the command value is different
        let decodedCommand = try decoder.decode(ParameterCommand.self, from: jsonData)
        #expect(decodedCommand.command == "other_action")
        // The logic in ChattyChannelsApp should handle this by not triggering sendParameterChange
    }

     @Test func testParameterCommandDecoding_MissingKey() {
        let missingKeyJsonString = """
        {"command": "set_parameter", "value": -3.5}
        """
        let jsonData = Data(missingKeyJsonString.utf8)
        let decoder = JSONDecoder()

        // Expect decoding to throw a keyNotFound error (or similar)
         #expect(throws: DecodingError.keyNotFound) {
             _ = try decoder.decode(ParameterCommand.self, from: jsonData)
         }
    }

     @Test func testParameterCommandDecoding_WrongType() {
        let wrongTypeJsonString = """
        {"command": "set_parameter", "parameter_id": "GAIN", "value": "-3.5"}
        """ // Value is a string, not float
        let jsonData = Data(wrongTypeJsonString.utf8)
        let decoder = JSONDecoder()

        // Expect decoding to throw a typeMismatch error
         #expect(throws: DecodingError.typeMismatch) {
             _ = try decoder.decode(ParameterCommand.self, from: jsonData)
         }
    }

     @Test func testParameterCommandDecoding_PlainText() {
        let plainTextString = "This is just normal text."
        let textData = Data(plainTextString.utf8)
        let decoder = JSONDecoder()

        // Expect decoding to throw a dataCorrupted error (or similar)
         #expect(throws: DecodingError.dataCorrupted) {
             _ = try decoder.decode(ParameterCommand.self, from: textData)
         }
    }
}
