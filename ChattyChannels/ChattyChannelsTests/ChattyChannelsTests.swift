//
//  ChattyChannelsTests.swift
//  ChattyChannelsTests
//
//  Created by Nick on 4/1/25.
//

import Testing
import Foundation
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
    }

    @Test func testNetworkServicePromptConstruction_Placeholder() {
        // TODO: Refactor NetworkService or use network mocking to properly test prompt construction.
        // This placeholder confirms the test suite structure.
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
        do {
            _ = try decoder.decode(ParameterCommand.self, from: jsonData)
            #expect(Bool(false), "Expected decoding to fail due to invalid JSON")
        } catch let error as DecodingError {
            switch error {
            case .dataCorrupted(let context):
                #expect(context.debugDescription.contains("The given data was not valid JSON"), "Expected error to indicate invalid JSON")
            default:
                #expect(Bool(false), "Expected a dataCorrupted error, but got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected a DecodingError, but got \(error)")
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

        // Catch the error and verify it's a keyNotFound error
        do {
            _ = try decoder.decode(ParameterCommand.self, from: jsonData)
            #expect(Bool(false), "Expected decoding to fail due to missing key")
        } catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, let context):
                #expect(key.stringValue == "parameter_id", "Expected missing key to be 'parameter_id'")
                #expect(context.debugDescription.contains("No value associated with key"), "Expected error to indicate missing key")
            default:
                #expect(Bool(false), "Expected a keyNotFound error, but got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected a DecodingError, but got \(error)")
        }
    }

    @Test func testParameterCommandDecoding_WrongType() {
        let wrongTypeJsonString = """
        {"command": "set_parameter", "parameter_id": "GAIN", "value": "-3.5"}
        """ // Value is a string, not float
        let jsonData = Data(wrongTypeJsonString.utf8)
        let decoder = JSONDecoder()

        // Catch the error and verify it's a typeMismatch error
        do {
            _ = try decoder.decode(ParameterCommand.self, from: jsonData)
            #expect(Bool(false), "Expected decoding to fail due to type mismatch")
        } catch let error as DecodingError {
            switch error {
            case .typeMismatch(let type, let context):
                #expect(type == Float.self, "Expected type mismatch on Float")
                #expect(context.debugDescription.contains("Expected to decode Float"), "Expected error to indicate type mismatch")
            default:
                #expect(Bool(false), "Expected a typeMismatch error, but got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected a DecodingError, but got \(error)")
        }
    }

    @Test func testParameterCommandDecoding_PlainText() {
        let plainTextString = "This is just normal text."
        let textData = Data(plainTextString.utf8)
        let decoder = JSONDecoder()

        // Catch the error and verify it's a dataCorrupted error
        do {
            _ = try decoder.decode(ParameterCommand.self, from: textData)
            #expect(Bool(false), "Expected decoding to fail due to invalid JSON")
        } catch let error as DecodingError {
            switch error {
            case .dataCorrupted(let context):
                #expect(context.debugDescription.contains("The given data was not valid JSON"), "Expected error to indicate invalid JSON")
            default:
                #expect(Bool(false), "Expected a dataCorrupted error, but got \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected a DecodingError, but got \(error)")
        }
    }
}
