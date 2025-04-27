# OSC Latency Optimization Plan

This document outlines the strategy for optimizing the OSC (Open Sound Control) implementation in the ChattyChannels project to meet the 200ms round-trip-time (RTT) latency budget specified in v0.5 requirements.

## Current Issue

The `OSCServiceTests.testSendRMS_UdpFastPath_RTTUnder200ms()` test is currently failing with RTTs of approximately 300ms. The v0.5 specification requires:

> OSC round-trip time (RTT) ≤ **200 ms** on localhost with one AIplayer instance.

Meeting this requirement is critical for PID controller stability, low-latency user feedback, and future scalability to 64 audio channels.

## Optimization Strategies

### 1. Connection Pooling & Reuse

**Problem**: Creating a new NWConnection for each message adds significant overhead.

**Solution**: Implement a persistent connection that is reused across multiple messages.

```swift
// Singleton connection instance
private var sharedConnection: NWConnection?
private let connectionLock = NSLock()

private func getOrCreateConnection() -> NWConnection {
    connectionLock.lock()
    defer { connectionLock.unlock() }
    
    if sharedConnection == nil || sharedConnection?.state == .cancelled {
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 9000)
        let conn = NWConnection(to: endpoint, using: .udp)
        conn.start(queue: DispatchQueue.global(qos: .userInteractive))
        sharedConnection = conn
    }
    return sharedConnection!
}
```

### 2. Network Parameter Optimization

**Problem**: Default UDP socket parameters don't prioritize low latency.

**Solution**: Configure network parameters specifically for minimal latency.

```swift
let params = NWParameters.udp
params.allowLocalEndpointReuse = true
params.includePeerToPeer = true

// Set service-level latency requirements
if let options = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
    options.serviceClass = .interactive
}
```

### 3. Dedicated High-Priority Queue

**Problem**: General-purpose queues may introduce delays due to thread contention.

**Solution**: Use a dedicated high-priority dispatch queue for OSC traffic.

```swift
private let oscSendQueue = DispatchQueue(label: "com.chatty.osc.send", 
                                         qos: .userInteractive, 
                                         attributes: .concurrent)
```

### 4. Memory Pre-allocation & Fast Encoding

**Problem**: Standard OSC encoding may involve unnecessary memory allocations.

**Solution**: Pre-allocate buffers and optimize the encoding process.

```swift
// Pre-allocate packet structures for common messages
private var rmsPacketCache = [Float: Data]()
private let cacheLock = NSLock()

private func getCachedOrCreatePacket(for rms: Float) -> Data {
    let roundedRMS = round(rms * 100) / 100  // Round to reduce cache size
    
    cacheLock.lock()
    defer { cacheLock.unlock() }
    
    if let cached = rmsPacketCache[roundedRMS] {
        return cached
    }
    
    let packet = OSCService.encodeOSC(address: "/aiplayer/rms", argument: roundedRMS)
    rmsPacketCache[roundedRMS] = packet
    return packet
}
```

### 5. Streamlined Send Completion

**Problem**: Completion handlers with error checking add overhead.

**Solution**: Minimize work in completion handlers, especially for high-frequency RMS updates.

```swift
// Send with highest priority and minimal completion handling
conn.send(content: packet, completion: .contentProcessed { _ in 
    // No connection teardown - keep alive for reuse
})
```

## Implementation Plan

1. Refactor `OSCService` to add connection pooling infrastructure
2. Create optimized network parameters for low-latency communication
3. Implement a dedicated high-priority dispatch queue
4. Add memory pre-allocation and packet caching
5. Refactor the `sendRMS` method to use these optimizations
6. Update tests to verify improved performance

## Expected Performance

By implementing these optimizations, we expect to reduce the RTT from ~300ms to under 200ms, with likely performance in the 50-100ms range depending on system load.

## Validation Criteria

- All tests in `OSCServiceTests` must pass, including the RTT test
- The optimized implementation should still function correctly in the real-world application scenario
- Code should remain maintainable and well-documented

---

*Document created: 2025-04-27*