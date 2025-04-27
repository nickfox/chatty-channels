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
            print("OSCService: Ignored empty message submission")
            return
        }
        
        print("OSCService: Submitting chat request from ID=\(instanceID): '\(message)'")
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
        
        // Limit cache size to prevent memory growth
        if rmsPacketCache.count > 100 {
            rmsPacketCache.removeAll(keepingCapacity: true)
        }
        
        rmsPacketCache[roundedRMS] = packet
        return packet
    }
    
    // MARK: - Public API
    
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
        print("OSCService: Sending parameter change for \(parameterID) with value \(value)")
        
        // Create the OSC address path for the parameter
        let oscAddress = "/aiplayer/parameter/\(parameterID)"
        
        // Create OSC packet
        let packet = OSCService.encodeOSC(address: oscAddress, argument: value)
        
        // Use the shared connection for parameter changes
        let connection = getOrCreateConnection()
        
        // Send the packet
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("Error sending parameter change: \(error)")
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
        print("OSCService: Sending response: \(message)")
        
        // Create a Data representation of the string message
        guard let messageData = message.data(using: .utf8) else {
            print("Error: Could not convert message to data")
            return
        }
        
        // Create a network endpoint
        let endpoint = NWEndpoint.hostPort(host: .init("127.0.0.1"), port: 9000)
        let connection = NWConnection(to: endpoint, using: .udp)
        
        // Start the connection
        connection.start(queue: DispatchQueue.global(qos: .userInteractive))
        
        // Prepare the OSC message format
        // OSC messages with strings have a specific format:
        // 1. The address string, null-terminated, padded to a multiple of 4 bytes
        // 2. The type tag string, starting with ',', followed by 's' for string, null-terminated, padded
        // 3. The string argument, null-terminated, padded to a multiple of 4 bytes
        
        // 1. Address part: "/aiplayer/response"
        let address = "/aiplayer/response"
        let addressData = address.data(using: .utf8)!
        let addressPadding = (4 - ((addressData.count + 1) % 4)) % 4 // +1 for null terminator
        
        // 2. Type tag part: ",s"
        let typeTag = ",s"
        let typeTagData = typeTag.data(using: .utf8)!
        let typeTagPadding = (4 - ((typeTagData.count + 1) % 4)) % 4 // +1 for null terminator
        
        // 3. String argument part: the actual message
        let stringPadding = (4 - ((messageData.count + 1) % 4)) % 4 // +1 for null terminator
        
        // Compose the full OSC message
        var oscMessage = Data()
        
        // Add address with padding
        oscMessage.append(addressData)
        oscMessage.append(0) // null terminator
        for _ in 0..<addressPadding {
            oscMessage.append(0)
        }
        
        // Add type tag with padding
        oscMessage.append(typeTagData)
        oscMessage.append(0) // null terminator
        for _ in 0..<typeTagPadding {
            oscMessage.append(0)
        }
        
        // Add string argument with padding
        oscMessage.append(messageData)
        oscMessage.append(0) // null terminator
        for _ in 0..<stringPadding {
            oscMessage.append(0)
        }
        
        // Send the OSC message
        connection.send(content: oscMessage, completion: .contentProcessed { error in
            if let error = error {
                print("Error sending response: \(error)")
            }
            // Cancel the connection when done
            connection.cancel()
        })
    }
    
    // MARK: - Private helpers
    
    /// Encodes a minimal OSC packet with a single Float32 argument.
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
        // Calculate padding for address
        let addressBytes = address.utf8.count
        let addressPadding = (4 - (addressBytes % 4)) % 4
        let addressSize = addressBytes + addressPadding + 1 // +1 for null terminator
        
        // Size for type tag ",f\0\0" (always 4 bytes)
        let typeTagSize = 4
        
        // Float is always 4 bytes
        let floatSize = 4
        
        // Pre-allocate exact buffer size
        var packet = Data(capacity: addressSize + typeTagSize + floatSize)
        
        // Add address with padding
        packet.append(address.data(using: .utf8)!)
        packet.append(0) // null-terminate
        for _ in 0..<addressPadding {
            packet.append(0)
        }
        
        // Add type tag with padding (always ",f\0\0")
        packet.append(",f".data(using: .utf8)!)
        packet.append(0) // null-terminate
        packet.append(0) // padding
        
        // Add float value in big-endian
        var beValue = argument.bitPattern.bigEndian
        withUnsafeBytes(of: &beValue) { packet.append(contentsOf: $0) }
        
        return packet
    }
    
    /// Cleans up resources when the service is deallocated.
    ///
    /// Ensures that network connections are properly closed to prevent resource leaks.
    deinit {
        connectionLock.lock()
        sharedConnection?.cancel()
        sharedConnection = nil
        connectionLock.unlock()
    }
}
