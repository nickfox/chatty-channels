// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/OSCService.swift

import Foundation
import SwiftUI
import Combine
import Network

/// A structure representing a chat request to be processed by AI services.
///
/// This structure encapsulates the data needed to identify and process a chat request
/// from a specific plugin instance.
///
/// ## Example
/// ```swift
/// let request = ChatRequest(instanceID: "plugin-1", userMessage: "reduce gain by 3dB")
/// oscService.chatRequestPublisher = request
/// ```
public struct ChatRequest {
    /// The unique identifier for the plugin instance making the request.
    ///
    /// This ID allows the system to route responses back to the correct plugin instance.
    public let instanceID: String
    
    /// The text message from the user to be processed.
    ///
    /// This is the actual content of the chat request that will be sent to the AI service.
    public let userMessage: String
}

/// Service for sending Open Sound Control (OSC) messages to audio applications.
///
/// OSCService provides a high-performance, low-latency channel for communication with
/// audio plugins and applications that support the OSC protocol. It handles connection
/// management, message formatting, and efficient packet transmission.
///
/// ## Features
/// - Optimized for real-time audio parameter control
/// - Supports multiple message types (RMS levels, parameter changes, text responses)
/// - Connection pooling and packet caching for maximum performance
/// - Thread-safe design with proper synchronization
///
/// ## Usage Example
/// ```swift
/// let oscService = OSCService()
///
/// // Send a parameter change
/// oscService.sendParameterChange(parameterID: "GAIN", value: -3.0)
///
/// // Send a response message
/// oscService.sendResponse(message: "Gain reduced by 3dB")
///
/// // Send RMS level update (for metering)
/// oscService.sendRMS(0.5)
/// ```
///
/// - Note: All OSC messages are sent to localhost:9000 by default, which is the
///   standard port for most audio applications that support OSC.
public final class OSCService: ObservableObject {
    // MARK: - Dependencies
    private var levelMeterService: LevelMeterService?
    private let portManager = PortManager()

    // MARK: - Unidentified RMS Cache
    private var unidentifiedRMSCache: [String: (rms: Float, senderIP: String, senderPort: Int, timestamp: Date)] = [:]
    private let unidentifiedRMSCacheLock = NSLock()
    private let cacheExpiryDuration: TimeInterval = 5.0 // 5 seconds for cache entries

    // MARK: - T-05 OSC Reliability Enhancements
    
    private struct MessageInfo {
        let message: Data
        let retryCount: Int
        let timestamp: Date
        let endpoint: NWEndpoint.Host?
        let port: NWEndpoint.Port?
    }
    
    // Keep track of outgoing messages and their sequence numbers
    private var outgoingSequenceNumbers = [String: UInt32]() // Key: address pattern
    private var pendingMessages = [String: MessageInfo]() // Key: msgID
    private var retryTimer: Timer?
    private let pendingMessagesLock = NSLock()
    private let maxRetries = 3
    private let retryInterval: TimeInterval = 0.5 // seconds

    /// Publisher for chat requests from audio plugins.
    ///
    /// The main mechanism for receiving chat requests from plugins.
    /// Set this property to trigger the processing pipeline.
    @Published public var chatRequestPublisher: ChatRequest? = nil
    
    /// Publisher for observing chat requests.
    ///
    /// This property allows other components to subscribe to chat request events.
    /// Use this in combination with Combine's sink() method to process requests.
    public var chatRequestPublisherPublisher: Published<ChatRequest?>.Publisher {
        $chatRequestPublisher
    }
    
    /// Sets a new chat request to be processed by listeners.
    ///
    /// Use this method to submit a new chat request for processing by subscribers.
    /// This is the main entry point for plugin messages into the AI processing pipeline.
    ///
    /// - Parameters:
    ///   - instanceID: The unique identifier for the plugin instance.
    ///   - message: The text message from the user.
    public func submitChatRequest(instanceID: String, message: String) {
        // Validate input to prevent empty messages from entering the pipeline
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[OSCService] Ignored empty message submission")
            return
        }
        
        print("[OSCService] Submitting chat request: id=\(instanceID), message='\(message)'")
        self.chatRequestPublisher = ChatRequest(instanceID: instanceID, userMessage: message)
    }
    
    // MARK: - Connection Management
    
    /// Dedicated high-priority queue for OSC operations.
    ///
    /// This queue ensures that OSC messages are processed with minimal latency,
    /// which is critical for real-time audio parameter control.
    private let oscSendQueue = DispatchQueue(label: "com.chatty.osc.send", qos: .userInteractive)
    
    /// Shared connection for RMS messages.
    ///
    /// A persistent network connection that's reused for frequent RMS updates
    /// to avoid the overhead of creating new connections.
    private var sharedConnection: NWConnection?
    
    /// Lock for thread-safe access to the shared connection.
    private let connectionLock = NSLock()
    
    /// Pre-allocated packet cache for frequent RMS values.
    ///
    /// Caches OSC packets for commonly used RMS values to avoid
    /// repeated packet construction overhead.
    private var rmsPacketCache = [Float: Data]()
    
    /// Lock for thread-safe access to the packet cache.
    private let cacheLock = NSLock()
    
    /// Creates or retrieves the shared OSC connection to localhost:9000.
    ///
    /// This method implements a connection pooling pattern to efficiently
    /// manage network resources. It either returns an existing connection
    /// or creates a new one if needed.
    ///
    /// - Returns: A network connection to the local OSC endpoint.
    private func getOrCreateConnection() -> NWConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        
        if sharedConnection == nil || sharedConnection?.state == .cancelled {
            // Create optimized network parameters
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true
            
            // Create endpoint and connection
            let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 9000)
            let conn = NWConnection(to: endpoint, using: params)
            conn.start(queue: oscSendQueue)
            sharedConnection = conn
            print("[OSCService] Created new shared OSC connection to localhost:9000")
        }
        return sharedConnection!
    }
    
    /// Gets a cached packet or creates a new one for the given RMS value.
    ///
    /// This method implements a caching strategy to avoid repeated encoding
    /// of common RMS values, improving performance for high-frequency metering updates.
    ///
    /// - Parameter rms: The RMS (Root Mean Square) value to encode.
    /// - Returns: An OSC packet as Data, ready for transmission.
    private func getCachedOrCreatePacket(for rms: Float) -> Data {
        // Round to 2 decimal places to increase cache hits
        let roundedRMS = round(rms * 100) / 100
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        if let cached = rmsPacketCache[roundedRMS] {
            return cached
        }
        
        // Create and cache the packet
        let packet = OSCService.encodeOSC(address: "/aiplayer/rms", argument: roundedRMS)
        print("[OSCService] Cache miss. Created new OSC packet for /aiplayer/rms with value: \(roundedRMS)")
        
        // Limit cache size to prevent memory growth
        if rmsPacketCache.count > 100 {
            rmsPacketCache.removeAll(keepingCapacity: true)
        }
        
        rmsPacketCache[roundedRMS] = packet
        return packet
    }

    // MARK: - Initialization
    // Updated init to ensure LevelMeterService can be injected.
    // The @StateObject in ChattyChannelsApp will call this.
    public init(levelMeterService: LevelMeterService? = nil) { // Keep optional for flexibility if used elsewhere without it initially
        self.levelMeterService = levelMeterService
        print("[OSCService] Initialized. LevelMeterService is \(levelMeterService == nil ? "nil" : "set").")
        
        // Don't start the retry timer here - let it start when needed
        print("[OSCService] Message retry handler initialized with interval: \(retryInterval)s, max retries: \(maxRetries)")
    }
    
    // MARK: - Public API
    
    // Method to update the LevelMeterService dependency if it's not set at init
    public func setLevelMeterService(_ service: LevelMeterService) {
        self.levelMeterService = service
    }

    /// Sends an OSC message with address "/aiplayer/rms" and a single float argument.
    ///
    /// This method is optimized for high-frequency transmission of audio level information,
    /// using packet caching and direct UDP connections for minimal latency.
    ///
    /// - Parameter rms: The RMS (Root Mean Square) level value between 0.0 and 1.0.
    ///
    /// - Note: This method creates a new connection for each call to avoid potential
    ///   latency issues that were observed with connection reuse.
    public func sendRMS(_ rms: Float) {
        // Get the packet from cache or create a new one
        let packet = getCachedOrCreatePacket(for: rms)
        
        // Create a direct UDP connection for minimal overhead
        let endpoint = NWEndpoint.hostPort(host: .init("127.0.0.1"), port: 9000)
        let connection = NWConnection(to: endpoint, using: .udp)
        
        // Start and send immediately for minimal latency
        connection.start(queue: DispatchQueue.global(qos: .userInteractive))
        
        // Send without waiting for a response
        connection.send(content: packet, completion: .contentProcessed { _ in
            // Cancel connection when done - reused connections were causing latency issues
            connection.cancel()
        })
    }

    // MARK: - Port Assignment Methods
    
    /// Handles port assignment request from a plugin
    /// - Parameters:
    ///   - tempID: The temporary instance ID from the plugin
    ///   - preferredPort: Optional preferred port number
    ///   - senderIP: IP address of the requesting plugin
    ///   - senderPort: Port the plugin sent from (for response)
    public func handlePortRequest(tempID: String, preferredPort: Int32?, senderIP: String, senderPort: Int) {
        print("[OSCService] Received port request from plugin \(tempID) at \(senderIP):\(senderPort)")
        
        let preferred = preferredPort.flatMap { $0 >= 0 ? UInt16($0) : nil }
        
        if let assignedPort = portManager.assignPort(to: tempID, preferred: preferred) {
            // Send successful assignment
            sendPortAssignment(to: tempID, port: Int32(assignedPort), status: "assigned", 
                             targetIP: senderIP, targetPort: senderPort)
        } else {
            // No ports available
            sendPortAssignment(to: tempID, port: -1, status: "error", 
                             targetIP: senderIP, targetPort: senderPort)
        }
    }
    
    /// Sends port assignment response to a plugin
    private func sendPortAssignment(to tempID: String, port: Int32, status: String, 
                                   targetIP: String, targetPort: Int) {
        let packet = OSCService.encodeOSC(
            address: "/aiplayer/port_assignment",
            arguments: [tempID, port, status]
        )
        
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(targetPort)) else {
            print("[OSCService] Invalid target port for port assignment: \(targetPort)")
            return
        }
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetIP), port: nwPort)
        let connection = NWConnection(to: endpoint, using: .udp)
        
        connection.start(queue: oscSendQueue)
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("[OSCService] Error sending port assignment: \(error)")
            } else {
                print("[OSCService] Sent port assignment to \(tempID): port \(port), status: \(status)")
            }
            connection.cancel()
        })
    }
    
    /// Handles port confirmation from a plugin
    /// - Parameters:
    ///   - tempID: The temporary instance ID from the plugin
    ///   - port: The port the plugin bound to
    ///   - status: Success/failure status
    public func handlePortConfirmation(tempID: String, port: Int32, status: String) {
        print("[OSCService] Received port confirmation from \(tempID): port \(port), status: \(status)")
        
        if status == "bound" {
            let success = portManager.confirmBinding(tempID: tempID, port: UInt16(port))
            if !success {
                print("[OSCService] WARNING: Port confirmation failed for \(tempID)")
            }
        } else {
            // Plugin failed to bind, release the port
            portManager.releasePort(UInt16(port))
            print("[OSCService] Released port \(port) due to binding failure")
        }
    }
    
    /// Handles UUID assignment confirmation from a plugin
    /// - Parameters:
    ///   - sequenceNumber: The sequence number from the original message
    ///   - tempID: The temporary instance ID from the plugin
    ///   - logicTrackUUID: The Logic Pro Track UUID that was assigned
    public func handleUUIDAssignmentConfirmation(sequenceNumber: UInt32, tempID: String, logicTrackUUID: String) {
        print("[OSCService] Received UUID assignment confirmation: seq=\(sequenceNumber), tempID=\(tempID), logicID=\(logicTrackUUID)")
        
        // Generate the message ID to find the pending message
        let msgID = generateMessageID(addressPattern: "/aiplayer/track_uuid_assignment", seqNum: sequenceNumber)
        
        pendingMessagesLock.lock()
        if pendingMessages[msgID] != nil {
            pendingMessages.removeValue(forKey: msgID)
            print("[OSCService] UUID assignment confirmed and removed from retry queue: \(msgID)")
            
            // If no more pending messages, stop timer
            if pendingMessages.isEmpty {
                retryTimer?.invalidate()
                retryTimer = nil
                print("[OSCService] All UUID assignments confirmed, retry timer stopped")
            }
        } else {
            print("[OSCService] WARNING: Received confirmation for unknown message ID: \(msgID)")
        }
        pendingMessagesLock.unlock()
    }
    
    /// Handles UUID assignment confirmation without sequence number (legacy format)
    /// - Parameters:
    ///   - tempID: The temporary instance ID from the plugin
    ///   - logicTrackUUID: The Logic Pro Track UUID that was assigned
    public func handleUUIDAssignmentConfirmationLegacy(tempID: String, logicTrackUUID: String) {
        print("[OSCService] Received UUID assignment confirmation (legacy): tempID=\(tempID), logicID=\(logicTrackUUID)")
        
        // Since we don't have the sequence number, we need to find the message by content
        // This is less ideal but should work for the legacy case
        pendingMessagesLock.lock()
        
        // Find any pending UUID assignment message that matches this tempID
        var foundKey: String?
        for (msgID, _) in pendingMessages {
            if msgID.hasPrefix("/aiplayer/track_uuid_assignment-") {
                // Found a UUID assignment message, assume this is the confirmation for it
                foundKey = msgID
                break
            }
        }
        
        if let key = foundKey {
            pendingMessages.removeValue(forKey: key)
            print("[OSCService] UUID assignment confirmed (legacy) and removed from retry queue: \(key)")
            
            // If no more pending messages, stop timer
            if pendingMessages.isEmpty {
                retryTimer?.invalidate()
                retryTimer = nil
                print("[OSCService] All UUID assignments confirmed, retry timer stopped")
            }
        } else {
            print("[OSCService] WARNING: Received legacy confirmation but no pending UUID assignment found")
        }
        
        pendingMessagesLock.unlock()
    }
    
    /// Gets the port assigned to a specific plugin
    public func getPluginPort(_ tempID: String) -> UInt16? {
        return portManager.getPort(for: tempID)
    }
    
    /// Gets all current port assignments
    public func getAllPortAssignments() -> [String: UInt16] {
        return portManager.getAllAssignments()
    }

    // MARK: - OSC Message Processing (called by an external OSC listener)

    /// Processes an incoming unidentified RMS message.
    /// - Parameters:
    ///   - tempID: The temporary instance ID from the plugin.
    ///   - rmsValue: The RMS value.
    ///   - senderIP: The IP address of the sending plugin.
    ///   - senderPort: The port of the sending plugin.
    public func processUnidentifiedRMS(tempID: String, rmsValue: Float, senderIP: String, senderPort: Int) {
        unidentifiedRMSCacheLock.lock()
        unidentifiedRMSCache[tempID] = (rms: rmsValue, senderIP: senderIP, senderPort: senderPort, timestamp: Date())
        unidentifiedRMSCacheLock.unlock()
        // Removed verbose logging - these messages come in continuously
    }

    /// Processes an incoming identified RMS message.
    /// - Parameters:
    ///   - logicTrackUUID: The official Logic Pro Track UUID.
    ///   - rmsValue: The RMS value.
    public func processIdentifiedRMS(logicTrackUUID: String, rmsValue: Float) {
        guard let levelMeterService = self.levelMeterService else {
            print("[OSCService] Error: LevelMeterService not set. Cannot process identified RMS for \(logicTrackUUID).")
            return
        }
        
        // Dispatch to MainActor as LevelMeterService.updateLevel is @MainActor isolated
        Task { @MainActor in
            levelMeterService.updateLevel(logicTrackUUID: logicTrackUUID, rmsValue: rmsValue)
            // Removed verbose logging - these messages come in continuously
        }
    }
    
    /// Processes an incoming port-based RMS message.
    /// - Parameters:
    ///   - tempID: The temporary instance ID from the plugin.
    ///   - port: The port number extracted from the address.
    ///   - rmsValue: The RMS value.
    public func processPortBasedRMS(tempID: String, port: UInt16, rmsValue: Float) {
        // First check if we have a track mapping for this port
        if let trackMapping = getTrackMappingForPort(port) {
            // We have a mapping, process as identified RMS
            processIdentifiedRMS(logicTrackUUID: trackMapping.logicTrackUUID, rmsValue: rmsValue)
        } else {
            // No mapping yet, store in cache similar to unidentified
            // This allows calibration to still work with port-based identification
            unidentifiedRMSCacheLock.lock()
            unidentifiedRMSCache[tempID] = (rms: rmsValue, senderIP: "127.0.0.1", senderPort: Int(port), timestamp: Date())
            unidentifiedRMSCacheLock.unlock()
        }
    }
    
    /// Gets track mapping for a given port (placeholder - needs integration with track mapping system)
    private func getTrackMappingForPort(_ port: UInt16) -> (logicTrackUUID: String, trackName: String)? {
        // TODO: Integrate with track mapping database
        // For now, return nil to treat all as unidentified during calibration
        return nil
    }

    // MARK: - Cache Management for Calibration

    /// Retrieves current, non-expired unidentified RMS data.
    public func getUnidentifiedRMSData() -> [String: (rms: Float, senderIP: String, senderPort: Int)] {
        unidentifiedRMSCacheLock.lock()
        defer { unidentifiedRMSCacheLock.unlock() }

        let now = Date()
        var validCache: [String: (rms: Float, senderIP: String, senderPort: Int)] = [:]
        for (key, value) in unidentifiedRMSCache {
            if now.timeIntervalSince(value.timestamp) < cacheExpiryDuration {
                validCache[key] = (rms: value.rms, senderIP: value.senderIP, senderPort: value.senderPort)
            }
        }
        // Clean out expired entries from the main cache
        unidentifiedRMSCache = unidentifiedRMSCache.filter { now.timeIntervalSince($0.value.timestamp) < cacheExpiryDuration }
        return validCache
    }

    /// Clears the entire unidentified RMS cache.
    public func clearUnidentifiedRMSCache() {
        unidentifiedRMSCacheLock.lock()
        unidentifiedRMSCache.removeAll()
        unidentifiedRMSCacheLock.unlock()
        print("[OSCService] Unidentified RMS cache cleared.")
    }
    
    /// Clears a specific entry from the unidentified RMS cache.
    public func clearSpecificUnidentifiedRMS(tempID: String) {
        unidentifiedRMSCacheLock.lock()
        unidentifiedRMSCache.removeValue(forKey: tempID)
        unidentifiedRMSCacheLock.unlock()
        print("[OSCService] Cleared specific RMS entry for tempID: \(tempID)")
    }

    // MARK: - OSC Sending Methods
    
    /// Sends an OSC message to change a parameter's value.
    ///
    /// This method transmits a parameter change command to the audio plugin,
    /// allowing for direct control of audio parameters like gain, EQ, etc.
    ///
    /// - Parameters:
    ///   - parameterID: The identifier of the parameter to change (e.g., "GAIN").
    ///   - value: The new value to set for the parameter.
    ///
    /// - Note: Uses the address pattern "/aiplayer/parameter/{parameterID}" and
    ///   sends the value as a float argument.
    public func sendParameterChange(parameterID: String, value: Float) {
        print("[OSCService] Sending parameter change: id=\(parameterID), value=\(value)")
        
        // Create the OSC address path for the parameter
        let oscAddress = "/aiplayer/set_parameter" // Corrected address based on plugin
        
        // Create OSC packet with two arguments: String (paramID), Float (value)
        let packet = OSCService.encodeOSC(address: oscAddress, arguments: [parameterID, value])
        
        // Use the shared connection for parameter changes (target port 9000 for plugin receiver)
        let connection = getOrCreateConnection() // This targets localhost:9000
        
        // Send the packet
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("[OSCService] Error sending parameter change: \(error)")
            }
        })
    }
    
    /// Sends an OSC response message.
    ///
    /// This method transmits a text response back to the plugin to be displayed
    /// in the user interface. It handles the proper OSC formatting for string arguments.
    ///
    /// - Parameter message: The text message to send.
    ///
    /// - Note: Uses the address pattern "/aiplayer/response" and sends the message
    ///   as a string argument.
    public func sendResponse(message: String) {
        print("[OSCService] Sending response: '\(message)'")
        
        let oscAddress = "/aiplayer/chat/response" // Corrected address based on plugin
        let packet = OSCService.encodeOSC(address: oscAddress, arguments: [message])

        // Create a new connection for this response, as target port might vary or for clarity
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 9000) // Plugin listens on 9000
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: oscSendQueue)
        
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("[OSCService] Error sending response: \(error)")
            }
            // Cancel the connection when done
            connection.cancel()
        })
    }

    /// Sends a UUID assignment message to a specific plugin instance with retry.
    /// - Parameters:
    ///   - ip: The IP address of the plugin.
    ///   - port: The port the plugin is listening on for this message.
    ///   - tempInstanceID: The temporary ID of the plugin to assign.
    ///   - logicTrackUUID: The Logic Pro Track UUID to assign.
    public func sendUUIDAssignment(toPluginIP ip: String, port: Int, tempInstanceID: String, logicTrackUUID: String) {
        let oscAddress = "/aiplayer/track_uuid_assignment"
        let arguments: [Any] = [tempInstanceID, logicTrackUUID]
        
        // Use the retry mechanism for this critical message
        print("[OSCService] Sending UUID assignment with retry: tempID=\(tempInstanceID) to logicID=\(logicTrackUUID) @ \(ip):\(port)")
        
        guard let targetPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            print("[OSCService] Error: Invalid port for sendUUIDAssignment: \(port)")
            return
        }
        
        // Use our improved sendWithRetry method with custom endpoint
        let host = NWEndpoint.Host(ip)
        sendWithRetry(address: oscAddress, arguments: arguments, critical: true, customEndpoint: host, customPort: targetPort)
    }
    
    // MARK: - T-05 OSC Retry Mechanism Implementation
    
    /// Generates a new sequence number for an address pattern
    /// - Parameter addressPattern: The OSC address pattern
    /// - Returns: The next sequence number
    private func nextSequenceNumber(for addressPattern: String) -> UInt32 {
        let currentNum = outgoingSequenceNumbers[addressPattern] ?? 0
        let nextNum = currentNum + 1
        outgoingSequenceNumbers[addressPattern] = nextNum
        return nextNum
    }
    
    /// Generates a unique message ID for tracking retries
    /// - Parameters:
    ///   - addressPattern: The OSC address pattern
    ///   - seqNum: The sequence number
    /// - Returns: A unique message ID
    private func generateMessageID(addressPattern: String, seqNum: UInt32) -> String {
        return "\(addressPattern)-\(seqNum)"
    }
    
    /// Starts the retry timer if not already running
    private func startRetryTimerIfNeeded() {
        if retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkPendingMessages()
            }
        }
    }
    
    /// Checks pending messages for retry or expiration
    private func checkPendingMessages() {
        pendingMessagesLock.lock()
        defer { pendingMessagesLock.unlock() }
        
        let now = Date()
        var messagesToRetry = [(String, MessageInfo)]() // (msgID, messageInfo)
        var messagesToRemove = [String]() // msgIDs
        
        for (msgID, messageInfo) in pendingMessages {
            let elapsedTime = now.timeIntervalSince(messageInfo.timestamp)
            
            if elapsedTime > retryInterval {
                if messageInfo.retryCount < maxRetries {
                    // Schedule for retry
                    messagesToRetry.append((msgID, messageInfo))
                    // Update retry count and timestamp
                    pendingMessages[msgID] = MessageInfo(
                        message: messageInfo.message,
                        retryCount: messageInfo.retryCount + 1,
                        timestamp: now,
                        endpoint: messageInfo.endpoint,
                        port: messageInfo.port
                    )
                    print("[OSCService] Retrying message \(msgID) (attempt \(messageInfo.retryCount + 1)/\(maxRetries))")
                } else {
                    // Max retries reached, remove message
                    messagesToRemove.append(msgID)
                    print("[OSCService] Message \(msgID) failed after \(maxRetries) retry attempts")
                }
            }
        }
        
        // Remove expired messages
        for msgID in messagesToRemove {
            pendingMessages.removeValue(forKey: msgID)
        }
        
        // If no more pending messages, stop timer
        if pendingMessages.isEmpty {
            retryTimer?.invalidate()
            retryTimer = nil
        }
        
        // Unlock before sending retries to avoid potential deadlock
        pendingMessagesLock.unlock()
        
        // Retry messages
        for (_, messageInfo) in messagesToRetry {
            sendRawOSCPacket(messageInfo.message, customEndpoint: messageInfo.endpoint, customPort: messageInfo.port)
        }
        
        // Relock for consistency with defer
        pendingMessagesLock.lock()
    }
    
    /// Sends a raw OSC packet with no tracking
    /// - Parameters:
    ///   - packetData: The OSC packet data
    ///   - customEndpoint: Optional custom endpoint, defaults to localhost:9000
    private func sendRawOSCPacket(_ packetData: Data, customEndpoint: NWEndpoint.Host? = nil, customPort: NWEndpoint.Port? = nil) {
        let host = customEndpoint ?? .init("127.0.0.1")
        let port = customPort ?? 9000
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: oscSendQueue)
        
        connection.send(content: packetData, completion: .contentProcessed { error in
            if let error = error {
                print("[OSCService] Error sending OSC packet: \(error)")
            }
            connection.cancel()
        })
    }
    
    /// Sends an OSC message with retry for critical messages
    /// - Parameters:
    ///   - address: The OSC address pattern
    ///   - arguments: The OSC arguments
    ///   - critical: Whether this is a critical message requiring retry
    ///   - customEndpoint: Optional custom endpoint
    ///   - customPort: Optional custom port
    public func sendWithRetry(address: String, arguments: [Any], critical: Bool = true, customEndpoint: NWEndpoint.Host? = nil, customPort: NWEndpoint.Port? = nil) {
        if !critical {
            // Non-critical message, just send once without tracking
            let packet = OSCService.encodeOSC(address: address, arguments: arguments)
            sendRawOSCPacket(packet, customEndpoint: customEndpoint, customPort: customPort)
            return
        }
        
        // Critical message, add sequence number and track for retries
        let seqNum = nextSequenceNumber(for: address)
        let msgArgs = [seqNum] + arguments
        let packet = OSCService.encodeOSC(address: address, arguments: msgArgs)
        let msgID = generateMessageID(addressPattern: address, seqNum: seqNum)
        
        // Add to pending messages
        pendingMessagesLock.lock()
        pendingMessages[msgID] = MessageInfo(
            message: packet,
            retryCount: 0,
            timestamp: Date(),
            endpoint: customEndpoint,
            port: customPort
        )
        pendingMessagesLock.unlock()
        
        // Start retry timer
        startRetryTimerIfNeeded()
        
        // Send initial message
        sendRawOSCPacket(packet, customEndpoint: customEndpoint, customPort: customPort)
        print("[OSCService] Sent critical message: \(address) with sequence \(seqNum)")
    }
    
    // MARK: - Private OSC Encoding Helpers
    
    /// Encodes a minimal OSC packet with a single Float32 argument. (Legacy, kept for compatibility if needed by sendRMS)
    ///
    /// This is an optimized implementation that minimizes memory allocations and copying
    /// to ensure the best possible performance for real-time audio applications.
    ///
    /// - Parameters:
    ///   - address: The OSC address pattern (e.g., "/aiplayer/parameter/GAIN").
    ///   - argument: The float value to encode as the argument.
    ///
    /// - Returns: A Data object containing the complete OSC packet.
    ///
    /// - Note: This implementation follows the OSC 1.0 specification for binary message format:
    ///   1. OSC Address Pattern (null-terminated, padded to 4-byte boundary)
    ///   2. OSC Type Tag String (starting with ',', null-terminated, padded)
    ///   3. OSC Arguments (each padded to 4-byte boundary)
    private static func encodeOSC(address: String, argument: Float) -> Data {
        return encodeOSC(address: address, arguments: [argument])
    }

    /// Encodes an OSC packet with an address pattern and an array of arguments.
    /// Supports Float32 and String arguments.
    public static func encodeOSC(address: String, arguments: [Any]) -> Data {
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
            if arg is Float || arg is Double { // Treat Double as Float for OSC
                typeTagString.append("f")
            } else if arg is String {
                typeTagString.append("s")
            } else if arg is Int || arg is Int32 || arg is UInt32 { // Handle Int32 explicitly
                 typeTagString.append("i")
            } else {
                print("[OSCService] Error: Unsupported argument type for OSC encoding: \(type(of: arg))")
                // Potentially return empty Data or throw an error
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
            } else if let doubleVal = arg as? Double { // Convert Double to Float
                var bigEndianFloat = Float(doubleVal).bitPattern.bigEndian
                withUnsafeBytes(of: &bigEndianFloat) { packet.append(contentsOf: $0) }
            } else if let stringVal = arg as? String {
                var stringData = stringVal.data(using: .utf8) ?? Data()
                stringData.append(0) // Null terminator
                while stringData.count % 4 != 0 {
                    stringData.append(0) // Pad to 4-byte boundary
                }
                packet.append(stringData)
            } else if let int32Val = arg as? Int32 { // Handle Int32 directly
                var bigEndianInt32 = int32Val.bigEndian
                withUnsafeBytes(of: &bigEndianInt32) { packet.append(contentsOf: $0) }
            } else if let intVal = arg as? Int {
                var bigEndianInt = Int32(intVal).bigEndian // Convert Int to Int32
                withUnsafeBytes(of: &bigEndianInt) { packet.append(contentsOf: $0) }
            } else if let uintVal = arg as? UInt32 {
                var bigEndianUInt = uintVal.bigEndian
                withUnsafeBytes(of: &bigEndianUInt) { packet.append(contentsOf: $0) }
            }
        }
        return packet
    }
    
    // MARK: - RMS Query System for Calibration
    
    /// Current query responses for calibration
    private var currentQueryResponses: [String: (tempID: String, rms: Float)] = [:]
    private var currentQueryID: String?
    private let queryLock = NSLock()
    
    /// Broadcasts an RMS query to all possible plugin ports
    /// - Parameter queryID: Unique identifier for this query session
    public func broadcastRMSQuery(queryID: String) {
        queryLock.lock()
        defer { queryLock.unlock() }
        
        currentQueryID = queryID
        currentQueryResponses.removeAll()
        
        // Broadcast to plugin receiver ports 9000-9010
        for port in 9000...9010 {
            sendQueryToPort(queryID: queryID, port: UInt16(port))
        }
        
        print("[OSCService] Broadcasted RMS query \(queryID) to ports 9000-9010")
    }
    
    /// Sends query to a specific port
    private func sendQueryToPort(queryID: String, port: UInt16) {
        let packet = OSCService.encodeOSC(address: "/aiplayer/query_rms", arguments: [queryID])
        
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let connection = NWConnection(to: endpoint, using: .udp)
        
        connection.start(queue: oscSendQueue)
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("[OSCService] Failed to send query to port \(port): \(error)")
            }
            connection.cancel()
        })
    }
    
    /// Processes RMS response from plugins
    public func processRMSResponse(queryID: String, tempInstanceID: String, currentRMS: Float) {
        queryLock.lock()
        defer { queryLock.unlock() }
        
        guard queryID == currentQueryID else {
            print("[OSCService] Ignoring stale RMS response for query \(queryID)")
            return
        }
        
        currentQueryResponses[tempInstanceID] = (tempID: tempInstanceID, rms: currentRMS)
        print("[OSCService] Received RMS response: \(tempInstanceID) = \(currentRMS)")
    }
    
    /// Gets current query responses (for calibration)
    public func getCurrentQueryResponses() -> [String: Float] {
        queryLock.lock()
        defer { queryLock.unlock() }
        
        return currentQueryResponses.mapValues { $0.rms }
    }
    
    /// Clears current query session
    public func clearCurrentQuery() {
        queryLock.lock()
        defer { queryLock.unlock() }
        
        currentQueryID = nil
        currentQueryResponses.removeAll()
    }
    
    // MARK: - Oscillator Control Methods for Calibration
    
    /// Starts tone generation on all plugins with specified frequency and amplitude
    public func startToneGeneration(frequency: Float, amplitude: Float) async throws {
        let packet = OSCService.encodeOSC(address: "/aiplayer/start_tone", arguments: [frequency, amplitude])
        
        // Broadcast to all possible plugin ports
        for port in 9000...9010 {
            let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
            let connection = NWConnection(to: endpoint, using: .udp)
            
            connection.start(queue: oscSendQueue)
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error = error {
                    print("[OSCService] Failed to send start_tone to port \(port): \(error)")
                } else {
                    print("[OSCService] Sent start_tone \(frequency)Hz @ \(amplitude)dB to port \(port)")
                }
                connection.cancel()
            })
        }
    }
    
    /// Stops tone generation on all plugins
    public func stopAllTones() async throws {
        let packet = OSCService.encodeOSC(address: "/aiplayer/stop_tone", arguments: [])
        
        // Broadcast to all possible plugin ports
        for port in 9000...9010 {
            let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
            let connection = NWConnection(to: endpoint, using: .udp)
            
            connection.start(queue: oscSendQueue)
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error = error {
                    print("[OSCService] Failed to send stop_tone to port \(port): \(error)")
                } else {
                    print("[OSCService] Sent stop_tone to port \(port)")
                }
                connection.cancel()
            })
        }
    }
    
    /// Queries tone status from all plugins
    public func queryToneStatus() async throws {
        let packet = OSCService.encodeOSC(address: "/aiplayer/tone_status", arguments: [])
        
        // Broadcast to all possible plugin ports
        for port in 9000...9010 {
            let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
            let connection = NWConnection(to: endpoint, using: .udp)
            
            connection.start(queue: oscSendQueue)
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error = error {
                    print("[OSCService] Failed to send tone_status query to port \(port): \(error)")
                }
                connection.cancel()
            })
        }
    }
    
    /// Cleans up resources when the service is deallocated.
    ///
    /// Ensures that network connections are properly closed to prevent resource leaks.
    deinit {
        retryTimer?.invalidate()
        retryTimer = nil
        
        connectionLock.lock()
        sharedConnection?.cancel()
        sharedConnection = nil
        connectionLock.unlock()
    }
}
