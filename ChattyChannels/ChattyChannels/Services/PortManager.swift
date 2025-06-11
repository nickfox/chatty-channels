//
//  PortManager.swift
//  ChattyChannels
//
//  Manages dynamic port allocation for AIplayer plugin instances.
//  Supports up to 1000 concurrent plugins using ports 9000-9999.
//

import Foundation

/// Manages port allocation for AIplayer plugin instances
final class PortManager {
    // MARK: - Properties
    
    /// Range of ports available for allocation
    private let portRange: ClosedRange<UInt16> = 9000...9999
    
    /// Set of currently available ports
    private var availablePorts: Set<UInt16>
    
    /// Mapping of plugin temp IDs to assigned ports
    private var assignedPorts: [String: UInt16] = [:]
    
    /// Reverse mapping of ports to plugin temp IDs
    private var portToPlugin: [UInt16: String] = [:]
    
    /// Thread safety lock
    private let lock = NSLock()
    
    /// Tracks port assignment timestamps for cleanup
    private var portAssignmentTime: [UInt16: Date] = [:]
    
    // MARK: - Initialization
    
    init() {
        // Initialize with all ports in range as available
        self.availablePorts = Set(portRange)
        print("[PortManager] Initialized with port range \(portRange.lowerBound)-\(portRange.upperBound)")
    }
    
    // MARK: - Port Assignment
    
    /// Assigns an available port to a plugin instance
    /// - Parameters:
    ///   - tempID: The temporary instance ID of the plugin
    ///   - preferredPort: Optional preferred port number
    /// - Returns: The assigned port number, or nil if no ports available
    func assignPort(to tempID: String, preferred preferredPort: UInt16? = nil) -> UInt16? {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if this plugin already has a port
        if let existingPort = assignedPorts[tempID] {
            print("[PortManager] Plugin \(tempID) already has port \(existingPort)")
            return existingPort
        }
        
        var assignedPort: UInt16?
        
        // Try preferred port first if provided
        if let preferred = preferredPort,
           portRange.contains(preferred),
           availablePorts.contains(preferred) {
            assignedPort = preferred
        } else {
            // Assign the lowest available port for predictability
            assignedPort = availablePorts.sorted().first
        }
        
        guard let port = assignedPort else {
            print("[PortManager] ERROR: No available ports for plugin \(tempID)")
            return nil
        }
        
        // Update tracking structures
        availablePorts.remove(port)
        assignedPorts[tempID] = port
        portToPlugin[port] = tempID
        portAssignmentTime[port] = Date()
        
        print("[PortManager] Assigned port \(port) to plugin \(tempID). Available ports: \(availablePorts.count)")
        return port
    }
    
    // MARK: - Port Confirmation
    
    /// Confirms that a plugin successfully bound to its assigned port
    /// - Parameters:
    ///   - tempID: The temporary instance ID of the plugin
    ///   - port: The port number that was bound
    /// - Returns: True if confirmation successful, false if port mismatch
    func confirmBinding(tempID: String, port: UInt16) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let assignedPort = assignedPorts[tempID] else {
            print("[PortManager] ERROR: No port assigned to plugin \(tempID)")
            return false
        }
        
        guard assignedPort == port else {
            print("[PortManager] ERROR: Port mismatch for plugin \(tempID). Expected \(assignedPort), got \(port)")
            return false
        }
        
        print("[PortManager] Confirmed plugin \(tempID) bound to port \(port)")
        return true
    }
    
    // MARK: - Port Release
    
    /// Releases a port back to the available pool
    /// - Parameter port: The port number to release
    func releasePort(_ port: UInt16) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let tempID = portToPlugin[port] else {
            print("[PortManager] WARNING: Attempting to release unassigned port \(port)")
            return
        }
        
        // Clean up all tracking structures
        availablePorts.insert(port)
        assignedPorts.removeValue(forKey: tempID)
        portToPlugin.removeValue(forKey: port)
        portAssignmentTime.removeValue(forKey: port)
        
        print("[PortManager] Released port \(port) from plugin \(tempID). Available ports: \(availablePorts.count)")
    }
    
    /// Releases port assigned to a specific plugin
    /// - Parameter tempID: The temporary instance ID of the plugin
    func releasePortForPlugin(_ tempID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let port = assignedPorts[tempID] else {
            print("[PortManager] No port assigned to plugin \(tempID)")
            return
        }
        
        // Clean up all tracking structures
        availablePorts.insert(port)
        assignedPorts.removeValue(forKey: tempID)
        portToPlugin.removeValue(forKey: port)
        portAssignmentTime.removeValue(forKey: port)
        
        print("[PortManager] Released port \(port) from plugin \(tempID). Available ports: \(availablePorts.count)")
    }
    
    // MARK: - Port Queries
    
    /// Gets the port assigned to a plugin
    /// - Parameter tempID: The temporary instance ID of the plugin
    /// - Returns: The assigned port number, or nil if none assigned
    func getPort(for tempID: String) -> UInt16? {
        lock.lock()
        defer { lock.unlock() }
        
        return assignedPorts[tempID]
    }
    
    /// Gets the plugin ID assigned to a port
    /// - Parameter port: The port number
    /// - Returns: The plugin temp ID, or nil if port not assigned
    func getPlugin(for port: UInt16) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        return portToPlugin[port]
    }
    
    /// Gets all current port assignments
    /// - Returns: Dictionary mapping temp IDs to ports
    func getAllAssignments() -> [String: UInt16] {
        lock.lock()
        defer { lock.unlock() }
        
        return assignedPorts
    }
    
    /// Gets count of available ports
    /// - Returns: Number of unassigned ports
    func availablePortCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        return availablePorts.count
    }
    
    // MARK: - Maintenance
    
    /// Cleans up stale port assignments older than the specified interval
    /// - Parameter olderThan: Time interval in seconds
    /// - Returns: Number of ports cleaned up
    @discardableResult
    func cleanupStalePorts(olderThan interval: TimeInterval = 300) -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        var cleaned = 0
        
        for (port, assignmentTime) in portAssignmentTime {
            if now.timeIntervalSince(assignmentTime) > interval {
                if let tempID = portToPlugin[port] {
                    // Release the stale port
                    availablePorts.insert(port)
                    assignedPorts.removeValue(forKey: tempID)
                    portToPlugin.removeValue(forKey: port)
                    portAssignmentTime.removeValue(forKey: port)
                    cleaned += 1
                    
                    print("[PortManager] Cleaned up stale port \(port) from plugin \(tempID)")
                }
            }
        }
        
        if cleaned > 0 {
            print("[PortManager] Cleaned up \(cleaned) stale ports. Available ports: \(availablePorts.count)")
        }
        
        return cleaned
    }
    
    /// Resets the port manager to initial state
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        availablePorts = Set(portRange)
        assignedPorts.removeAll()
        portToPlugin.removeAll()
        portAssignmentTime.removeAll()
        
        print("[PortManager] Reset complete. All ports available.")
    }
}