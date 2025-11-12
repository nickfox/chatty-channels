# Multi-Agent Orchestrator Architecture - Implementation Plan

**Version**: 1.0
**Date**: 2025-11-12
**Status**: Planning Phase

---

## Executive Summary

This document outlines the implementation plan for transforming Chatty Channels from a single-LLM architecture to a sophisticated multi-agent system where an orchestrator LLM coordinates four specialized sub-agent LLMs. Each agent has domain-specific responsibilities and can communicate peer-to-peer for efficiency while maintaining orchestrator oversight for high-level coordination.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Agent Specifications](#agent-specifications)
3. [Communication Patterns](#communication-patterns)
4. [Data Flow Examples](#data-flow-examples)
5. [Debug Mode: Mission Control View](#debug-mode-mission-control-view)
6. [Implementation Phases](#implementation-phases)
7. [Technical Design](#technical-design)
8. [State Management](#state-management)
9. [Cost Analysis](#cost-analysis)
10. [Testing Strategy](#testing-strategy)
11. [Risk Mitigation](#risk-mitigation)

---

## 1. Architecture Overview

### 1.1 System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     USER INTERFACE (SwiftUI)                 │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Chat Window + Mission Control Feed          │   │
│  └─────────────────────────────────────────────────────┘   │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
         ┌──────────────────────────────┐
         │   ORCHESTRATOR (Claude 4.5)  │
         │   • Coordinates all agents    │
         │   • High-level planning       │
         │   • User intent parsing       │
         └──────────────┬───────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Chat Agent   │ │AppleScript   │ │ OSC Agent    │
│ (Claude 4.5) │ │Agent (Grok4) │ │ (Grok4 NR)   │
└──────────────┘ └──────────────┘ └───────┬──────┘
                                           │
                                           │ peer-to-peer
                                           ▼
                                  ┌──────────────┐
                                  │Calculations  │
                                  │Agent (Grok4R)│
                                  └──────────────┘

Legend:
─── : Orchestrator → Sub-agent communication
··· : Peer-to-peer agent communication
```

### 1.2 Design Principles

1. **Separation of Concerns**: Each agent has a clearly defined domain
2. **Intelligent Routing**: Orchestrator decides which agents to invoke
3. **Peer Communication**: Agents can communicate directly when efficient
4. **Observable Operations**: All agent actions visible in debug mode
5. **Cost Optimization**: Use cheaper models for mechanical tasks
6. **Reasoning Where Needed**: Use reasoning models for complex analysis

---

## 2. Agent Specifications

### 2.1 Orchestrator Agent

**Model**: Claude Sonnet 4.5
**Role**: System coordinator and strategic planner

**Responsibilities**:
- Parse and understand user intent from natural language
- Decompose complex requests into agent tasks
- Coordinate multi-agent workflows
- Maintain conversation context and history
- Handle error recovery and retry logic
- Make high-level musical/mixing decisions

**Tools Available**:
- `invokeAgent(agentName, task, context)`
- `getSystemState()`
- `updateConversationHistory(message)`
- `setUserPreference(key, value)`

**Invocation Triggers**:
- User sends a message in chat
- Agent reports error requiring orchestrator intervention
- Multi-agent coordination required

**Example Task**:
> User: "Make the vocals louder and add more bass"
>
> Orchestrator reasoning:
> 1. Parse intent: Adjust two tracks (vocals, bass)
> 2. Invoke AppleScript Agent: Identify vocal track
> 3. Invoke AppleScript Agent: Increase vocal volume
> 4. Invoke AppleScript Agent: Identify bass track
> 5. Invoke AppleScript Agent: Increase bass level
> 6. Invoke Chat Agent: Confirm changes to user

---

### 2.2 Chat Agent

**Model**: Claude Sonnet 4.5
**Role**: User-facing communication specialist

**Responsibilities**:
- Generate natural, friendly responses to user
- Explain what the system is doing in musical terms
- Ask clarifying questions when needed
- Provide feedback on operations
- Maintain consistent personality (the "Soundsmith" persona)

**Tools Available**:
- `sendChatMessage(message)`
- `formatMusicalFeedback(data)`
- `askClarificationQuestion(options)`

**Invocation Triggers**:
- Orchestrator needs to communicate with user
- System status update ready for user
- Clarification needed from user

**Personality Guidelines**:
- Warm, professional audio engineer
- Uses musical terminology appropriately
- Encouraging but honest feedback
- Doesn't over-explain technical details

**Example Task**:
> Input: "Vocals increased by 3dB, bass boosted by 5dB"
>
> Output: "I've brought the vocals forward by 3dB and added some punch to the bass with a 5dB boost. The mix should feel more balanced now. Would you like me to adjust anything else?"

---

### 2.3 OSC Agent

**Model**: Grok 4 Fast Non-Reasoning
**Role**: Real-time telemetry handler and protocol manager

**Responsibilities**:
- Monitor incoming OSC messages from AIplayer plugins
- Parse telemetry data (RMS, FFT band energies)
- Maintain connection state with all plugin instances
- Handle connection errors and retries
- Route interesting data to Calculations Agent (peer-to-peer)
- Accumulate data for orchestrator queries

**Tools Available**:
- `sendOSCMessage(address, arguments)`
- `getPluginState(pluginID)`
- `getAllTelemetry()`
- `invokeCalculationsAgent(data, task)` ← peer-to-peer
- `retryConnection(pluginID)`

**Invocation Triggers**:
- Orchestrator requests telemetry data
- Orchestrator needs to send OSC command
- Connection state change detected
- ~~Every OSC message received~~ (NO - too expensive)

**Data Accumulation Strategy**:
```
OSC messages arrive at 24 Hz per plugin
↓
OSC Agent accumulates in local state (no LLM call)
↓
Only invoke LLM when:
  1. Orchestrator explicitly requests data
  2. Anomaly detected (connection drop, invalid data)
  3. Data needs interpretation (threshold exceeded, etc.)
```

**Peer-to-Peer Communication**:
When OSC Agent receives telemetry that needs analysis:
```swift
// Example: Detect frequency spike
if bandEnergy[highFreqs] > threshold {
    // Don't ask orchestrator, go directly to Calculations Agent
    result = await invokeCalculationsAgent(
        data: telemetryData,
        task: "Analyze high-frequency spike in track TR1"
    )
    // Report result back to orchestrator
    await reportToOrchestrator(result)
}
```

---

### 2.4 AppleScript Agent

**Model**: Grok 4 Fast Non-Reasoning
**Role**: Logic Pro automation specialist

**Responsibilities**:
- Execute AppleScript commands to control Logic Pro
- Query track names, volumes, mute states
- Adjust plugin parameters
- Handle track identification
- Parse AppleScript results
- Handle AppleScript errors gracefully

**Tools Available**:
- `executeAppleScript(script)`
- `getTrackList()`
- `setTrackVolume(trackName, volumeDB)`
- `setTrackMute(trackName, muted)`
- `getPluginParameter(trackName, pluginName, paramName)`
- `setPluginParameter(trackName, pluginName, paramName, value)`

**Invocation Triggers**:
- Orchestrator needs to control Logic Pro
- Track information needed
- Parameter adjustment requested

**Example Task**:
> Input: "Set volume of track 'Lead Vocals' to -6dB"
>
> Actions:
> 1. Call executeAppleScript with volume command
> 2. Verify command succeeded
> 3. Return success/failure to orchestrator

---

### 2.5 Calculations Agent

**Model**: Grok 4 Fast Reasoning
**Role**: Signal processing and audio analysis expert

**Responsibilities**:
- Perform FFT analysis and interpretation
- Calculate spectral features (centroid, rolloff, etc.)
- Detect musical patterns in frequency data
- Compare tracks for balance analysis
- Provide mixing insights based on data
- Mathematical reasoning about audio signals

**Tools Available**:
- `calculateFFT(audioData)`
- `analyzeBandEnergies(fftData)`
- `detectTransients(audioData)`
- `compareSpectrums(track1, track2)`
- `suggestEQAdjustments(spectrum)`
- `calculateLoudness(rmsData)`

**Invocation Triggers**:
- Orchestrator requests audio analysis
- OSC Agent detects interesting data (peer-to-peer)
- User asks mixing advice

**Reasoning Capabilities**:
This agent uses the reasoning model to:
- Understand musical context of frequency data
- Infer mixing problems from spectral analysis
- Suggest creative solutions based on audio patterns
- Explain "why" certain frequencies matter

**Example Task**:
> Input from OSC Agent (peer-to-peer):
> "Track TR1 showing energy spike at 3-4kHz, should I be concerned?"
>
> Calculations Agent reasoning:
> - 3-4kHz is vocal presence range
> - Spike could indicate harshness/sibilance
> - Analyze sustained vs transient energy
> - Compare to other vocal tracks
>
> Output: "This is the vocal presence zone. The spike suggests possible harshness - recommend checking for sibilance or reducing 3.5kHz by 2-3dB with narrow Q. Track is 4dB hotter than reference vocal track in this band."

---

## 3. Communication Patterns

### 3.1 Hub-and-Spoke (Orchestrator-Centric)

**When to use**:
- User-initiated requests
- Multi-agent coordination needed
- High-level decisions required

**Flow**:
```
User → Chat Window
      ↓
Orchestrator (parses intent)
      ↓
Orchestrator → Sub-agent(s)
      ↓
Sub-agent(s) → Orchestrator (results)
      ↓
Orchestrator → Chat Agent
      ↓
Chat Agent → User
```

### 3.2 Peer-to-Peer (Direct Agent Communication)

**When to use**:
- Routine data processing (OSC → Calculations)
- No orchestrator decision needed
- Performance optimization

**Flow**:
```
OSC Agent (receives telemetry)
      ↓
OSC Agent → Calculations Agent (analyze this)
      ↓
Calculations Agent → OSC Agent (results)
      ↓
OSC Agent → Orchestrator (report)
```

**Allowed Peer Relationships**:
| From Agent | Can Directly Invoke | Reason |
|------------|---------------------|--------|
| OSC Agent | Calculations Agent | Routine FFT analysis doesn't need orchestrator |
| Calculations Agent | OSC Agent | May need additional telemetry data |
| AppleScript Agent | OSC Agent | May need to verify plugin state |

**Forbidden Peer Relationships**:
- Chat Agent cannot directly invoke other agents (must go through orchestrator)
- AppleScript Agent cannot directly invoke Calculations Agent (orchestrator decides)

### 3.3 Communication Protocol

**Message Format**:
```swift
struct AgentMessage {
    let fromAgent: AgentType
    let toAgent: AgentType
    let task: String
    let context: [String: Any]
    let priority: Priority
    let timestamp: Date
    let requestID: UUID
}

enum AgentType {
    case orchestrator
    case chat
    case osc
    case appleScript
    case calculations
}

enum Priority {
    case realtime  // Must process immediately
    case high      // Process within 100ms
    case normal    // Process within 1s
    case low       // Process when convenient
}
```

---

## 4. Data Flow Examples

### 4.1 Example: Simple User Request

**User**: "What's the current level of the kick drum?"

```
1. User types in chat window
   ↓
2. Orchestrator receives message
   - Parses intent: Query track level
   - Identifies need: AppleScript + OSC data
   - Mission Control: "🎯 ORCHESTRATOR: Analyzing request - need kick drum level"
   ↓
3. Orchestrator → AppleScript Agent
   - Task: "Get track name for kick drum"
   - Mission Control: "📜 APPLESCRIPT: Querying Logic Pro track list"
   ↓
4. AppleScript Agent returns: "Track 3 - Kick"
   - Mission Control: "✅ APPLESCRIPT: Found kick on Track 3"
   ↓
5. Orchestrator → OSC Agent
   - Task: "Get current RMS for Track 3"
   - Mission Control: "📡 OSC: Retrieving telemetry for Track 3"
   ↓
6. OSC Agent returns: "-18.5 dB RMS"
   - Mission Control: "✅ OSC: Current level -18.5 dBFS"
   ↓
7. Orchestrator → Chat Agent
   - Task: "Format response about kick drum level"
   - Context: {track: "Kick", level: -18.5}
   - Mission Control: "💬 CHAT: Composing response"
   ↓
8. Chat Agent generates response
   - Mission Control: "✅ CHAT: Response ready"
   ↓
9. User sees: "The kick drum is currently sitting at -18.5 dBFS, which is a solid level for a kick in most mixes. It has good presence without overpowering."
```

**Orchestrator Decision Logic**:
```
User query → Needs track identification → AppleScript Agent
           → Needs audio level → OSC Agent
           → Needs user response → Chat Agent
```

---

### 4.2 Example: Complex Multi-Agent Task

**User**: "The vocals sound harsh. Can you help?"

```
1. User reports problem
   ↓
2. Orchestrator receives message
   - Parses intent: Diagnose and fix harshness in vocals
   - Mission Control: "🎯 ORCHESTRATOR: Investigating vocal harshness"
   ↓
3. Orchestrator → AppleScript Agent
   - Task: "Identify vocal track"
   - Mission Control: "📜 APPLESCRIPT: Locating vocal track"
   ↓
4. AppleScript returns: "Track 7 - Lead Vocals"
   - Mission Control: "✅ APPLESCRIPT: Vocals on Track 7"
   ↓
5. Orchestrator → OSC Agent
   - Task: "Get frequency spectrum for Track 7"
   - Mission Control: "📡 OSC: Capturing vocal spectrum"
   ↓
6. OSC Agent returns band energies: [low: -45dB, lowMid: -32dB, highMid: -18dB, high: -22dB]
   - Mission Control: "✅ OSC: Spectrum acquired"
   ↓
7. Orchestrator → Calculations Agent
   - Task: "Analyze spectrum for harshness causes"
   - Context: {bandEnergies, trackType: "vocals"}
   - Mission Control: "🔬 CALCULATIONS: Analyzing frequency distribution"
   ↓
8. Calculations Agent reasons:
   - High-mid band (-18dB) is significantly hotter than typical vocal
   - Likely excess energy at 3-4kHz (sibilance/harshness zone)
   - Recommends: -3dB cut at 3.5kHz with Q=2
   - Mission Control: "✅ CALCULATIONS: Detected 3.5kHz spike, suggesting reduction"
   ↓
9. Orchestrator → Chat Agent
   - Task: "Explain findings and get user approval"
   - Context: {problem: "excess 3.5kHz", solution: "-3dB cut"}
   - Mission Control: "💬 CHAT: Preparing diagnosis"
   ↓
10. Chat Agent → User
    - "I've analyzed the vocal track and found excess energy around 3.5kHz, which typically causes that harsh quality. I can reduce this frequency by 3dB with a focused EQ cut. Would you like me to apply this adjustment?"
    - Mission Control: "✅ CHAT: Awaiting user confirmation"
    ↓
11. User: "Yes, please"
    ↓
12. Orchestrator → AppleScript Agent
    - Task: "Apply EQ cut: 3.5kHz, -3dB, Q=2 on Track 7"
    - Mission Control: "📜 APPLESCRIPT: Applying EQ adjustment"
    ↓
13. AppleScript Agent executes
    - Mission Control: "✅ APPLESCRIPT: EQ updated successfully"
    ↓
14. Orchestrator → Chat Agent
    - Task: "Confirm completion"
    - Mission Control: "💬 CHAT: Confirming changes"
    ↓
15. Chat Agent → User
    - "Done! I've applied a -3dB cut at 3.5kHz. Give it a listen - the harshness should be smoothed out now while keeping the vocal presence intact."
    - Mission Control: "✅ CHAT: Task complete"
```

**Total Agent Invocations**: 7 LLM calls
- Orchestrator: 2 (initial + coordination)
- AppleScript: 2 (identify + adjust)
- OSC: 1 (get spectrum)
- Calculations: 1 (analyze)
- Chat: 2 (explain + confirm)

---

### 4.3 Example: Peer-to-Peer Optimization

**Scenario**: OSC Agent receives telemetry showing unusual frequency spike

```
1. AIplayer plugin sends telemetry
   - Track TR1: band energies show sudden spike in high-mids
   ↓
2. OSC Agent (no LLM call yet - just data accumulation)
   - Detects anomaly: highMid energy jumped from -40dB to -15dB
   - Decision: This needs analysis
   - Mission Control: "📡 OSC: Anomaly detected on TR1, consulting Calculations"
   ↓
3. OSC Agent → Calculations Agent (PEER-TO-PEER, no orchestrator)
   - Task: "Sudden 25dB spike in high-mids on TR1, is this a problem?"
   - Context: {before: -40dB, after: -15dB, duration: 2s}
   - Mission Control: "🔬 CALCULATIONS: Analyzing frequency anomaly"
   ↓
4. Calculations Agent reasons:
   - 25dB spike is dramatic
   - Sustained 2s suggests not just transient (cymbal hit)
   - Likely feedback, mic proximity issue, or plugin malfunction
   - Severity: HIGH
   - Mission Control: "✅ CALCULATIONS: Possible feedback condition detected"
   ↓
5. Calculations Agent → OSC Agent (peer response)
   - Result: "HIGH SEVERITY: Likely feedback or plugin issue. Recommend immediate attention."
   ↓
6. OSC Agent → Orchestrator (escalation)
   - Priority: HIGH
   - Message: "Calculations Agent flagged potential feedback on TR1"
   - Mission Control: "⚠️ OSC: Escalating to Orchestrator"
   ↓
7. Orchestrator → Chat Agent
   - Task: "Alert user about feedback risk"
   - Mission Control: "🎯 ORCHESTRATOR: User alert required"
   ↓
8. Chat Agent → User
   - "⚠️ I'm detecting what might be feedback building up on Track 1. You may want to check that track's input or mute it temporarily."
   - Mission Control: "💬 CHAT: Alert delivered"
```

**Key Optimization**:
- OSC Agent didn't ask orchestrator permission to consult Calculations Agent
- Saved 1 orchestrator call
- Faster response time to potential problem
- Orchestrator only involved when escalation needed

---

## 5. Debug Mode: Mission Control View

### 5.1 Visual Design

**Layout**:
```
┌──────────────────────────────────────────────────────────┐
│                    MISSION CONTROL                       │
│                  [DEBUG MODE: ON/OFF]                    │
├──────────────────────────────────────────────────────────┤
│  🎯 ORCHESTRATOR: Analyzing user request...             │
│  📜 APPLESCRIPT: Querying Logic Pro track list          │
│  ✅ APPLESCRIPT: Found 12 tracks                        │
│  📡 OSC: Retrieving telemetry for Track 3               │
│  ✅ OSC: Current level -18.5 dBFS                       │
│  🔬 CALCULATIONS: Analyzing frequency distribution       │
│  ⏳ CALCULATIONS: Running FFT on 1024 samples...        │
│  ✅ CALCULATIONS: Spectrum analysis complete            │
│  💬 CHAT: Composing response                            │
│  ✅ CHAT: Response ready                                │
│  ──────────────────────────────────────────────────     │
│  🎯 ORCHESTRATOR: All agents complete, task finished    │
│                                                          │
│  [Auto-scroll enabled]                                  │
└──────────────────────────────────────────────────────────┘
```

### 5.2 Icon Legend

| Icon | Agent | Meaning |
|------|-------|---------|
| 🎯 | Orchestrator | Strategic decision/coordination |
| 💬 | Chat | User communication |
| 📡 | OSC | Network/telemetry operations |
| 📜 | AppleScript | Logic Pro automation |
| 🔬 | Calculations | Data analysis/math |
| ✅ | Any | Task completed successfully |
| ❌ | Any | Task failed |
| ⚠️ | Any | Warning condition |
| ⏳ | Any | Long-running operation |
| 🔄 | Any | Retry attempt |
| 🔗 | Any | Peer-to-peer communication |

### 5.3 Message Format

**Standard format**:
```
[Icon] [AGENT]: [Action description]
```

**Examples**:
```
✅ APPLESCRIPT: Track 'Lead Vocals' volume set to -6dB
❌ OSC: Failed to connect to plugin TR1, retrying...
🔄 OSC: Retry attempt 2/3 for plugin TR1
⚠️ CALCULATIONS: High-frequency spike detected (>20dB)
🔗 OSC → CALCULATIONS: Requesting spectrum analysis
⏳ APPLESCRIPT: Waiting for Logic Pro response...
```

### 5.4 Implementation Details

```swift
/// Mission Control message logger
class MissionControlLogger: ObservableObject {
    @Published var messages: [MissionControlMessage] = []
    @Published var isEnabled: Bool = false

    private let maxMessages = 500 // Keep last 500 messages

    func log(agent: AgentType, status: Status, message: String) {
        guard isEnabled else { return }

        let entry = MissionControlMessage(
            timestamp: Date(),
            agent: agent,
            status: status,
            message: message
        )

        DispatchQueue.main.async {
            self.messages.append(entry)
            if self.messages.count > self.maxMessages {
                self.messages.removeFirst()
            }
        }
    }
}

struct MissionControlMessage: Identifiable {
    let id = UUID()
    let timestamp: Date
    let agent: AgentType
    let status: Status
    let message: String

    var icon: String {
        switch (agent, status) {
        case (.orchestrator, _): return "🎯"
        case (.chat, _): return "💬"
        case (.osc, _): return "📡"
        case (.appleScript, _): return "📜"
        case (.calculations, _): return "🔬"
        }
    }

    var prefix: String {
        switch status {
        case .success: return "✅"
        case .failure: return "❌"
        case .warning: return "⚠️"
        case .working: return "⏳"
        case .peerToPeer: return "🔗"
        case .retry: return "🔄"
        case .neutral: return icon
        }
    }
}

enum Status {
    case success, failure, warning, working, peerToPeer, retry, neutral
}
```

### 5.5 SwiftUI View

```swift
struct MissionControlView: View {
    @ObservedObject var logger: MissionControlLogger
    @State private var shouldAutoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("MISSION CONTROL")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.green)
                Spacer()
                Toggle("Debug Mode", isOn: $logger.isEnabled)
                    .toggleStyle(.switch)
            }
            .padding()
            .background(Color.black)

            Divider()

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(logger.messages) { message in
                            MissionControlMessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color.black)
                .onChange(of: logger.messages.count) { _ in
                    if shouldAutoScroll, let lastMessage = logger.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .cornerRadius(8)
    }
}

struct MissionControlMessageView: View {
    let message: MissionControlMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message.prefix)
                .font(.system(size: 12))

            Text(message.agent.rawValue.uppercased() + ":")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(message.agent.color)

            Text(message.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)

            Spacer()

            Text(timeString(message.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

extension AgentType {
    var color: Color {
        switch self {
        case .orchestrator: return .purple
        case .chat: return .blue
        case .osc: return .orange
        case .appleScript: return .yellow
        case .calculations: return .cyan
        }
    }
}
```

### 5.6 Usage Example

```swift
// In any agent operation
missionControl.log(
    agent: .orchestrator,
    status: .neutral,
    message: "Analyzing user request: 'Make vocals louder'"
)

// When starting a task
missionControl.log(
    agent: .appleScript,
    status: .working,
    message: "Executing AppleScript: getTrackList()"
)

// On success
missionControl.log(
    agent: .appleScript,
    status: .success,
    message: "Retrieved 12 tracks from Logic Pro"
)

// Peer-to-peer communication
missionControl.log(
    agent: .osc,
    status: .peerToPeer,
    message: "OSC → CALCULATIONS: Requesting FFT analysis for TR1"
)

// On error
missionControl.log(
    agent: .osc,
    status: .failure,
    message: "Connection timeout for plugin TR1"
)
```

---

## 6. Implementation Phases

### Phase 1: Foundation (Week 1)
**Goal**: Build core infrastructure without LLMs

**Tasks**:
1. Create agent protocol and base classes
2. Implement message passing system
3. Build Mission Control UI and logger
4. Create agent registry and lifecycle management
5. Implement configuration system for model assignments

**Deliverables**:
- `Agent` protocol
- `AgentMessage` struct
- `AgentCoordinator` class
- `MissionControlLogger` class
- `MissionControlView` SwiftUI view
- Unit tests for message passing

**Success Criteria**:
- Agents can send messages to each other
- Mission Control displays agent activity
- Debug mode toggle works

---

### Phase 2: Individual Agents (Week 2)
**Goal**: Implement each agent with mock LLM responses

**Tasks**:
1. Implement `OrchestratorAgent` with Claude 4.5 integration
2. Implement `ChatAgent` with Claude 4.5 integration
3. Implement `OSCAgent` with Grok 4 Fast NR integration
4. Implement `AppleScriptAgent` with Grok 4 Fast NR integration
5. Implement `CalculationsAgent` with Grok 4 Fast R integration
6. Create tool/function definitions for each agent
7. Implement agent-specific state management

**Deliverables**:
- All 5 agent classes functional
- Tool calling infrastructure
- Agent-specific error handling
- Unit tests for each agent

**Success Criteria**:
- Each agent can invoke its LLM
- Tools are called correctly
- Mission Control shows agent activity

---

### Phase 3: Orchestrator Logic (Week 3)
**Goal**: Implement intelligent task routing

**Tasks**:
1. Build prompt engineering for orchestrator
2. Implement intent parsing
3. Create task decomposition logic
4. Build agent selection heuristics
5. Implement context management
6. Add conversation history tracking

**Deliverables**:
- Orchestrator system prompt
- Task routing logic
- Context manager
- Conversation history store

**Success Criteria**:
- Orchestrator correctly interprets user requests
- Appropriate agents are invoked
- Context is maintained across multi-turn conversations

---

### Phase 4: Peer-to-Peer Communication (Week 4)
**Goal**: Enable direct agent-to-agent communication

**Tasks**:
1. Define peer communication rules
2. Implement OSC → Calculations peer channel
3. Add escalation logic (when to involve orchestrator)
4. Create peer message format
5. Add peer communication to Mission Control

**Deliverables**:
- Peer communication protocol
- OSC-Calculations integration
- Escalation rules
- Updated Mission Control display

**Success Criteria**:
- OSC Agent can directly invoke Calculations Agent
- Escalations work correctly
- Mission Control shows peer messages

---

### Phase 5: Integration & Error Handling (Week 5)
**Goal**: Robust end-to-end system

**Tasks**:
1. Integrate all agents into ChattyChannels app
2. Implement comprehensive error handling
3. Add retry logic for LLM failures
4. Build rate limiting and cost controls
5. Add circuit breaker pattern for failed agents
6. Performance optimization

**Deliverables**:
- Fully integrated system
- Error recovery mechanisms
- Cost monitoring dashboard
- Performance benchmarks

**Success Criteria**:
- System handles LLM failures gracefully
- Cost stays within budget
- Response time < 3s for simple requests

---

### Phase 6: Testing & Refinement (Week 6)
**Goal**: Production-ready system

**Tasks**:
1. Integration testing with real Logic Pro sessions
2. Load testing with multiple simultaneous requests
3. Prompt engineering refinement
4. User acceptance testing
5. Documentation
6. Performance tuning

**Deliverables**:
- Test suite
- Performance report
- User documentation
- Refined prompts

**Success Criteria**:
- All tests passing
- User feedback positive
- System stable under load

---

## 7. Technical Design

### 7.1 Core Protocols

```swift
/// Base protocol for all agents
protocol Agent: AnyObject {
    var agentType: AgentType { get }
    var modelName: String { get }
    var isAvailable: Bool { get }
    var missionControl: MissionControlLogger { get }

    /// Execute a task and return the result
    func execute(task: AgentTask) async throws -> AgentResult

    /// Get agent's current state
    func getState() -> AgentState

    /// Invoke another agent (may require orchestrator permission)
    func invokeAgent(_ agent: AgentType, task: AgentTask) async throws -> AgentResult
}

/// Task given to an agent
struct AgentTask {
    let id: UUID
    let description: String
    let context: [String: Any]
    let priority: Priority
    let requester: AgentType
    let timestamp: Date
}

/// Result from agent execution
struct AgentResult {
    let taskID: UUID
    let success: Bool
    let data: [String: Any]
    let message: String?
    let error: Error?
}

/// Agent state information
struct AgentState {
    let agentType: AgentType
    let isProcessing: Bool
    let currentTask: AgentTask?
    let lastActivity: Date
    let queuedTasks: Int
}
```

### 7.2 LLM Integration Layer

```swift
/// Protocol for LLM providers
protocol LLMProvider {
    var modelName: String { get }
    func sendMessage(_ input: String, systemPrompt: String) async throws -> String
    func sendMessageWithTools(_ input: String, systemPrompt: String, tools: [Tool]) async throws -> LLMResponse
}

/// Generic LLM response with tool calls
struct LLMResponse {
    let message: String?
    let toolCalls: [ToolCall]?
    let finishReason: String
}

struct ToolCall {
    let id: String
    let name: String
    let arguments: [String: Any]
}

/// Tool definition for LLM
struct Tool {
    let name: String
    let description: String
    let parameters: JSONSchema
}
```

### 7.3 Grok Integration

```swift
/// Grok 4 provider implementation
final class GrokProvider: LLMProvider {
    private let apiKey: String
    private let modelName: String
    private let endpoint: URL
    private let useReasoning: Bool

    static let modelFastReasoning = "grok-4-fast-reasoning"
    static let modelFastNonReasoning = "grok-4-fast-non-reasoning"

    init(apiKey: String, modelName: String) {
        self.apiKey = apiKey
        self.modelName = modelName
        self.useReasoning = modelName.contains("reasoning")
        self.endpoint = URL(string: "https://api.x.ai/v1/chat/completions")!
    }

    func sendMessageWithTools(_ input: String, systemPrompt: String, tools: [Tool]) async throws -> LLMResponse {
        // Implement Grok API call with tool support
        // Similar to OpenAI function calling format
    }
}
```

### 7.4 Agent Coordinator

```swift
/// Central coordinator for agent lifecycle and communication
class AgentCoordinator: ObservableObject {
    @Published var orchestrator: OrchestratorAgent
    @Published var agents: [AgentType: Agent] = [:]

    let missionControl: MissionControlLogger
    private let messageQueue: AgentMessageQueue

    init(config: AgentConfiguration) {
        self.missionControl = MissionControlLogger()
        self.messageQueue = AgentMessageQueue()

        // Initialize all agents
        self.orchestrator = OrchestratorAgent(
            provider: ClaudeProvider(apiKey: config.claudeAPIKey, modelName: "claude-sonnet-4-5-20250929"),
            missionControl: missionControl,
            coordinator: self
        )

        self.agents[.chat] = ChatAgent(
            provider: ClaudeProvider(apiKey: config.claudeAPIKey),
            missionControl: missionControl
        )

        self.agents[.osc] = OSCAgent(
            provider: GrokProvider(apiKey: config.grokAPIKey, modelName: .modelFastNonReasoning),
            missionControl: missionControl,
            oscService: config.oscService
        )

        self.agents[.appleScript] = AppleScriptAgent(
            provider: GrokProvider(apiKey: config.grokAPIKey, modelName: .modelFastNonReasoning),
            missionControl: missionControl
        )

        self.agents[.calculations] = CalculationsAgent(
            provider: GrokProvider(apiKey: config.grokAPIKey, modelName: .modelFastReasoning),
            missionControl: missionControl
        )
    }

    /// User sends a message
    func handleUserMessage(_ message: String) async {
        missionControl.log(agent: .orchestrator, status: .neutral, message: "User: \(message)")

        do {
            let result = try await orchestrator.execute(task: AgentTask(
                id: UUID(),
                description: message,
                context: [:],
                priority: .normal,
                requester: .orchestrator,
                timestamp: Date()
            ))

            missionControl.log(agent: .orchestrator, status: .success, message: "Task completed")
        } catch {
            missionControl.log(agent: .orchestrator, status: .failure, message: "Error: \(error.localizedDescription)")
        }
    }

    /// Route message between agents
    func routeMessage(_ message: AgentMessage) async throws -> AgentResult {
        guard let targetAgent = agents[message.toAgent] else {
            throw AgentError.agentNotFound(message.toAgent)
        }

        // Check if peer-to-peer is allowed
        let isPeerAllowed = isPeerCommunicationAllowed(from: message.fromAgent, to: message.toAgent)

        if isPeerAllowed {
            missionControl.log(
                agent: message.fromAgent,
                status: .peerToPeer,
                message: "\(message.fromAgent.rawValue.uppercased()) → \(message.toAgent.rawValue.uppercased()): \(message.task)"
            )
        } else if message.fromAgent != .orchestrator {
            // Not allowed, must go through orchestrator
            throw AgentError.unauthorizedPeerCommunication(from: message.fromAgent, to: message.toAgent)
        }

        let task = AgentTask(
            id: message.requestID,
            description: message.task,
            context: message.context,
            priority: message.priority,
            requester: message.fromAgent,
            timestamp: message.timestamp
        )

        return try await targetAgent.execute(task: task)
    }

    private func isPeerCommunicationAllowed(from: AgentType, to: AgentType) -> Bool {
        switch (from, to) {
        case (.osc, .calculations), (.calculations, .osc):
            return true
        case (.appleScript, .osc), (.osc, .appleScript):
            return true
        default:
            return false
        }
    }
}
```

### 7.5 OSC Agent Implementation Example

```swift
final class OSCAgent: Agent {
    let agentType: AgentType = .osc
    let modelName: String
    let missionControl: MissionControlLogger

    private let llmProvider: LLMProvider
    private let oscService: OSCService
    private var telemetryCache: [String: TelemetryData] = [:]

    var isAvailable: Bool { oscService.isConnected }

    init(provider: LLMProvider, missionControl: MissionControlLogger, oscService: OSCService) {
        self.llmProvider = provider
        self.modelName = provider.modelName
        self.missionControl = missionControl
        self.oscService = oscService

        // Subscribe to OSC messages
        setupOSCListener()
    }

    func execute(task: AgentTask) async throws -> AgentResult {
        missionControl.log(agent: .osc, status: .working, message: task.description)

        // Build system prompt
        let systemPrompt = buildSystemPrompt()

        // Build user message with context
        let userMessage = buildUserMessage(task: task)

        // Define tools available to this agent
        let tools = [
            Tool(name: "sendOSCMessage", description: "Send OSC message to plugin", parameters: oscMessageSchema),
            Tool(name: "getTelemetry", description: "Get current telemetry for plugin", parameters: telemetrySchema),
            Tool(name: "invokeCalculations", description: "Ask Calculations Agent to analyze data", parameters: calculationsSchema)
        ]

        // Call LLM
        let response = try await llmProvider.sendMessageWithTools(userMessage, systemPrompt: systemPrompt, tools: tools)

        // Execute any tool calls
        var toolResults: [String: Any] = [:]
        if let toolCalls = response.toolCalls {
            for toolCall in toolCalls {
                let result = try await executeTool(toolCall)
                toolResults[toolCall.name] = result
            }
        }

        missionControl.log(agent: .osc, status: .success, message: "Completed: \(task.description)")

        return AgentResult(
            taskID: task.id,
            success: true,
            data: toolResults,
            message: response.message,
            error: nil
        )
    }

    private func setupOSCListener() {
        oscService.onTelemetryReceived = { [weak self] telemetry in
            self?.handleTelemetry(telemetry)
        }
    }

    private func handleTelemetry(_ telemetry: TelemetryData) {
        // Cache telemetry (no LLM call)
        telemetryCache[telemetry.trackID] = telemetry

        // Check for anomalies
        if detectAnomaly(telemetry) {
            // Invoke Calculations Agent directly (peer-to-peer)
            Task {
                await consultCalculationsAgent(about: telemetry)
            }
        }
    }

    private func detectAnomaly(_ telemetry: TelemetryData) -> Bool {
        // Simple heuristic - could be made smarter
        return telemetry.bandEnergies.contains { $0 > -15.0 } // Unusually hot
    }

    private func consultCalculationsAgent(about telemetry: TelemetryData) async {
        missionControl.log(agent: .osc, status: .peerToPeer, message: "Consulting Calculations Agent about anomaly")

        // This is peer-to-peer - no orchestrator involved
        // (Implementation would use AgentCoordinator.routeMessage)
    }

    private func buildSystemPrompt() -> String {
        """
        You are the OSC Agent for Chatty Channels, responsible for communicating with AIplayer audio plugins via OSC protocol.

        Your responsibilities:
        - Monitor incoming telemetry data (RMS levels, frequency band energies)
        - Send OSC messages to control plugins
        - Detect connection issues and handle retries
        - Identify anomalies in audio data
        - Consult the Calculations Agent when complex analysis is needed

        Available tools:
        - sendOSCMessage: Send an OSC message to a plugin
        - getTelemetry: Retrieve current telemetry data for a plugin
        - invokeCalculations: Ask the Calculations Agent to analyze data (use for complex analysis only)

        When you detect unusual patterns in telemetry (sudden spikes, drops, or sustained anomalies),
        immediately invoke the Calculations Agent to analyze the issue. Don't wait for orchestrator permission.

        Be concise and technical in your responses. You are talking to other agents, not the user.
        """
    }

    private func buildUserMessage(task: AgentTask) -> String {
        var message = task.description

        // Add relevant context
        if let trackID = task.context["trackID"] as? String,
           let telemetry = telemetryCache[trackID] {
            message += "\n\nCurrent telemetry for \(trackID):"
            message += "\n- RMS: \(telemetry.rmsLevel) dB"
            message += "\n- Band energies: \(telemetry.bandEnergies)"
        }

        return message
    }

    private func executeTool(_ toolCall: ToolCall) async throws -> Any {
        switch toolCall.name {
        case "sendOSCMessage":
            return try await executeOSCSend(toolCall.arguments)
        case "getTelemetry":
            return executeTelemetryGet(toolCall.arguments)
        case "invokeCalculations":
            return try await executeCalculationsInvoke(toolCall.arguments)
        default:
            throw AgentError.unknownTool(toolCall.name)
        }
    }
}
```

---

## 8. State Management

### 8.1 Agent State

Each agent maintains its own internal state:

**OrchestratorAgent**:
- Conversation history
- Active agent tasks
- User preferences
- System goals

**ChatAgent**:
- Last N messages
- User sentiment
- Conversation context

**OSCAgent**:
- Telemetry cache (last 100 messages per plugin)
- Connection states
- Plugin registry

**AppleScriptAgent**:
- Track list cache
- Parameter cache
- Last query results

**CalculationsAgent**:
- Analysis history
- Reference spectrums
- Learned patterns

### 8.2 Shared State

Managed by `AgentCoordinator`:

```swift
class SharedState: ObservableObject {
    // Track information
    @Published var tracks: [Track] = []
    @Published var currentTrackMapping: [String: String] = [:] // pluginID -> trackName

    // Audio levels
    @Published var audioLevels: [String: AudioLevel] = [:]

    // User preferences
    @Published var mixingGoals: [String: Any] = [:]

    // System state
    @Published var logicProConnected: Bool = false
    @Published var oscConnected: Bool = false
}
```

### 8.3 State Persistence

```swift
/// Persist agent state between sessions
class AgentStateManager {
    func save(state: SharedState) async throws {
        // Save to disk
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL)
    }

    func load() async throws -> SharedState {
        // Load from disk
        let data = try Data(contentsOf: stateFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(SharedState.self, from: data)
    }
}
```

---

## 9. Cost Analysis

### 9.1 Model Pricing (Estimated)

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| Claude Sonnet 4.5 | $3.00 | $15.00 |
| Grok 4 Fast Reasoning | $0.50 | $2.00 |
| Grok 4 Fast Non-Reasoning | $0.30 | $1.00 |

### 9.2 Token Usage Estimates

**Per User Request**:

| Agent | Calls | Avg Input Tokens | Avg Output Tokens | Model |
|-------|-------|-----------------|-------------------|-------|
| Orchestrator | 1-2 | 500 | 200 | Claude 4.5 |
| Chat | 1-2 | 300 | 150 | Claude 4.5 |
| OSC | 0-2 | 200 | 100 | Grok 4 NR |
| AppleScript | 1-3 | 250 | 100 | Grok 4 NR |
| Calculations | 0-1 | 300 | 200 | Grok 4 R |

**Simple Request Cost** (e.g., "What's the kick drum level?"):
- Orchestrator: 1 call × (500 input + 200 output) = 700 tokens × $3/$15 = ~$0.003
- AppleScript: 1 call × (250 input + 100 output) = 350 tokens × $0.30/$1 = ~$0.0001
- OSC: 1 call × (200 input + 100 output) = 300 tokens × $0.30/$1 = ~$0.0001
- Chat: 1 call × (300 input + 150 output) = 450 tokens × $3/$15 = ~$0.002

**Total: ~$0.005 per simple request** (half a cent)

**Complex Request Cost** (e.g., "Fix harsh vocals"):
- Orchestrator: 2 calls = ~$0.006
- AppleScript: 2 calls = ~$0.0002
- OSC: 1 call = ~$0.0001
- Calculations: 1 call = ~$0.0005
- Chat: 2 calls = ~$0.004

**Total: ~$0.011 per complex request** (about 1 cent)

**Daily Usage Estimate** (active user):
- 50 simple requests = $0.25
- 20 complex requests = $0.22
- **Total: ~$0.47/day or ~$14/month per active user**

### 9.3 Cost Control Mechanisms

```swift
class CostController {
    private let dailyLimit: Decimal = 5.00 // $5/day max
    private var todaySpent: Decimal = 0

    func checkBudget(estimatedCost: Decimal) -> Bool {
        return (todaySpent + estimatedCost) <= dailyLimit
    }

    func recordUsage(tokens: TokenUsage, model: String) {
        let cost = calculateCost(tokens: tokens, model: model)
        todaySpent += cost

        if todaySpent > dailyLimit * 0.8 {
            // Warn user
            notifyApproachingLimit()
        }
    }
}
```

---

## 10. Testing Strategy

### 10.1 Unit Tests

**Agent Tests**:
```swift
class OrchestratorAgentTests: XCTestCase {
    func testIntentParsing() async throws {
        let agent = OrchestratorAgent(provider: MockLLMProvider())
        let task = AgentTask(description: "Make vocals louder")
        let result = try await agent.execute(task: task)

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.data["invokedAgents"] as? [AgentType] == [.appleScript])
    }
}
```

### 10.2 Integration Tests

**Multi-Agent Workflow**:
```swift
class AgentIntegrationTests: XCTestCase {
    func testVocalAdjustmentWorkflow() async throws {
        let coordinator = AgentCoordinator(config: testConfig)

        await coordinator.handleUserMessage("Make vocals louder")

        // Verify correct agent sequence
        XCTAssertEqual(coordinator.missionControl.messages.count, 7)
        XCTAssertTrue(coordinator.missionControl.messages.contains {
            $0.agent == .appleScript && $0.message.contains("vocal")
        })
    }
}
```

### 10.3 Performance Tests

```swift
func testResponseTime() async throws {
    let start = Date()
    await coordinator.handleUserMessage("What's the kick level?")
    let duration = Date().timeIntervalSince(start)

    XCTAssertLessThan(duration, 3.0, "Response should be < 3 seconds")
}
```

### 10.4 Cost Tests

```swift
func testCostTracking() async throws {
    let costController = CostController()

    // Simulate 100 requests
    for _ in 0..<100 {
        await coordinator.handleUserMessage("Test request")
    }

    XCTAssertLessThan(costController.todaySpent, 1.00, "100 requests should cost < $1")
}
```

---

## 11. Risk Mitigation

### 11.1 LLM Availability

**Risk**: Claude or Grok API downtime
**Mitigation**:
- Implement circuit breaker pattern
- Fall back to cached responses for common queries
- Queue requests during outages
- Notify user of degraded service

```swift
class CircuitBreaker {
    private var failureCount = 0
    private let threshold = 3
    private var isOpen = false

    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        guard !isOpen else {
            throw CircuitBreakerError.open
        }

        do {
            let result = try await operation()
            failureCount = 0
            return result
        } catch {
            failureCount += 1
            if failureCount >= threshold {
                isOpen = true
            }
            throw error
        }
    }
}
```

### 11.2 Cost Overrun

**Risk**: Unexpected high LLM usage
**Mitigation**:
- Daily spending limits
- Rate limiting per user
- Cost estimation before execution
- Alerts at 80% of budget

### 11.3 Incorrect Agent Actions

**Risk**: Agent makes wrong decision (e.g., mutes wrong track)
**Mitigation**:
- Require user confirmation for destructive operations
- Implement undo functionality
- Comprehensive logging
- User override capability

### 11.4 Performance Degradation

**Risk**: Multiple LLM calls slow down system
**Mitigation**:
- Parallel agent invocations where possible
- Caching common queries
- Timeout enforcement (3s for simple, 10s for complex)
- Fallback to simpler operations

---

## 12. Open Questions

### 12.1 System Prompt Management

**Question**: Should system prompts be:
- A) Stored in separate `.txt` files per agent?
- B) Defined in Swift code as strings?
- C) Stored in a database for easy updating?

**Recommendation**: Separate `.txt` files in `ChattyChannels/Resources/AgentPrompts/`
- Easy to edit without recompiling
- Version control friendly
- Can be updated without code changes

### 12.2 Conversation Context Window

**Question**: How many messages should orchestrator remember?
- Last 10 messages? Last 20? Entire session?
- Should old messages be summarized to save tokens?

**Recommendation**:
- Keep last 20 messages in full
- Summarize older messages beyond 20
- Reset conversation context with explicit user command

### 12.3 Agent Tool Expansion

**Question**: Should agents be able to:
- Invoke external APIs (Spotify, Apple Music for reference tracks)?
- Access file system to read/write session notes?
- Control other macOS apps beyond Logic Pro?

**Recommendation**: Start conservative, expand based on user needs

### 12.4 Multi-User Support

**Question**: Will multiple users share one Chatty Channels instance?
**Impact**: Affects state management, cost tracking, conversation history

**Recommendation**: Design for single user initially, architect for multi-user future

---

## 13. Success Criteria

### 13.1 Functional Requirements

- ✅ User can ask natural language questions about their mix
- ✅ System correctly identifies tracks and plugins
- ✅ Orchestrator intelligently routes tasks to appropriate agents
- ✅ Peer-to-peer communication works without orchestrator bottleneck
- ✅ Mission Control provides visibility into agent operations
- ✅ All agents log activity in human-readable format

### 13.2 Performance Requirements

- ✅ Simple requests respond in < 3 seconds
- ✅ Complex requests respond in < 10 seconds
- ✅ System handles 50 requests/hour without degradation
- ✅ OSC telemetry processed at 24 Hz without drops

### 13.3 Cost Requirements

- ✅ Average cost per request < $0.01
- ✅ Daily cost for active user < $1.00
- ✅ Monthly cost per user < $30

### 13.4 Quality Requirements

- ✅ Orchestrator correctly interprets intent >90% of time
- ✅ Agent tool calls succeed >95% of time
- ✅ User satisfaction >4/5 in testing
- ✅ No destructive actions without confirmation

---

## 14. Next Steps

1. **Review this document** with stakeholders
2. **Refine agent responsibilities** based on feedback
3. **Create detailed system prompts** for each agent
4. **Set up development environment** (API keys, test Logic session)
5. **Begin Phase 1 implementation** (Foundation)

---

## Appendix A: Example System Prompts

### Orchestrator System Prompt (Draft)

```
You are the Orchestrator for Chatty Channels, an AI-powered mixing assistant for Logic Pro.

Your role is to coordinate four specialized sub-agents:
1. Chat Agent - User communication specialist
2. OSC Agent - Real-time audio telemetry handler
3. AppleScript Agent - Logic Pro automation specialist
4. Calculations Agent - Audio analysis and DSP expert

When a user sends a message:
1. Parse their intent (what do they want to accomplish?)
2. Determine which agents need to be involved
3. Invoke agents in the correct order
4. Coordinate their responses
5. Ensure the user gets a coherent, helpful response

Guidelines:
- Break complex tasks into smaller sub-tasks
- Invoke multiple agents in parallel when possible
- Handle errors gracefully and inform the user
- Maintain conversation context
- Don't over-explain - be concise but clear
- When in doubt, ask the user for clarification

Available agents:
- Chat: Use when you need to communicate with the user
- OSC: Use when you need telemetry data or OSC commands
- AppleScript: Use when you need to control Logic Pro
- Calculations: Use when you need audio analysis or DSP insights

The user is a music producer working in Logic Pro. They trust you to help them make their mix sound better.
```

### Chat Agent System Prompt (Draft)

```
You are the Chat Agent for Chatty Channels, the user-facing personality of the system.

Your personality: "The Soundsmith"
- Warm, encouraging audio engineer
- Knowledgeable but not condescending
- Uses appropriate music/audio terminology
- Concise but friendly
- Occasionally uses subtle audio humor

Your job:
- Translate technical information into user-friendly language
- Ask clarifying questions when needed
- Provide feedback on mixing decisions
- Celebrate user's progress
- Explain what the system is doing in musical terms

Guidelines:
- Keep responses under 3 sentences when possible
- Use musical metaphors when helpful
- Don't over-explain technical details unless asked
- Be honest if something won't work
- Encourage experimentation

Examples of your style:
- Good: "I've pulled the bass back by 2dB. Give it a listen - should sit better in the mix now."
- Bad: "The bass track's volume parameter has been decreased by 2 decibels in the digital audio workstation."

Remember: You're a helpful mixing assistant, not just an API response formatter.
```

### OSC Agent System Prompt (Draft)

```
You are the OSC Agent for Chatty Channels. You handle all communication with AIplayer audio plugins via OSC protocol.

Your responsibilities:
- Monitor incoming telemetry (RMS levels, frequency band energies)
- Send OSC messages to control plugins
- Detect anomalies in audio data
- Consult Calculations Agent for complex analysis (you can do this directly without asking orchestrator)

Available tools:
- sendOSCMessage(address, args): Send OSC message
- getTelemetry(pluginID): Get current telemetry
- invokeCalculations(data, task): Ask Calculations Agent to analyze (PEER-TO-PEER)

When to invoke Calculations Agent (peer-to-peer):
- Sudden level changes >20dB
- Sustained unusual frequency patterns
- Potential feedback conditions
- User asks about frequency content

Be concise and technical. You're communicating with other agents, not the user.

Telemetry format:
- RMS: dBFS (typically -60 to 0)
- Band energies: [low, lowMid, highMid, high] in dBFS
- Frequency ranges: Low (20-250Hz), LowMid (250-2kHz), HighMid (2k-8kHz), High (8k-20kHz)
```

### AppleScript Agent System Prompt (Draft)

```
You are the AppleScript Agent for Chatty Channels. You control Logic Pro via AppleScript.

Your responsibilities:
- Execute AppleScript commands
- Query track information
- Adjust parameters (volume, mute, plugins)
- Handle Logic Pro errors gracefully

Available tools:
- executeAppleScript(script): Run AppleScript
- getTrackList(): Get all track names
- setTrackVolume(track, db): Set track volume
- setTrackMute(track, muted): Mute/unmute track

Important:
- Always verify track names before operating on them
- Handle AppleScript errors gracefully
- Return clear success/failure messages
- Be aware that AppleScript can be slow (2-3 second delays normal)

Common track name patterns:
- Vocals: "Lead Vocals", "Vox", "Lead Voc"
- Drums: "Kick", "Snare", "Drums", "Kit"
- Bass: "Bass", "Sub", "808"

Be technical and precise. You're talking to other agents.
```

### Calculations Agent System Prompt (Draft)

```
You are the Calculations Agent for Chatty Channels. You are the DSP and audio analysis expert.

Your expertise:
- FFT analysis and spectral processing
- Frequency domain reasoning
- Musical acoustics
- Mixing principles
- Signal processing mathematics

Available tools:
- calculateFFT(data): Compute FFT
- analyzeBandEnergies(fft): Extract band energies
- compareSpectrums(track1, track2): Compare frequency content
- suggestEQAdjustments(spectrum): Recommend EQ changes

Frequency band meanings:
- Low (20-250Hz): Sub bass, kick fundamentals, bass guitar
- LowMid (250-2kHz): Body, warmth, male vocals, snare body
- HighMid (2k-8kHz): Presence, clarity, female vocals, sibilance
- High (8k-20kHz): Air, cymbals, sparkle

Typical mixing targets:
- Vocal presence: -25 to -30 dBFS in high-mids
- Kick: -20 to -25 dBFS in lows
- Overall mix: -14 to -18 dBFS RMS

When analyzing:
1. Consider musical context (genre, instrumentation)
2. Compare to typical reference values
3. Identify specific problems (frequencies, dB amounts)
4. Suggest specific, actionable fixes

You use REASONING. Think through problems step by step. Explain your logic.

Be technical but explain WHY, not just WHAT.
```

---

## Appendix B: Tool Definitions (JSON Schema Examples)

### OSC Agent Tools

```json
{
  "name": "sendOSCMessage",
  "description": "Send an OSC message to an AIplayer plugin",
  "parameters": {
    "type": "object",
    "properties": {
      "address": {
        "type": "string",
        "description": "OSC address pattern (e.g., /aiplayer/control)"
      },
      "arguments": {
        "type": "array",
        "description": "OSC message arguments",
        "items": {
          "type": ["string", "number", "boolean"]
        }
      },
      "pluginID": {
        "type": "string",
        "description": "Target plugin ID (e.g., TR1, TR2)"
      }
    },
    "required": ["address", "pluginID"]
  }
}
```

### AppleScript Agent Tools

```json
{
  "name": "setTrackVolume",
  "description": "Set the volume of a Logic Pro track",
  "parameters": {
    "type": "object",
    "properties": {
      "trackName": {
        "type": "string",
        "description": "Name of the track (e.g., 'Lead Vocals')"
      },
      "volumeDB": {
        "type": "number",
        "description": "Volume in dB (-60 to +6)",
        "minimum": -60,
        "maximum": 6
      }
    },
    "required": ["trackName", "volumeDB"]
  }
}
```

### Calculations Agent Tools

```json
{
  "name": "suggestEQAdjustments",
  "description": "Analyze a frequency spectrum and suggest EQ adjustments",
  "parameters": {
    "type": "object",
    "properties": {
      "spectrum": {
        "type": "object",
        "description": "Frequency spectrum data",
        "properties": {
          "low": {"type": "number"},
          "lowMid": {"type": "number"},
          "highMid": {"type": "number"},
          "high": {"type": "number"}
        }
      },
      "trackType": {
        "type": "string",
        "description": "Type of track (vocals, kick, snare, bass, etc.)",
        "enum": ["vocals", "kick", "snare", "bass", "guitar", "synth", "other"]
      }
    },
    "required": ["spectrum"]
  }
}
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-12 | AI Assistant | Initial planning document |

---

**END OF DOCUMENT**
