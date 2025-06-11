// OSCRetryTests.swift
// Tests for OSC message retry mechanism (Task T-05)

import XCTest
import Network
@testable import ChattyChannels

/// Tests for the OSC retry mechanism implementation (Task T-05 from plan.md)
final class OSCRetryTests: XCTestCase {
    
    private var oscService: OSCService!
    private var mockListener: MockOSCListener!
    private var levelMeterService: LevelMeterService!
    
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
        mockListener = MockOSCListener()
    }
    
    override func tearDown() {
        mockListener?.stop()
        mockListener = nil
        oscService = nil
        levelMeterService = nil
        super.tearDown()
    }
    
    // MARK: - Basic Retry Tests
    
    func testSendWithRetry_SuccessfulDelivery() throws {
        // Start mock listener
        try mockListener.start()
        let port = mockListener.port
        
        let expectation = XCTestExpectation(description: "Message received")
        
        mockListener.onMessageReceived = { address, arguments in
            if address == "/aiplayer/track_uuid_assignment" {
                expectation.fulfill()
            }
        }
        
        // Send critical message with retry
        oscService.sendWithRetry(
            address: "/aiplayer/track_uuid_assignment",
            arguments: ["temp-123", "logic-uuid-456"],
            critical: true,
            customEndpoint: .init("127.0.0.1"),
            customPort: port
        )
        
        wait(for: [expectation], timeout: 2.0)
        
        // Verify message was received
        let messages = mockListener.receivedMessages
        XCTAssertGreaterThan(messages.count, 0, "Should have received at least one message")
        
        if let firstMessage = messages.first {
            XCTAssertEqual(firstMessage.address, "/aiplayer/track_uuid_assignment")
            XCTAssertEqual(firstMessage.arguments.count, 3) // sequence number + 2 args
            
            // First argument should be sequence number
            XCTAssertNotNil(firstMessage.arguments[0] as? UInt32)
            XCTAssertEqual(firstMessage.arguments[1] as? String, "temp-123")
            XCTAssertEqual(firstMessage.arguments[2] as? String, "logic-uuid-456")
        }
    }
    
    func testSendWithRetry_NonCriticalMessage() throws {
        // Non-critical messages should not have sequence numbers or retry
        try mockListener.start()
        let port = mockListener.port
        
        let expectation = XCTestExpectation(description: "Message received")
        
        mockListener.onMessageReceived = { address, arguments in
            if address == "/aiplayer/rms" {
                expectation.fulfill()
            }
        }
        
        // Send non-critical message
        oscService.sendWithRetry(
            address: "/aiplayer/rms",
            arguments: [0.5 as Float],
            critical: false,
            customEndpoint: .init("127.0.0.1"),
            customPort: port
        )
        
        wait(for: [expectation], timeout: 1.0)
        
        // Verify message format
        let messages = mockListener.receivedMessages
        XCTAssertEqual(messages.count, 1, "Non-critical message should be sent only once")
        
        if let message = messages.first {
            XCTAssertEqual(message.address, "/aiplayer/rms")
            XCTAssertEqual(message.arguments.count, 1) // No sequence number
            XCTAssertEqual((message.arguments[0] as? Float) ?? 0.0, 0.5, accuracy: 0.001)
        }
    }
    
    func testSendWithRetry_PacketLoss() throws {
        // Test retry mechanism with simulated packet loss
        try mockListener.start()
        let port = mockListener.port
        
        // Enable packet loss simulation
        mockListener.simulatePacketLoss = true
        mockListener.packetLossRate = 0.5 // 50% loss rate
        
        let expectation = XCTestExpectation(description: "Message eventually received")
        var receivedCount = 0
        
        mockListener.onMessageReceived = { address, arguments in
            if address == "/aiplayer/track_uuid_assignment" {
                receivedCount += 1
                if receivedCount == 1 {
                    expectation.fulfill()
                }
            }
        }
        
        // Send critical message - should retry on packet loss
        oscService.sendWithRetry(
            address: "/aiplayer/track_uuid_assignment",
            arguments: ["temp-789", "logic-uuid-101"],
            critical: true,
            customEndpoint: .init("127.0.0.1"),
            customPort: port
        )
        
        // Wait longer to account for retries
        wait(for: [expectation], timeout: 5.0)
        
        // Should have received the message despite packet loss
        XCTAssertGreaterThan(receivedCount, 0, "Message should eventually be received despite packet loss")
    }
    
    func testSendWithRetry_SequenceNumbers() throws {
        // Test that sequence numbers increment correctly
        try mockListener.start()
        let port = mockListener.port
        
        let expectation = XCTestExpectation(description: "All messages received")
        expectation.expectedFulfillmentCount = 3
        
        var sequenceNumbers: [UInt32] = []
        
        mockListener.onMessageReceived = { address, arguments in
            if address == "/test/sequence" {
                if let seqNum = arguments.first as? UInt32 {
                    sequenceNumbers.append(seqNum)
                }
                expectation.fulfill()
            }
        }
        
        // Send multiple messages to same address
        for i in 0..<3 {
            oscService.sendWithRetry(
                address: "/test/sequence",
                arguments: ["message-\(i)"],
                critical: true,
                customEndpoint: .init("127.0.0.1"),
                customPort: port
            )
            Thread.sleep(forTimeInterval: 0.1) // Small delay between sends
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        // Verify sequence numbers are sequential
        XCTAssertEqual(sequenceNumbers.count, 3)
        if sequenceNumbers.count >= 3 {
            XCTAssertEqual(sequenceNumbers[1], sequenceNumbers[0] + 1)
            XCTAssertEqual(sequenceNumbers[2], sequenceNumbers[1] + 1)
        }
    }
    
    // MARK: - UUID Assignment Specific Tests
    
    func testSendUUIDAssignment() throws {
        // Test the specific UUID assignment method
        try mockListener.start()
        let port = Int(mockListener.port.rawValue)
        
        let expectation = XCTestExpectation(description: "UUID assignment received")
        
        mockListener.onMessageReceived = { address, arguments in
            if address == "/aiplayer/track_uuid_assignment" {
                expectation.fulfill()
            }
        }
        
        // Send UUID assignment
        oscService.sendUUIDAssignment(
            toPluginIP: "127.0.0.1",
            port: port,
            tempInstanceID: "temp-abc-123",
            logicTrackUUID: "LOGIC-TRACK-UUID-456"
        )
        
        wait(for: [expectation], timeout: 2.0)
        
        // Verify the message format
        if let message = mockListener.latestMessage(for: "/aiplayer/track_uuid_assignment") {
            XCTAssertEqual(message.arguments.count, 3) // seq + 2 args
            XCTAssertEqual(message.arguments[1] as? String, "temp-abc-123")
            XCTAssertEqual(message.arguments[2] as? String, "LOGIC-TRACK-UUID-456")
        } else {
            XCTFail("UUID assignment message not received")
        }
    }
    
    // MARK: - Stress Tests
    
    func testRetryUnderLoad() throws {
        // Test retry mechanism under heavy load
        try mockListener.start()
        let port = mockListener.port
        
        // Enable both packet loss and delay
        mockListener.simulatePacketLoss = true
        mockListener.packetLossRate = 0.3
        mockListener.simulateDelay = true
        mockListener.delayRange = 0.05...0.2
        
        let messageCount = 10
        let expectation = XCTestExpectation(description: "All critical messages eventually received")
        expectation.expectedFulfillmentCount = messageCount
        
        var receivedMessages = Set<String>()
        
        mockListener.onMessageReceived = { address, arguments in
            if address == "/test/stress" {
                if arguments.count >= 2, let messageId = arguments[1] as? String {
                    if !receivedMessages.contains(messageId) {
                        receivedMessages.insert(messageId)
                        expectation.fulfill()
                    }
                }
            }
        }
        
        // Send many critical messages rapidly
        for i in 0..<messageCount {
            oscService.sendWithRetry(
                address: "/test/stress",
                arguments: ["msg-\(i)"],
                critical: true,
                customEndpoint: .init("127.0.0.1"),
                customPort: port
            )
        }
        
        // Allow extra time for retries
        wait(for: [expectation], timeout: 10.0)
        
        XCTAssertEqual(receivedMessages.count, messageCount, "All messages should eventually be received")
    }
    
    // MARK: - Performance Tests
    
    func testRetryPerformance() throws {
        // Measure performance impact of retry mechanism
        try mockListener.start()
        let port = mockListener.port
        
        measure {
            // Send a mix of critical and non-critical messages
            for i in 0..<50 {
                let critical = i % 2 == 0
                oscService.sendWithRetry(
                    address: "/test/performance",
                    arguments: [i],
                    critical: critical,
                    customEndpoint: .init("127.0.0.1"),
                    customPort: port
                )
            }
        }
    }
}
