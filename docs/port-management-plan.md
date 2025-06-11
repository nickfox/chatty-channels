# Port Management Plan for AIplayer/ChattyChannels Communication

## Problem Statement

Currently, all AIplayer plugin instances attempt to bind to port 9000 for receiving OSC messages. Due to a JUCE OSC bug, `receiver.connect()` returns true even when the port is already in use, causing only the first plugin instance to actually receive messages. This breaks the calibration system when multiple tracks are involved.

## Current Limitations

The hardcoded port range 9000-9010 limits the system to only 11 concurrent AIplayer instances (channels). This is insufficient for professional music production where projects commonly have 32, 64, or even 128+ tracks.

## Proposed Solution: Dynamic Port Management

### Architecture Overview

```
┌─────────────────┐                    ┌──────────────────┐
│   AIplayer #1   │◄─────port 9002────►│                  │
├─────────────────┤                    │                  │
│   AIplayer #2   │◄─────port 9003────►│  ChattyChannels │
├─────────────────┤                    │  (Port Manager) │
│   AIplayer #3   │◄─────port 9004────►│                  │
├─────────────────┤                    │                  │
│       ...       │         ◄──────────►│  Listens: 9001  │
└─────────────────┘                    └──────────────────┘
```

### Port Allocation Strategy

1. **Dynamic Range**: Instead of fixed 9000-9010, use 9000-9999 (1000 ports)
   - Supports up to 1000 concurrent plugin instances
   - Far exceeds typical DAW track counts
   - Avoids conflicts with common service ports

2. **Port Pool Management**:
   ```swift
   class PortManager {
       private var availablePorts: Set<UInt16> = Set(9000...9999)
       private var assignedPorts: [String: UInt16] = [:] // tempID -> port
       private var portToPlugin: [UInt16: String] = [:]  // port -> tempID
   }
   ```

### Communication Protocol

#### Phase 1: Port Assignment
```
1. Plugin → ChattyChannels (port 9001):
   /aiplayer/request_port
   - tempInstanceID: String
   - preferredPort: Int32 (optional, -1 if none)

2. ChattyChannels → Plugin (ephemeral response):
   /aiplayer/port_assignment
   - tempInstanceID: String
   - assignedPort: Int32
   - status: String ("assigned" | "error")

3. Plugin → ChattyChannels (port 9001):
   /aiplayer/port_confirmed
   - tempInstanceID: String
   - port: Int32
   - status: String ("bound" | "failed")
```

#### Phase 2: Normal Operation
- Plugin receives on its assigned port (9000-9999)
- Plugin sends to ChattyChannels on port 9001
- ChattyChannels tracks which plugin is on which port

### Implementation Details

#### AIplayer Changes (C++)

```cpp
class AIplayerAudioProcessor {
private:
    enum class PortState {
        Unassigned,
        Requesting,
        Assigned,
        Bound,
        Failed
    };
    
    PortState portState = PortState::Unassigned;
    int assignedPort = -1;
    int portRequestRetries = 0;
    const int maxPortRequestRetries = 5;
    
    void requestPortAssignment();
    void bindToAssignedPort(int port);
    bool verifyPortBinding(int port);
};
```

Key changes:
1. Don't bind to any receiver port on startup
2. Request port assignment from ChattyChannels first
3. Only bind after receiving assignment
4. Implement proper port verification to work around JUCE bug
5. Retry mechanism for port requests

#### ChattyChannels Changes (Swift)

```swift
extension OSCService {
    // Port management
    private let portManager = PortManager()
    
    func handlePortRequest(tempID: String, preferredPort: Int32?) {
        let port = portManager.assignPort(to: tempID, preferred: preferredPort)
        sendPortAssignment(to: tempID, port: port)
    }
    
    func handlePortConfirmation(tempID: String, port: Int32, success: Bool) {
        if success {
            portManager.confirmBinding(tempID: tempID, port: port)
        } else {
            portManager.releasePort(port)
            // Optionally assign alternative port
        }
    }
    
    // For calibration/targeting specific plugins
    func sendToPlugin(tempID: String, message: OSCMessage) {
        guard let port = portManager.getPort(for: tempID) else { return }
        send(message, to: "127.0.0.1", port: port)
    }
}
```

### Benefits

1. **Scalability**: Supports 1000 concurrent plugins (vs current 11)
2. **Reliability**: No port conflicts between plugins
3. **Debuggability**: ChattyChannels knows exactly where each plugin is
4. **Flexibility**: Can dynamically expand port range if needed
5. **Fault Tolerance**: Can reassign ports if binding fails

### Migration Path

1. **Phase 1**: Implement port request/assignment protocol
2. **Phase 2**: Update calibration to use port mappings
3. **Phase 3**: Add port recycling for disconnected plugins
4. **Phase 4**: Add port persistence across sessions (optional)

### Alternative Considerations

#### Option A: Ephemeral Ports
- Let OS assign random high ports
- Plugins report their bound port to ChattyChannels
- More flexible but harder to debug

#### Option B: Single Port with Plugin Multiplexing
- All plugins share one port
- Messages include plugin ID for routing
- Simpler but potential performance bottleneck

#### Why Chosen Solution is Best
- Predictable port range aids debugging
- One port per plugin ensures no message bottlenecks
- Direct addressing enables real-time performance
- Compatible with existing OSC infrastructure

### Security Considerations

- Ports are localhost-only (127.0.0.1)
- No external network access required
- Port range is high enough to avoid system services
- Could add authentication tokens if needed

### Testing Strategy

1. **Unit Tests**: Port allocation/deallocation logic
2. **Integration Tests**: Multi-plugin port assignment
3. **Stress Tests**: 100+ concurrent plugins
4. **Failure Tests**: Port binding failures, retries

## Timeline

1. **Week 1**: Implement basic port management in ChattyChannels
2. **Week 1-2**: Update AIplayer with port request protocol
3. **Week 2**: Update calibration system to use port mappings
4. **Week 3**: Testing and optimization
5. **Week 4**: Documentation and deployment

## Conclusion

This port management system removes the artificial 11-channel limit and provides a robust foundation for professional multi-track audio production. The dynamic assignment ensures reliable communication while maintaining the performance requirements of real-time audio processing.