# /Users/nickfox137/Documents/roo-code-memory-bank/memory-bank/systemPatterns.md
# System Patterns *Optional*

This file documents recurring patterns and standards used in the project.
It is optional, but recommended to be updated as the project evolves.
2025-04-11 15:01:13 - Initial Memory Bank setup.
2025-04-11 17:44:40 - Added architectural patterns: Cross-Plugin Analysis, AI-Driven Balancing, NL-to-MIDI Generation (V2+), Centralized Hub, Role-Based Agents.
2025-04-11 19:52:24 - Added NVFE Mixing Methodology as a core architectural pattern for V2+.

*

## Coding Patterns

*   

## Architectural Patterns

*   **[V2+ Roadmap] Cross-Plugin Analysis for Dynamic Mixing:**
    *   *Description:* Plugins (`AIplayer`, Bus AIs) perform local audio analysis (e.g., FFT) and report key metrics (e.g., spectral peaks) via OSC to a central coordinator (`AIproducer` Swift app). The coordinator analyzes data from multiple plugins to detect issues like frequency masking.
    *   *Rationale:* Enables system-wide awareness for intelligent mixing decisions (e.g., unmasking kick/bass) that individual plugins cannot make in isolation.
    *   *Implementation:* Requires defined OSC messages for spectral data, analysis logic in the Swift app (potentially guided by LLM), and command routing back to plugins for EQ adjustments. Inspired by iZotope Neutron's unmasking.
*   **[V2+ Roadmap] AI-Driven Spectral Balancing:**
    *   *Description:* Plugins use local spectral analysis combined with LLM guidance (based on user prompts and potentially instrument profiles) to apply intelligent EQ adjustments for tonal balance.
    *   *Rationale:* Automates complex EQ tasks, providing a starting point for balanced sound tailored to the instrument's role. Inspired by Sonible Smart:EQ.
    *   *Implementation:* Plugins perform FFT, send context to `AIproducer`, LLM suggests EQ settings, plugin applies them via internal DSP.
*   **[V2+ Roadmap] Natural Language to MIDI Generation:**
    *   *Description:* User provides chat prompts describing desired musical parts (e.g., "funky bassline"). The `AIproducer` app uses an LLM to interpret the request and generate structured instructions (e.g., note patterns, rhythms). These instructions are sent via OSC to the relevant plugin (`AIplayer`, `AIdrummer`), which then generates the corresponding MIDI events within Logic Pro.
    *   *Rationale:* Bridges the gap between high-level creative ideas expressed in natural language and concrete musical output in the DAW. Inspired by Logic's Session Players but made interactive and flexible via chat.
    *   *Implementation:* Requires robust LLM prompting for musical interpretation, defined OSC format for MIDI instructions, and MIDI generation capabilities within JUCE plugins.
*   **[V1+] Centralized Control Hub (Swift App):**
    *   *Description:* A native macOS Swift app (`AIproducer`) acts as the central coordinator for the system. It manages communication (OSC hub), interacts with external LLM APIs, executes project-level Logic control (AppleScript), and potentially hosts shared state or logic.
    *   *Rationale:* Separates concerns, keeping audio plugins focused on DSP/MIDI while the Swift app handles orchestration, external services, and host interaction. Leverages native macOS capabilities.
*   **[V1+] Role-Based AI Agents:**
    *   *Description:* The system is composed of distinct AI agents, each with a specific role (`AIproducer`, `AIplayer`, `AIdrummer`, `AIeffects`, `AIengineer`) implemented as separate software components (Swift app or JUCE plugins).
    *   *Rationale:* Simulates a real studio workflow, provides clear separation of responsibilities, and allows for tailored AI behavior and prompts for each role.
*   **[V2+ Roadmap] Nichols Vocal Flow Engine (NVFE) Mixing Methodology:**
    *   *Description:* A structured mixing process adapted from Roger Nichols' techniques, guiding AI agents (`AIProducer`, `AIEngineer`) through EQ balance, compression, level setting, and reverb application using precision checks (0.2dB audibility) and defined workflows.
    *   *Rationale:* Embeds expert mixing knowledge into the AI, promoting consistent, high-quality results aligned with professional standards. Provides a clear framework for AI decision-making in mixing tasks.
    *   *Implementation:* Defined in `nvfe.txt` using hybrid text/Mermaid format. Logic will be integrated into AI agent prompts and decision trees (V2+). Requires coordination between `AIProducer`, `AIEngineer`, `AI Musicians`, `AIplayer`, and `AIeffects`.

## Testing Patterns

*