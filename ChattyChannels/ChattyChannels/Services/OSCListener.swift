// OSCListener.swift
// 
// Network listener for incoming OSC messages from AIPlayer plugins

import Foundation
import Network
import OSLog

/// Handles incoming OSC messages from AIPlayer plugins
public class OSCListener: ObservableObject, @unchecked Sendable {
    private var listener: NWListener?
    private let oscService: OSCService
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "OSCListener")
    private let listenerQueue = DispatchQueue(label: "com.chatty.osc.listener", qos: .userInteractive)
    
    @Published public var isListening: Bool = false
    @Published public var listenPort: UInt16 = 8999
    
    public init(oscService: OSCService, port: UInt16 = 8999) {
        self.oscService = oscService
        self.listenPort = port
    }
    
    /// Starts listening for incoming OSC messages
    @MainActor
    public func startListening() async throws {
        guard !isListening else {
            logger.info("OSC Listener already running")
            return
        }
        
        // Try port 8999 first (avoiding conflict with plugin ports), then fallback ports
        let portsToTry: [UInt16] = [8999, 8998, 8997, 8996, 8995]
        var lastError: Error?
        
        for portToTry in portsToTry {
            do {
                let port = NWEndpoint.Port(rawValue: portToTry)!
                let params = NWParameters.udp
                params.allowLocalEndpointReuse = true
                
                listener = try NWListener(using: params, on: port)
                
                listener?.newConnectionHandler = { [weak self] connection in
                    Task {
                        await self?.handleNewConnection(connection)
                    }
                }
                
                listener?.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor [weak self] in
                        switch state {
                        case .ready:
                            self?.isListening = true
                            self?.listenPort = portToTry
                            self?.logger.info("OSC Listener started on port \(portToTry)")
                        case .failed(let error):
                            self?.isListening = false
                            self?.logger.error("OSC Listener failed on port \(portToTry): \(error.localizedDescription)")
                        case .cancelled:
                            self?.isListening = false
                            self?.logger.info("OSC Listener cancelled")
                        default:
                            break
                        }
                    }
                }
                
                listener?.start(queue: listenerQueue)
                
                // If we get here without throwing, we successfully bound to this port
                logger.info("Successfully bound OSC Listener to port \(portToTry)")
                return
                
            } catch {
                lastError = error
                logger.warning("Failed to bind to port \(portToTry): \(error.localizedDescription)")
                continue
            }
        }
        
        // If we get here, all ports failed
        logger.error("Failed to start OSC Listener on any port: \(lastError?.localizedDescription ?? "Unknown error")")
        throw lastError ?? NSError(domain: "OSCListener", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind to any available port"])
    }
    
    /// Stops listening for incoming OSC messages
    @MainActor
    public func stopListening() {
        listener?.cancel()
        listener = nil
        isListening = false
        logger.info("OSC Listener stopped")
    }
    
    private func handleNewConnection(_ connection: NWConnection) async {
        connection.start(queue: listenerQueue)
        
        // For UDP, we need to keep receiving messages
        let weakSelf = self
        func receiveNextMessage() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    Task {
                        await weakSelf.processIncomingOSCData(data, from: connection)
                    }
                }
                
                if let error = error {
                    weakSelf.logger.error("Connection receive error: \(error.localizedDescription)")
                    return
                }
                
                // For UDP, continue receiving
                receiveNextMessage()
            }
        }
        
        receiveNextMessage()
    }
    
    private func processIncomingOSCData(_ data: Data, from connection: NWConnection) async {
        do {
            let message = try parseOSCMessage(data)
            // Only log non-RMS messages to reduce spam
            if !message.address.contains("rms") {
                logger.debug("Received OSC: \(message.address) with \(message.arguments.count) args")
            }
            
            // Route to appropriate handler based on address pattern
            switch message.address {
            case "/aiplayer/rms_unidentified":
                await handleUnidentifiedRMS(message, from: connection)
                
            case "/aiplayer/rms":
                await handleIdentifiedRMS(message)
                
            case "/aiplayer/rms_response":
                await handleRMSResponse(message)
                
            case let address where address.hasPrefix("/aiplayer/rms_"):
                // Handle port-based RMS messages (e.g., /aiplayer/rms_9002)
                // But exclude rms_response and rms_unidentified which are handled above
                await handlePortBasedRMS(message, address: address)
                
            case "/aiplayer/chat/request":
                await handleChatRequest(message)
                
            case "/aiplayer/request_port":
                await handlePortRequest(message, from: connection)
                
            case "/aiplayer/port_confirmed":
                await handlePortConfirmation(message)
                
            case "/aiplayer/uuid_assignment_confirmed":
                await handleUUIDAssignmentConfirmation(message)
                
            case "/aiplayer/start_tone", "/aiplayer/stop_tone", "/aiplayer/query_rms":
                // These are outgoing messages TO plugins, not incoming FROM plugins
                logger.debug("Received echo of outgoing message: \(message.address)")
                
            case "/aiplayer/tone_started":
                await handleToneStarted(message)
                
            case "/aiplayer/tone_stopped":
                await handleToneStopped(message)
                
            default:
                logger.debug("Unknown OSC address: \(message.address)")
            }
            
        } catch {
            logger.error("Failed to parse OSC message: \(error.localizedDescription)")
        }
    }
    
    private func handleUnidentifiedRMS(_ message: OSCMessage, from connection: NWConnection) async {
        guard message.arguments.count >= 2,
              let tempID = message.arguments[0] as? String,
              let rmsValue = message.arguments[1] as? Float else {
            logger.error("Invalid unidentified RMS message format")
            return
        }
        
        // Extract sender info from connection
        let senderIP = extractIPFromConnection(connection)
        let senderPort = extractPortFromConnection(connection)
        
        oscService.processUnidentifiedRMS(
            tempID: tempID,
            rmsValue: rmsValue,
            senderIP: senderIP,
            senderPort: senderPort
        )
    }
    
    private func handleIdentifiedRMS(_ message: OSCMessage) async {
        guard message.arguments.count >= 2,
              let logicTrackUUID = message.arguments[0] as? String,
              let rmsValue = message.arguments[1] as? Float else {
            logger.error("Invalid identified RMS message format")
            return
        }
        
        oscService.processIdentifiedRMS(logicTrackUUID: logicTrackUUID, rmsValue: rmsValue)
    }
    
    private func handlePortBasedRMS(_ message: OSCMessage, address: String) async {
        guard message.arguments.count >= 2,
              let tempID = message.arguments[0] as? String,
              let rmsValue = message.arguments[1] as? Float else {
            logger.error("Invalid port-based RMS message format")
            return
        }
        
        // Extract port number from address (e.g., /aiplayer/rms_9002 -> 9002)
        let addressParts = address.split(separator: "_")
        guard addressParts.count == 2,
              let portString = addressParts.last,
              let port = UInt16(portString) else {
            logger.error("Could not extract port from RMS address: \(address)")
            return
        }
        
        // Process as identified RMS using the tempID-to-UUID mapping if available
        // For now, forward to a new method that can handle port-based identification
        oscService.processPortBasedRMS(tempID: tempID, port: port, rmsValue: rmsValue)
    }
    
    private func handleRMSResponse(_ message: OSCMessage) async {
        guard message.arguments.count >= 3,
              let queryID = message.arguments[0] as? String,
              let tempInstanceID = message.arguments[1] as? String,
              let currentRMS = message.arguments[2] as? Float else {
            logger.error("Invalid RMS response message format")
            return
        }
        
        logger.debug("Received RMS response: queryID=\(queryID), tempID=\(tempInstanceID), RMS=\(currentRMS)")
        oscService.processRMSResponse(queryID: queryID, tempInstanceID: tempInstanceID, currentRMS: currentRMS)
    }
    
    private func handleChatRequest(_ message: OSCMessage) async {
        guard message.arguments.count >= 2,
              let instanceID = message.arguments[0] as? String,
              let userMessage = message.arguments[1] as? String else {
            logger.error("Invalid chat request message format")
            return
        }
        
        oscService.submitChatRequest(instanceID: instanceID, message: userMessage)
    }
    
    private func handlePortRequest(_ message: OSCMessage, from connection: NWConnection) async {
        guard message.arguments.count >= 1,
              let tempID = message.arguments[0] as? String else {
            logger.error("Invalid port request message format")
            return
        }
        
        // Extract optional preferred port
        let preferredPort: Int32? = message.arguments.count >= 2 ? message.arguments[1] as? Int32 : nil
        
        // Extract response port (where to send the assignment back)
        let responsePort: Int32 = message.arguments.count >= 3 ? (message.arguments[2] as? Int32 ?? 0) : 0
        
        // Extract sender info from connection
        let senderIP = extractIPFromConnection(connection)
        let senderPort = responsePort > 0 ? Int(responsePort) : extractPortFromConnection(connection)
        
        logger.info("Handling port request from \(tempID) at \(senderIP):\(senderPort) (responsePort: \(responsePort))")
        
        oscService.handlePortRequest(
            tempID: tempID,
            preferredPort: preferredPort,
            senderIP: senderIP,
            senderPort: senderPort
        )
    }
    
    private func handlePortConfirmation(_ message: OSCMessage) async {
        guard message.arguments.count >= 3,
              let tempID = message.arguments[0] as? String,
              let port = message.arguments[1] as? Int32,
              let status = message.arguments[2] as? String else {
            logger.error("Invalid port confirmation message format")
            return
        }
        
        logger.info("Handling port confirmation from \(tempID): port \(port), status: \(status)")
        
        oscService.handlePortConfirmation(
            tempID: tempID,
            port: port,
            status: status
        )
    }
    
    private func handleUUIDAssignmentConfirmation(_ message: OSCMessage) async {
        guard message.arguments.count >= 3 else {
            logger.error("Invalid UUID assignment confirmation message format: expected 3+ args, got \(message.arguments.count)")
            return
        }
        
        // Try different parsing approaches based on what the plugin might be sending
        
        // Approach 1: Original expectation (seq, tempID, logicID)
        if let sequenceNumber = message.arguments[0] as? UInt32,
           let tempID = message.arguments[1] as? String,
           let logicTrackUUID = message.arguments[2] as? String {
            
            logger.info("Received UUID assignment confirmation (format 1): seq=\(sequenceNumber), tempID=\(tempID), logicID=\(logicTrackUUID)")
            
            oscService.handleUUIDAssignmentConfirmation(
                sequenceNumber: sequenceNumber,
                tempID: tempID,
                logicTrackUUID: logicTrackUUID
            )
            return
        }
        
        // Approach 2: Maybe no sequence number? (tempID, logicID, status?)
        if let tempID = message.arguments[0] as? String,
           let logicTrackUUID = message.arguments[1] as? String {
            
            logger.info("Received UUID assignment confirmation (format 2): tempID=\(tempID), logicID=\(logicTrackUUID)")
            
            // We need to find the sequence number somehow - for now, let's handle without it
            oscService.handleUUIDAssignmentConfirmationLegacy(
                tempID: tempID,
                logicTrackUUID: logicTrackUUID
            )
            return
        }
        
        // Approach 3: Maybe sequence is Int32 instead of UInt32?
        if let sequenceNumber = message.arguments[0] as? Int32,
           let tempID = message.arguments[1] as? String,
           let logicTrackUUID = message.arguments[2] as? String {
            
            logger.info("Received UUID assignment confirmation (format 3): seq=\(sequenceNumber), tempID=\(tempID), logicID=\(logicTrackUUID)")
            
            oscService.handleUUIDAssignmentConfirmation(
                sequenceNumber: UInt32(sequenceNumber),
                tempID: tempID,
                logicTrackUUID: logicTrackUUID
            )
            return
        }
        
        logger.error("Could not parse UUID assignment confirmation with any known format")
    }
    
    private func handleToneStarted(_ message: OSCMessage) async {
        guard message.arguments.count >= 2,
              let tempID = message.arguments[0] as? String,
              let frequency = message.arguments[1] as? Float else {
            logger.error("Invalid tone started message format")
            return
        }
        
        logger.debug("Plugin \(tempID) confirmed tone started at \(frequency)Hz")
    }
    
    private func handleToneStopped(_ message: OSCMessage) async {
        guard message.arguments.count >= 1,
              let tempID = message.arguments[0] as? String else {
            logger.error("Invalid tone stopped message format")
            return
        }
        
        logger.debug("Plugin \(tempID) confirmed tone stopped")
    }
    
    // Helper functions to extract connection info
    private func extractIPFromConnection(_ connection: NWConnection) -> String {
        if case .hostPort(let host, _) = connection.endpoint {
            return "\(host)"
        }
        return "unknown"
    }
    
    private func extractPortFromConnection(_ connection: NWConnection) -> Int {
        if case .hostPort(_, let port) = connection.endpoint {
            return Int(port.rawValue)
        }
        return 0
    }
    
    deinit {
        // Listener cleanup will be handled by ARC when the instance is deallocated
        // No need for explicit async cleanup in deinit
    }
}

// MARK: - OSC Message Parsing

struct OSCMessage {
    let address: String
    let arguments: [Any]
}

enum OSCParseError: Error {
    case invalidFormat
    case invalidAddress
    case invalidTypeTag
    case invalidArgument
}

private func parseOSCMessage(_ data: Data) throws -> OSCMessage {
    var offset = 0
    
    // 1. Parse address pattern
    guard let address = parseOSCString(data, offset: &offset) else {
        throw OSCParseError.invalidAddress
    }
    
    // 2. Parse type tag string
    guard let typeTag = parseOSCString(data, offset: &offset),
          typeTag.hasPrefix(",") else {
        throw OSCParseError.invalidTypeTag
    }
    
    // 3. Parse arguments based on type tags
    var arguments: [Any] = []
    let tags = String(typeTag.dropFirst()) // Remove the comma
    
    for tag in tags {
        switch tag {
        case "f": // Float32
            guard let floatValue = parseOSCFloat(data, offset: &offset) else {
                throw OSCParseError.invalidArgument
            }
            arguments.append(floatValue)
            
        case "s": // String
            guard let stringValue = parseOSCString(data, offset: &offset) else {
                throw OSCParseError.invalidArgument
            }
            arguments.append(stringValue)
            
        case "i": // Int32
            guard let intValue = parseOSCInt32(data, offset: &offset) else {
                throw OSCParseError.invalidArgument
            }
            arguments.append(intValue)
            
        default:
            throw OSCParseError.invalidArgument
        }
    }
    
    return OSCMessage(address: address, arguments: arguments)
}

private func parseOSCString(_ data: Data, offset: inout Int) -> String? {
    guard offset < data.count else { return nil }
    
    // Find null terminator
    var end = offset
    while end < data.count && data[end] != 0 {
        end += 1
    }
    
    guard end < data.count else { return nil }
    
    let stringData = data.subdata(in: offset..<end)
    let result = String(data: stringData, encoding: .utf8)
    
    // Move past string and padding to 4-byte boundary
    offset = ((end + 4) / 4) * 4
    
    return result
}

private func parseOSCFloat(_ data: Data, offset: inout Int) -> Float? {
    guard offset + 4 <= data.count else { return nil }
    
    let bytes = data.subdata(in: offset..<(offset + 4))
    let value = bytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    offset += 4
    
    return Float(bitPattern: value)
}

private func parseOSCInt32(_ data: Data, offset: inout Int) -> Int32? {
    guard offset + 4 <= data.count else { return nil }
    
    let bytes = data.subdata(in: offset..<(offset + 4))
    let value = bytes.withUnsafeBytes { $0.load(as: Int32.self).bigEndian }
    offset += 4
    
    return value
}
