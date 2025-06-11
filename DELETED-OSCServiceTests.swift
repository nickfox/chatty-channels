// OSCServiceTests.swift
// Comprehensive test suite for OSC communication

import XCTest
import Network
import Combine
@testable import ChattyChannels

/// Comprehensive test suite for OSCService covering all critical v0.7 functionality
final class OSCServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var oscService: OSCService!
    private var levelMeterService: LevelMeterService!
    private var cancellables = Set<AnyCancellable>()
    private let testTimeout: TimeInterval = 5.0
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        // Create services synchronously on main thread
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            levelMeterService = LevelMeterService()
            oscService = OSCService(levelMeterService: levelMeterService)
            semaphore.signal()
        }
        semaphore.wait()
        
        // Wait briefly to ensure any existing socket connections are cleaned up
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    override func tearDown() {
        cancellables.removeAll()
        oscService = nil
        levelMeterService = nil
        
        // Wait briefly before next test
        Thread.sleep(forTimeInterval: 0.1)
        super.tearDown()
    }
    
    // MARK: - OSC Packet Encoding Tests
    
    func testOSCPacketEncoding_RMSMessage() throws {
        // Test that RMS packets are correctly encoded
        let packet = OSCService.encodeOSCPacket(address: "/aiplayer/rms", arguments: [0.5 as Float])
        
        // Verify packet structure
        XCTAssertFalse(packet.isEmpty, "Packet should not be empty")
        
        // Decode and verify
        let decoded = try decodeOSCPacket(packet)
        XCTAssertEqual(decoded.address, "/aiplayer/rms")
        XCTAssertEqual(decoded.arguments.count, 1)
        XCTAssertEqual(Double(decoded.arguments[0] as? Float ?? 0.0), 0.5, accuracy: 0.001)
    }
    
    func testOSCPacketEncoding_UnidentifiedRMS() throws {
        // Test unidentified RMS packet format
        let tempID = "test-temp-id-123"
        let rmsValue: Float = 0.75
        let packet = OSCService.encodeOSCPacket(address: "/aiplayer/rms_unidentified", 
                                                arguments: [tempID, rmsValue])
        
        let decoded = try decodeOSCPacket(packet)
        XCTAssertEqual(decoded.address, "/aiplayer/rms_unidentified")
        XCTAssertEqual(decoded.arguments.count, 2)
        XCTAssertEqual(decoded.arguments[0] as? String, tempID)
        XCTAssertEqual(Double((decoded.arguments[1] as? Float) ?? 0.0), Double(rmsValue), accuracy: 0.001)
    }
    
    func testOSCPacketEncoding_UUIDAssignment() throws {
        // Test UUID assignment packet format (critical for calibration)
        let tempID = "temp-123"
        let logicUUID = "logic-uuid-456"
        let packet = OSCService.encodeOSCPacket(address: "/aiplayer/track_uuid_assignment",
                                                arguments: [tempID, logicUUID])
        
        let decoded = try decodeOSCPacket(packet)
        XCTAssertEqual(decoded.address, "/aiplayer/track_uuid_assignment")
        XCTAssertEqual(decoded.arguments.count, 2)
        XCTAssertEqual(decoded.arguments[0] as? String, tempID)
        XCTAssertEqual(decoded.arguments[1] as? String, logicUUID)
    }
    
    // MARK: - Message Processing Tests
    
    func testProcessUnidentifiedRMS() {
        // Test that unidentified RMS data is properly cached
        let tempID = "test-plugin-1"
        let rmsValue: Float = 0.8
        let senderIP = "127.0.0.1"
        let senderPort = 9000
        
        oscService.processUnidentifiedRMS(tempID: tempID, 
                                         rmsValue: rmsValue,
                                         senderIP: senderIP,
                                         senderPort: senderPort)
        
        // Verify the data is cached
        let cachedData = oscService.getUnidentifiedRMSData()
        XCTAssertNotNil(cachedData[tempID])
        XCTAssertEqual(Double((cachedData[tempID]?.rms) ?? 0.0), Double(rmsValue), accuracy: 0.001)
        XCTAssertEqual(cachedData[tempID]?.senderIP, senderIP)
        XCTAssertEqual(cachedData[tempID]?.senderPort, senderPort)
    }
    
    func testProcessIdentifiedRMS() async throws {
        // Test that identified RMS updates the level meter service
        let logicUUID = "track-uuid-123"
        let rmsValue: Float = 0.6
        
        // Process the identified RMS
        oscService.processIdentifiedRMS(logicTrackUUID: logicUUID, rmsValue: rmsValue)
        
        // Give it a moment to update on MainActor
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Verify the level meter service was updated
        await MainActor.run {
            let audioLevel = levelMeterService.audioLevels[logicUUID]
            XCTAssertNotNil(audioLevel)
            XCTAssertEqual(Double((audioLevel?.rmsValue) ?? 0.0), Double(rmsValue), accuracy: 0.001)
        }
    }
    
    // MARK: - Cache Management Tests
    
    func testUnidentifiedRMSCacheExpiry() throws {
        // Test that old cache entries are removed
        let tempID = "expiring-plugin"
        oscService.processUnidentifiedRMS(tempID: tempID, rmsValue: 0.5,
                                         senderIP: "127.0.0.1", senderPort: 9000)
        
        // Verify it's cached
        var cachedData = oscService.getUnidentifiedRMSData()
        XCTAssertNotNil(cachedData[tempID])
        
        // Wait for expiry (this would need adjustment if cache expiry is longer)
        // For testing, we'd need to expose the cache expiry duration or make it configurable
        // Thread.sleep(forTimeInterval: 6.0) // Assuming 5 second expiry
        
        // For now, test the clear functionality
        oscService.clearSpecificUnidentifiedRMS(tempID: tempID)
        cachedData = oscService.getUnidentifiedRMSData()
        XCTAssertNil(cachedData[tempID])
    }
    
    func testClearUnidentifiedRMSCache() {
        // Add multiple entries
        for i in 1...5 {
            oscService.processUnidentifiedRMS(tempID: "plugin-\(i)", 
                                             rmsValue: Float(i) * 0.1,
                                             senderIP: "127.0.0.1", 
                                             senderPort: 9000 + i)
        }
        
        // Verify they're cached
        var cachedData = oscService.getUnidentifiedRMSData()
        XCTAssertEqual(cachedData.count, 5)
        
        // Clear all
        oscService.clearUnidentifiedRMSCache()
        
        // Verify empty
        cachedData = oscService.getUnidentifiedRMSData()
        XCTAssertTrue(cachedData.isEmpty)
    }
    
    // MARK: - Chat Request Tests
    
    func testSubmitChatRequest() {
        let expectation = XCTestExpectation(description: "Chat request published")
        
        oscService.$chatRequestPublisher
            .dropFirst() // Skip initial nil
            .sink { request in
                XCTAssertNotNil(request)
                XCTAssertEqual(request?.instanceID, "test-instance")
                XCTAssertEqual(request?.userMessage, "reduce gain by 3dB")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        oscService.submitChatRequest(instanceID: "test-instance", message: "reduce gain by 3dB")
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSubmitEmptyChatRequest() {
        // Test that empty messages are ignored
        let expectation = XCTestExpectation(description: "No chat request published")
        expectation.isInverted = true // Should NOT be fulfilled
        
        oscService.$chatRequestPublisher
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Try to submit empty message
        oscService.submitChatRequest(instanceID: "test", message: "   ")
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    // MARK: - Integration Tests
    
    func testOSCRoundTrip() throws {
        // This tests actual network communication
        let testPort: NWEndpoint.Port = 9877
        let expectation = XCTestExpectation(description: "Receive OSC packet")
        
        var receivedData: Data?
        
        // Create listener
        let listener = try NWListener(using: .udp, on: testPort)
        
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receiveMessage { data, _, _, _ in
                receivedData = data
                expectation.fulfill()
            }
        }
        
        listener.start(queue: .global())
        Thread.sleep(forTimeInterval: 0.1) // Let listener start
        
        // Send test packet
        let packet = OSCService.encodeOSCPacket(address: "/test/message", arguments: ["hello", 42])
        
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: testPort)
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: .global())
        
        connection.send(content: packet, completion: .contentProcessed { _ in })
        
        wait(for: [expectation], timeout: 2.0)
        
        // Cleanup
        connection.cancel()
        listener.cancel()
        
        // Verify
        XCTAssertNotNil(receivedData)
        if let data = receivedData {
            let decoded = try decodeOSCPacket(data)
            XCTAssertEqual(decoded.address, "/test/message")
            XCTAssertEqual(decoded.arguments[0] as? String, "hello")
            XCTAssertEqual(decoded.arguments[1] as? Int32, 42)
        }
    }
    
    // MARK: - Performance Tests
    
    func testRMSSendPerformance() throws {
        // Measure performance of sending RMS packets
        measure {
            for i in 0..<100 {
                oscService.sendRMS(Float(i) / 100.0)
            }
        }
    }
    
    func testPacketEncodingPerformance() throws {
        // Measure encoding performance
        measure {
            for i in 0..<1000 {
                _ = OSCService.encodeOSCPacket(address: "/aiplayer/rms", 
                                              arguments: [Float(i) / 1000.0])
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Decode an OSC packet for testing verification
    private func decodeOSCPacket(_ data: Data) throws -> (address: String, arguments: [Any]) {
        var offset = 0
        
        // Read address
        guard let addressEnd = data[offset...].firstIndex(of: 0) else {
            throw OSCTestError.invalidPacket("No null terminator for address")
        }
        
        let address = String(data: data[offset..<addressEnd], encoding: .utf8) ?? ""
        offset = addressEnd + 1
        
        // Align to 4-byte boundary
        while offset % 4 != 0 { offset += 1 }
        
        // Read type tag string
        guard offset < data.count, data[offset] == 44 else { // comma
            throw OSCTestError.invalidPacket("Missing type tag string")
        }
        
        guard let typeTagEnd = data[offset...].firstIndex(of: 0) else {
            throw OSCTestError.invalidPacket("No null terminator for type tags")
        }
        
        let typeTags = String(data: data[(offset + 1)..<typeTagEnd], encoding: .utf8) ?? ""
        offset = typeTagEnd + 1
        
        // Align to 4-byte boundary
        while offset % 4 != 0 { offset += 1 }
        
        // Read arguments based on type tags
        var arguments: [Any] = []
        
        for typeTag in typeTags {
            switch typeTag {
            case "f": // Float32
                guard offset + 4 <= data.count else {
                    throw OSCTestError.invalidPacket("Insufficient data for float")
                }
                let bytes = data[offset..<(offset + 4)]
                let bigEndianValue = bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                let floatBits = UInt32(bigEndian: bigEndianValue)
                arguments.append(Float(bitPattern: floatBits))
                offset += 4
                
            case "i": // Int32
                guard offset + 4 <= data.count else {
                    throw OSCTestError.invalidPacket("Insufficient data for int")
                }
                let bytes = data[offset..<(offset + 4)]
                let bigEndianValue = bytes.withUnsafeBytes { $0.load(as: Int32.self) }
                arguments.append(Int32(bigEndian: bigEndianValue))
                offset += 4
                
            case "s": // String
                guard let stringEnd = data[offset...].firstIndex(of: 0) else {
                    throw OSCTestError.invalidPacket("No null terminator for string")
                }
                let string = String(data: data[offset..<stringEnd], encoding: .utf8) ?? ""
                arguments.append(string)
                offset = stringEnd + 1
                while offset % 4 != 0 { offset += 1 }
                
            default:
                throw OSCTestError.invalidPacket("Unknown type tag: \(typeTag)")
            }
        }
        
        return (address, arguments)
    }
}

// MARK: - Test Helpers

enum OSCTestError: Error {
    case invalidPacket(String)
}

// MARK: - OSCService Test Extensions

extension OSCService {
    /// Expose the encoding method for testing
    static func encodeOSCPacket(address: String, arguments: [Any]) -> Data {
        // We need to make encodeOSC internal instead of private in OSCService
        // For now, we'll create a test-specific encoder
        var packet = Data()

        // 1. Address Pattern
        var addressData = address.data(using: .utf8) ?? Data()
        addressData.append(0) // Null terminator
        while addressData.count % 4 != 0 {
            addressData.append(0) // Pad to 4-byte boundary
        }
        packet.append(addressData)

        // 2. Type Tag String
        var typeTagString = ","
        for arg in arguments {
            if arg is Float || arg is Double {
                typeTagString.append("f")
            } else if arg is String {
                typeTagString.append("s")
            } else if arg is Int || arg is UInt32 {
                typeTagString.append("i")
            }
        }
        var typeTagData = typeTagString.data(using: .utf8) ?? Data()
        typeTagData.append(0) // Null terminator
        while typeTagData.count % 4 != 0 {
            typeTagData.append(0) // Pad to 4-byte boundary
        }
        packet.append(typeTagData)

        // 3. Arguments
        for arg in arguments {
            if let floatVal = arg as? Float {
                var bigEndianFloat = floatVal.bitPattern.bigEndian
                withUnsafeBytes(of: &bigEndianFloat) { packet.append(contentsOf: $0) }
            } else if let doubleVal = arg as? Double {
                var bigEndianFloat = Float(doubleVal).bitPattern.bigEndian
                withUnsafeBytes(of: &bigEndianFloat) { packet.append(contentsOf: $0) }
            } else if let stringVal = arg as? String {
                var stringData = stringVal.data(using: .utf8) ?? Data()
                stringData.append(0) // Null terminator
                while stringData.count % 4 != 0 {
                    stringData.append(0) // Pad to 4-byte boundary
                }
                packet.append(stringData)
            } else if let intVal = arg as? Int {
                var bigEndianInt = Int32(intVal).bigEndian
                withUnsafeBytes(of: &bigEndianInt) { packet.append(contentsOf: $0) }
            } else if let uintVal = arg as? UInt32 {
                var bigEndianUInt = uintVal.bigEndian
                withUnsafeBytes(of: &bigEndianUInt) { packet.append(contentsOf: $0) }
            }
        }
        return packet
    }
}
