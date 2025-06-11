// MockOSCListener.swift
// Mock OSC listener for testing OSC communication

import Foundation
import Network
@testable import ChattyChannels

/// Mock OSC listener that can simulate various network conditions for testing
class MockOSCListener {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.chatty.mock.osc.listener")
    
    /// Messages received by the listener
    private(set) var receivedMessages: [(address: String, arguments: [Any], timestamp: Date)] = []
    
    /// Closure called when a message is received
    var onMessageReceived: ((String, [Any]) -> Void)?
    
    /// Whether to simulate packet loss
    var simulatePacketLoss = false
    var packetLossRate: Double = 0.3 // 30% loss rate when enabled
    
    /// Whether to simulate delays
    var simulateDelay = false
    var delayRange: ClosedRange<TimeInterval> = 0.1...0.5
    
    /// Port the listener is bound to
    private(set) var port: NWEndpoint.Port = 0
    
    /// Start the mock listener on a specified port
    func start(on port: NWEndpoint.Port = 0) throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        if port == 0 {
            // Find an available port
            self.port = try findAvailablePort()
        } else {
            self.port = port
        }
        
        listener = try NWListener(using: params, on: self.port)
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: queue)
        
        // Wait for listener to be ready
        Thread.sleep(forTimeInterval: 0.1)
    }
    
    /// Stop the listener
    func stop() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        receivedMessages.removeAll()
    }
    
    /// Clear received messages
    func clearMessages() {
        queue.sync {
            receivedMessages.removeAll()
        }
    }
    
    /// Get count of messages matching an address pattern
    func messageCount(for address: String) -> Int {
        queue.sync {
            receivedMessages.filter { $0.address == address }.count
        }
    }
    
    /// Get the most recent message for an address
    func latestMessage(for address: String) -> (address: String, arguments: [Any])? {
        queue.sync {
            receivedMessages.last { $0.address == address }.map { ($0.address, $0.arguments) }
        }
    }
    
    // MARK: - Private Methods
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.start(queue: queue)
        
        // Start receiving messages
        receiveMessage(on: connection)
    }
    
    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }
            
            if let error = error {
                print("MockOSCListener: Receive error: \(error)")
                return
            }
            
            if let data = data {
                // Simulate packet loss if enabled
                if self.simulatePacketLoss {
                    let random = Double.random(in: 0...1)
                    if random < self.packetLossRate {
                        // Drop this packet
                        self.receiveMessage(on: connection)
                        return
                    }
                }
                
                // Simulate delay if enabled
                if self.simulateDelay {
                    let delay = TimeInterval.random(in: self.delayRange)
                    self.queue.asyncAfter(deadline: .now() + delay) {
                        self.processReceivedData(data)
                    }
                } else {
                    self.processReceivedData(data)
                }
            }
            
            // Continue receiving
            self.receiveMessage(on: connection)
        }
    }
    
    private func processReceivedData(_ data: Data) {
        do {
            let (address, arguments) = try decodeOSCPacket(data)
            
            queue.sync {
                receivedMessages.append((address, arguments, Date()))
            }
            
            onMessageReceived?(address, arguments)
            
        } catch {
            print("MockOSCListener: Failed to decode OSC packet: \(error)")
        }
    }
    
    private func findAvailablePort() throws -> NWEndpoint.Port {
        // Try ports in a range
        for port in 10000...10100 {
            do {
                let testListener = try NWListener(using: .udp, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
                testListener.cancel()
                return NWEndpoint.Port(integerLiteral: UInt16(port))
            } catch {
                continue
            }
        }
        throw MockOSCError.noAvailablePort
    }
    
    /// Decode an OSC packet
    private func decodeOSCPacket(_ data: Data) throws -> (address: String, arguments: [Any]) {
        var offset = 0
        
        // Read address
        guard let addressEnd = data[offset...].firstIndex(of: 0) else {
            throw MockOSCError.invalidPacket("No null terminator for address")
        }
        
        let address = String(data: data[offset..<addressEnd], encoding: .utf8) ?? ""
        offset = addressEnd + 1
        
        // Align to 4-byte boundary
        while offset % 4 != 0 { offset += 1 }
        
        // Read type tag string
        guard offset < data.count, data[offset] == 44 else { // comma
            throw MockOSCError.invalidPacket("Missing type tag string")
        }
        
        guard let typeTagEnd = data[offset...].firstIndex(of: 0) else {
            throw MockOSCError.invalidPacket("No null terminator for type tags")
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
                    throw MockOSCError.invalidPacket("Insufficient data for float")
                }
                let bytes = data[offset..<(offset + 4)]
                let bigEndianValue = bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                let floatBits = UInt32(bigEndian: bigEndianValue)
                arguments.append(Float(bitPattern: floatBits))
                offset += 4
                
            case "i": // Int32
                guard offset + 4 <= data.count else {
                    throw MockOSCError.invalidPacket("Insufficient data for int")
                }
                let bytes = data[offset..<(offset + 4)]
                let bigEndianValue = bytes.withUnsafeBytes { $0.load(as: Int32.self) }
                arguments.append(Int32(bigEndian: bigEndianValue))
                offset += 4
                
            case "s": // String
                guard let stringEnd = data[offset...].firstIndex(of: 0) else {
                    throw MockOSCError.invalidPacket("No null terminator for string")
                }
                let string = String(data: data[offset..<stringEnd], encoding: .utf8) ?? ""
                arguments.append(string)
                offset = stringEnd + 1
                while offset % 4 != 0 { offset += 1 }
                
            default:
                throw MockOSCError.invalidPacket("Unknown type tag: \(typeTag)")
            }
        }
        
        return (address, arguments)
    }
}

enum MockOSCError: Error {
    case noAvailablePort
    case invalidPacket(String)
}
