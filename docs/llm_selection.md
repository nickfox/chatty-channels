# Plan: Implementing Multi-LLM Provider Support in ChattyChannels

**Date:** 2025-05-07

**Goal:** Refactor `NetworkService.swift` and related components to support multiple LLM providers (OpenAI, Gemini, Claude, Grok), allowing easy switching between them.

**Core Idea:** Introduce a protocol (e.g., `LLMProvider`) that defines a common interface for sending requests and receiving responses. Create concrete classes for each LLM that implement this protocol. `NetworkService` will then use an instance of the selected `LLMProvider`.

---

## Phase 1: Design and Abstraction

1.  **Define `LLMProvider` Protocol:**
    *   This protocol will declare the essential methods, primarily a function similar to the current `sendMessage`, but generalized.
    *   It might also include properties or methods for provider-specific configurations if needed.
    *   Example:
        ```swift
        protocol LLMProvider {
            func sendMessage(_ input: String, systemPrompt: String) async throws -> String
        }
        ```

2.  **Define Common Request/Response Structures (or adapt existing ones):**
    *   Each `LLMProvider` implementation will manage its own DTOs internally. The `LLMProvider` protocol's `sendMessage` will return a simple `String` (the assistant's reply).

3.  **API Key Management Strategy:**
    *   `Config.plist` will store API keys for all providers:
        *   `openaiApiKey`
        *   `geminiApiKey`
        *   `claudeApiKey`
        *   `grokApiKey`
    *   The `loadApiKey()` method in `NetworkService` (or logic within each provider) will fetch the correct key.

4.  **Provider Selection Mechanism:**
    *   Initially, use a setting in `Config.plist` (e.g., `activeLLMProvider: "Gemini"`) to determine the active provider.

5.  **System Prompt Handling:**
    *   Start by using the existing `systemInstruction` (for JSON parameter control) for all providers, passing it as-is. Future enhancements can allow provider-specific prompts.

---

## Phase 2: Implementation - Provider by Provider

For each provider (OpenAI, Gemini, Claude, Grok):

1.  **Create Provider-Specific DTOs:**
    *   Define `struct`s for request and response bodies specific to that provider's API.

2.  **Create `LLMProvider` Implementation:**
    *   Create a new Swift file for each provider (e.g., `OpenAIProvider.swift`, `GeminiProvider.swift`, `ClaudeProvider.swift`, `GrokProvider.swift`).
    *   Each class will:
        *   Conform to the `LLMProvider` protocol.
        *   Implement `sendMessage()`, handling provider-specific request construction, HTTP calls, headers, authentication, and response parsing.
        *   Manage its specific model name(s) and API endpoint URL.
        *   Take its API key via its initializer.

---

## Phase 3: Refactor `NetworkService`

1.  **Modify `NetworkService.swift`:**
    *   Remove direct OpenAI-specific logic.
    *   Hold an instance of the current `LLMProvider`: `private var activeProvider: LLMProvider!`.
    *   **Initialization (`init()`):**
        *   Read the `activeLLMProvider` string from `Config.plist`.
        *   Read the corresponding API key for the active provider.
        *   Instantiate and assign the correct provider class to `activeProvider`.
    *   Remove `modelName` and `endpoint` properties (managed by individual providers).
    *   **`sendMessage(_ input: String)`:**
        *   Delegate the call to `try await activeProvider.sendMessage(input, systemPrompt: self.systemInstruction)`.
        *   The `systemInstruction` (lines 262-273 in the original file) will be a property of `NetworkService` and passed to the active provider.
    *   Move OpenAI-specific DTOs (`OAChatMessage`, `OAChatRequest`, `OAChatResponse`) to `OpenAIProvider.swift`.
    *   The `loadApiKey()` method will be adapted or its logic moved into provider initialization.
    *   The `NetworkError` enum should be used consistently, extended if necessary.

---

## Phase 4: Configuration and Testing

1.  **Update `Config.plist`:**
    *   Add new string keys for `geminiApiKey`, `claudeApiKey`, `grokApiKey`.
    *   Add a string key for `activeLLMProvider` (e.g., initial value "OpenAI" or "Gemini").

2.  **Testing:**
    *   Thoroughly test each provider integration individually.
    *   Test the switching mechanism.
    *   Ensure JSON parsing for parameter control works across all providers.

---

## Mermaid Diagram of the New Architecture

```mermaid
graph LR
    subgraph App
        ContentView --> NetworkService
    end

    subgraph NetworkServiceLayer
        NetworkService -- uses --> CurrentLLMProvider(LLMProvider)
    end

    subgraph LLMProviders
        CurrentLLMProvider <|-- OpenAIProvider
        CurrentLLMProvider <|-- GeminiProvider
        CurrentLLMProvider <|-- ClaudeProvider
        CurrentLLMProvider <|-- GrokProvider
    end

    subgraph Configuration
        NetworkService -- reads --> ConfigPlist[Config.plist (API Keys, ActiveProvider)]
        OpenAIProvider -- reads key --> ConfigPlist
        GeminiProvider -- reads key --> ConfigPlist
        ClaudeProvider -- reads key --> ConfigPlist
        GrokProvider -- reads key --> ConfigPlist
    end

    subgraph ExternalAPIs
        OpenAIProvider -- HTTP --> OpenAI_API[OpenAI API]
        GeminiProvider -- HTTP --> Gemini_API[Gemini API]
        ClaudeProvider -- HTTP --> Claude_API[Claude API]
        GrokProvider -- HTTP --> Grok_API[Grok API]
    end

    style NetworkService fill:#f9f,stroke:#333,stroke-width:2px
    style LLMProvider fill:#ccf,stroke:#333,stroke-width:2px
```

---

## High-Level Instructions for LLM Implementation

1.  **Create `LLMProvider.swift`:** Define the `LLMProvider` protocol:
    ```swift
    protocol LLMProvider {
        init(apiKey: String) // Or handle API key loading internally
        func sendMessage(_ input: String, systemPrompt: String) async throws -> String
    }
    ```
2.  **Refactor `NetworkService.swift`:**
    *   Add `private var activeProvider: LLMProvider!`.
    *   Add `private let systemInstruction: String = """..."""` (copy existing prompt).
    *   Modify `init()`:
        *   Load `activeLLMProviderName` (String) and relevant `apiKey` from `Config.plist`.
        *   Instantiate `activeProvider` based on `activeLLMProviderName` (e.g., `GeminiProvider(apiKey: geminiKey)`).
    *   Modify `sendMessage(_ input: String)` to call `try await activeProvider.sendMessage(input: input, systemPrompt: self.systemInstruction)`.
    *   Remove OpenAI-specific DTOs, `modelName`, `endpoint`, and `loadApiKey()` (or adapt `loadApiKey` to be generic).
3.  **Create `OpenAIProvider.swift`:**
    *   Implement `LLMProvider`.
    *   Include OpenAI DTOs.
    *   Implement `sendMessage` using existing OpenAI logic, configured with API key and model (e.g., "o4-mini" or a configurable model).
4.  **Create `GeminiProvider.swift`:**
    *   Implement `LLMProvider`.
    *   Define Gemini DTOs for `generateContent`.
    *   Implement `sendMessage` for Gemini API (`https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent`).
5.  **Create `ClaudeProvider.swift`:**
    *   Implement `LLMProvider`.
    *   Define Claude DTOs (Anthropic Messages API).
    *   Implement `sendMessage` for Claude API (`https://api.anthropic.com/v1/messages`), handling `x-api-key` header.
6.  **Create `GrokProvider.swift`:**
    *   Implement `LLMProvider`.
    *   Research and define Grok DTOs, endpoint, and authentication.
    *   Implement `sendMessage`.
7.  **Update `Config.plist`:** Add `geminiApiKey`, `claudeApiKey`, `grokApiKey` (all String), and `activeLLMProvider` (String).
8.  **Error Handling:** Ensure `NetworkError` is used or extended.
9.  **Testing:** Unit/integration tests for each provider and switching.