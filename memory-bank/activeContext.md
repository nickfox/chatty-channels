# /Users/nickfox137/Documents/roo-code-memory-bank/memory-bank/activeContext.md
# Active Context

  This file tracks the project's current status, including recent changes, current goals, and open questions.
  2025-04-11 15:01:00 - Initial Memory Bank setup.
  2025-04-11 17:44:02 - Updated focus to V1 AIproducer app, logged recent decisions and V2+ roadmap items.
  2025-04-11 19:51:15 - Logged definition of NVFE and added to V2+ considerations.

*

## Current Focus

*   **V1 Implementation:** Develop the `AIproducer` Swift macOS application ("Control Room"). This includes:
    *   Building the chat UI (SwiftUI).
    *   Integrating with the Gemini API (`gemini-2.5-pro-exp-03-25`).
    *   Implementing chat history saving and loading (`chatHistory.json`).
    *   Ensuring production quality (error handling, logging, secure API key management, sandbox entitlements).

## Recent Changes

*   **[2025-04-11]** Defined the full "Chatty Channels" vision, including the AI crew roles (`AIproducer`, `AIplayer`/Bus AIs, `AIeffects`, `AIengineer`).
*   **[2025-04-11]** Established V1 scope: Focus solely on the `AIproducer` Swift app.
*   **[2025-04-11]** Detailed advanced features for `AIplayer`/Bus AIs (unmasking, balancing, MIDI generation) and added them to the V2+ roadmap.
*   **[2025-04-11]** Confirmed technology stack: Swift for `AIproducer`, JUCE for plugins, OSC for communication, AppleScript for Logic control, external LLM APIs.
*   **[2025-04-11]** Resolved initial Gemini API connection issues (model name, sandbox entitlements).
*   **[2025-04-11]** Defined the Nichols Vocal Flow Engine (NVFE) based on Roger Nichols' mixing advice, using a hybrid text/Mermaid format. Added to V2+ roadmap for integration into `AIProducer` and `AIEngineer`. (See `nvfe.txt` and `systemPatterns.md`).

## Open Questions/Issues

*   None currently identified for V1 scope. Future considerations for V2+ include plugin architecture details, OSC protocol design, specific algorithms for unmasking/balancing, and NVFE implementation details within the AI agents.