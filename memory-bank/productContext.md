# /Users/nickfox137/Documents/roo-code-memory-bank/memory-bank/productContext.md
# Product Context

This file provides a high-level overview of the project and the expected product that will be created. Initially it is based upon projectBrief.md (if provided) and all other available project-related information in the working directory. This file is intended to be updated as the project evolves, and should be used to inform all other modes of the project's goals and context.
2025-04-11 15:00:52 - Initial Memory Bank setup.
2025-04-11 17:43:36 - Updated with Chatty Channels vision, AI crew roles, V1 scope, and V2+ roadmap including advanced AIplayer features (unmasking, balancing, MIDI generation).
2025-04-11 19:50:57 - Added Nichols Vocal Flow Engine (NVFE) as a key feature and mixing methodology for V2+.

*

## Project Goal

*   Develop "Chatty Channels," a suite of AI-powered tools for Logic Pro designed to simulate a collaborative studio environment. The goal is to enhance the music creation and mixing process through natural language interaction with AI agents representing different studio roles (producer, musicians, engineer).

## Key Features

*   **AI Crew:** A set of specialized AI agents:
    *   `AIproducer`: Swift macOS app ("Control Room") acting as session leader, using an external LLM (starting with Gemini).
    *   `AIplayer`/Bus AIs (`AIdrummer`, `AIkeys`, etc.): JUCE AU plugins on tracks/buses acting as "musicians," with chat interfaces.
    *   `AIeffects`: JUCE AU plugin for effects processing, responding to requests.
    *   `AIengineer`: JUCE AU plugin on the master bus for mix polishing.
*   **Chat-Based Interaction:** Users interact with AI agents via natural language through dedicated chat interfaces.
*   **Studio Simulation:** Aims to mimic the workflow and collaboration dynamics of a real recording studio.
*   **Nichols Vocal Flow Engine (NVFE):** A core mixing methodology based on Roger Nichols' techniques, guiding the AI crew (especially `AIProducer` and `AIEngineer`) in achieving balanced and clear mixes using EQ, compression, levels, and reverb with precision. Defined in `nvfe.txt` and documented in `systemPatterns.md`. (V2+ feature integration).
*   **V1 Focus:** Implement the `AIproducer` Swift app with Gemini connectivity and chat state persistence. Plugin development, OSC, and NVFE integration deferred.
*   **(V2+ Roadmap) Advanced AIplayer/Bus AI Capabilities:**
    *   *Neutron-Inspired Unmasking:* Dynamic EQ adjustments based on cross-track frequency analysis to resolve masking issues.
    *   *Smart:EQ-Inspired Balancing:* AI-driven spectral balancing tailored to instrument profiles.
    *   *Chat-Driven MIDI Generation:* Generate MIDI patterns based on natural language prompts, similar to Logic's Session Players but interactive.

## Overall Architecture

*   **Hybrid System:** Combines a native Swift macOS app (`AIproducer`) with cross-platform JUCE AU plugins (`AIplayer`, `AIdrummer`, `AIeffects`, `AIengineer`).
*   **Communication:** OSC protocol used for inter-process communication between the Swift app and JUCE plugins.
*   **AI Backend:** Leverages external LLM APIs (starting with Gemini) via the Swift app for natural language processing and decision-making.
*   **Audio Analysis:** Plugins will perform local audio analysis (FFT, spectral analysis) to inform AI decisions (V2+).
*   **Logic Control:** Swift app uses AppleScript for project-level manipulations (track creation, etc.).