# /Users/nickfox137/Documents/roo-code-memory-bank/memory-bank/decisionLog.md
# Decision Log

This file records architectural and implementation decisions using a list format.
2025-04-11 15:01:09 - Initial Memory Bank setup.
2025-04-11 17:44:22 - Logged key architectural decisions: Hybrid architecture, OSC, External LLMs, AppleScript, V1 Scope, AI Roles, V2+ Features.

*

## Decision [2025-04-11]
Adopt a hybrid architecture combining a native Swift macOS app (`AIproducer`) with cross-platform JUCE AU plugins (`AIplayer`, `AIdrummer`, etc.).

## Rationale
Leverages Swift's tight macOS integration (AppleScript, native UI) for the central control app and JUCE's robustness for audio processing and cross-DAW compatibility in the plugins. Balances native feel with audio plugin standards.

## Implementation Details
*   `AIproducer`: SwiftUI app, handles LLM calls, OSC hub, AppleScript execution.
*   Plugins: C++ with JUCE framework, handle audio/MIDI processing, local analysis (V2+), communicate via OSC.

---

## Decision [2025-04-11]
Use OSC (Open Sound Control) for inter-process communication between the `AIproducer` Swift app and the JUCE plugins.

## Rationale
OSC is a standard, lightweight protocol suitable for real-time control data between music applications. Libraries exist for both Swift (SwiftOSC) and C++/JUCE.

## Implementation Details
*   Swift app acts as OSC server/client hub.
*   Plugins act as OSC clients/servers, sending analysis data and receiving commands.
*   Define clear OSC address patterns (e.g., `/player/kick/spectrum`, `/producer/command/eq`).

---

## Decision [2025-04-11]
Utilize external LLM APIs (starting with Gemini) for AI capabilities, accessed via the `AIproducer` Swift app.

## Rationale
Leverages powerful cloud-based models without requiring local LLM hosting. Allows flexibility to switch providers later. Centralizing calls in the Swift app keeps plugins lightweight.

## Implementation Details
*   `NetworkService.swift` handles API calls (URLSession).
*   API keys stored securely in `Config.plist` (excluded from Git).
*   Modular design to allow future integration of Ollama, Grok, ChatGPT, Claude.

---

## Decision [2025-04-11]
Control Logic Pro project-level actions (e.g., track creation) using AppleScript executed from the `AIproducer` Swift app.

## Rationale
Provides a way to manipulate Logic's project structure, which AU plugins cannot do directly. AppleScript is the standard mechanism for macOS automation.

## Implementation Details
*   Use `NSAppleScript` or `osascript` via `Process` in Swift.
*   Define specific AppleScript commands for needed actions (create track, set instrument, etc.).

---

## Decision [2025-04-11]
Define V1 scope to focus *only* on the `AIproducer` Swift app ("Control Room").

## Rationale
Establishes a manageable first iteration to validate the core chat functionality, Gemini integration, and state persistence before tackling complex plugin development and OSC communication. Reduces initial risk.

## Implementation Details
*   V1 deliverables: SwiftUI app, Gemini API connection, chat history save/load.
*   Plugin development (`AIplayer`, etc.), OSC, AppleScript integration, advanced features (unmasking, balancing, MIDI) deferred to V2+.

---

## Decision [2025-04-11]
Establish distinct roles for AI agents (`AIproducer`, `AIplayer`/Bus AIs, `AIeffects`, `AIengineer`) to simulate a studio crew.

## Rationale
Enhances the "studio realism" concept, provides clear separation of concerns, and allows for tailored AI prompts and behaviors for each role.

## Implementation Details
*   Roles defined in `productContext.md`.
*   Each role corresponds to a specific app component (Swift app or JUCE plugin type).
*   Prompts for LLM will be tailored to each role's responsibilities.

---

## Decision [2025-04-11]
Document advanced `AIplayer`/Bus AI features (Neutron-style unmasking, Smart:EQ-style balancing, chat-driven MIDI generation) for the V2+ roadmap.

## Rationale
Captures valuable brainstorming ideas and feature enhancements for future iterations without expanding the V1 scope. Provides clear direction for subsequent development phases.

## Implementation Details
*   Features detailed in `productContext.md` and potentially `systemPatterns.md`.
*   Requires significant additions to plugin DSP/analysis capabilities and Swift app logic in V2+.

---

## Decision [2025-04-11]
Adopt the Nichols Vocal Flow Engine (NVFE), based on Roger Nichols' mixing methodology, as the core framework for AI-driven mixing decisions within Chatty Channels.

## Rationale
Provides a structured, proven approach to achieving clear and balanced mixes, aligning with the project's goal of high-quality audio output. Enhances the "studio realism" by embedding expert engineering knowledge into the AI agents (`AIProducer`, `AIEngineer`). The hybrid text/Mermaid format defined in `nvfe.txt` balances detailed instruction with visual clarity.

## Implementation Details
*   The NVFE logic (steps for EQ, Compression, Levels, Reverb with 0.2dB checks and interaction rules) will be integrated into the prompts and decision-making processes of `AIProducer` and `AIEngineer` (V2+).
*   AI agents will use NVFE to generate instructions for `AIplayer`/Bus AIs and `AIeffects`.
*   The instruction set is documented separately in `nvfe.txt` and referenced in `systemPatterns.md`.

---

## Decision [2025-04-12]
Define communication flow and components for AIplayer v0.3 (Plugin <-> Swift App <-> LLM interaction).

## Rationale
To enable the AIplayer plugin to leverage the AIproducer Swift app's connection to the Gemini LLM for chat functionality, establishing a clear communication protocol and identifying necessary components is required.

## Implementation Details
*   **Protocol:** OSC (as previously decided).
*   **Flow:** Plugin UI -> Plugin Processor (OSC Send) -> Swift App (OSC Receive, LLM Call) -> Gemini -> Swift App (OSC Send) -> Plugin Processor (OSC Receive) -> Plugin UI.
*   **Plugin Components (v0.3):**
    *   Simple Chat UI (`PluginEditor`).
    *   Processor <-> Editor communication (e.g., ValueTree).
    *   `juce::OSCReceiver` implementation (`PluginProcessor`).
    *   `juce::OSCSender` usage refinement (`PluginProcessor`).
*   **Swift App Components (v0.3):**
    *   OSC Receiver implementation (e.g., SwiftOSC).
    *   OSC Sender implementation.
    *   Logic to route OSC messages to/from `NetworkService` (Gemini).
    *   Mechanism to manage plugin instances and route responses.
*   **Instance Strategy:** Use Instance ID + Predictable Ports (Plugins listen starting at 9000, include unique ID in requests; Swift app maps ID to port for responses).
*   **OSC Scheme (Preliminary):**
    *   Plugin -> Swift: `/aiplayer/chat/request` (Args: `int` instanceID, `string` userMessage)
    *   Swift -> Plugin: `/aiplayer/chat/response` (Args: `string` geminiResponse)
*   **Ports (Initial):**
    *   Plugin Sends Requests TO: `127.0.0.1:9001` (Swift App Listener)
    *   Plugin Listens for Responses ON: Port `9000` (Swift App Sends To This Port)

---

## Decision [2025-04-14]
Select `OSCKit` as the Swift OSC library and finalize AIproducer OSC parameters.

## Rationale
`OSCKit` (`https://github.com/orchetect/OSCKit.git`) appears to be a modern, well-maintained Swift library suitable for OSC communication, unlike previously considered options. Finalizing parameters enables implementation.

## Implementation Details
*   **Library:** `OSCKit` added via Swift Package Manager.
*   **AIproducer Listen Port:** `9001` (UDP)
*   **AIproducer Send Port:** `9000` (UDP) - Target for AIplayer plugins.
*   **Incoming Message:** `/aiplayer/chat/request` (Args: `int` instanceID, `string` userMessage)
*   **Outgoing Message:** `/aiplayer/chat/response` (Args: `string` geminiResponse)
*   **Service:** Implement logic within `OSCService.swift`.