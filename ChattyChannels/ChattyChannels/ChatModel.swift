/// ChatModel.swift
/// ChattyChannels
///
/// State-only version — all on-disk persistence removed but API surface is kept
/// so existing views compile without change.
import Foundation
import os.log

// MARK: - ChatMessage

/// Represents a single message in the chat conversation.
struct ChatMessage: Codable, Identifiable {
    /// Unique identifier for the message.
    var id: UUID = UUID()                // var allows decoding if we restore persistence later
    /// The origin of the message (e.g., "You" or "Producer").
    let source: String
    /// The content of the message.
    let text: String
    /// When the message was created.
    let timestamp: Date

    init(source: String, text: String, timestamp: Date = .init()) {
        self.source = source
        self.text = text
        self.timestamp = timestamp
    }
}

// MARK: - ChatModel

/// Observable view‑model that stores chat messages and loading state.
///
/// NOTE: Filesystem persistence is **disabled**. Both `loadChatHistory()` and
/// `saveChatHistory()` are retained as no‑ops so existing callers build.
final class ChatModel: ObservableObject {
    /// Chronological collection of chat messages.
    @Published private(set) var messages: [ChatMessage] = []
    /// Indicates whether an outbound network request is in progress.
    @Published private(set) var isLoading: Bool = false

    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "ChatModel")

    // MARK: ‑ Lifecycle

    init() {
        logger.debug("ChatModel initialised (no persisted history)")
    }

    // MARK: ‑ Public API

    /// Appends a message to the conversation.
    func addMessage(_ message: ChatMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.messages.append(message)
            self.logger.debug("Added message from \(message.source, privacy: .public)")
            self.isLoading = (message.source == "You")
            self.saveChatHistory() // no‑op
        }
    }

    /// Clears the in‑memory history.
    func resetHistory() {
        messages.removeAll()
        isLoading = false
        logger.debug("Chat history reset")
    }

    // MARK: ‑ Stubbed persistence (no‑ops)

    /// Placeholder – does nothing while persistence is disabled.
    func loadChatHistory() {
        logger.debug("loadChatHistory() called – persistence disabled")
    }

    /// Placeholder – does nothing while persistence is disabled.
    private func saveChatHistory() {
        // Intentionally left blank.
    }
}

