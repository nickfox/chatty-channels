// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/ChatModel.swift

/// ChatModel provides state management and persistence for the chat interaction.
///
/// This model is responsible for storing chat messages, managing chat state,
/// and providing persistence for chat history through JSON serialization.
import Foundation
import os.log

/// Represents a single message in the chat conversation.
///
/// Each message contains metadata about its source (user or AI), content, and timing.
/// Messages are uniquely identifiable and support serialization for persistence.
struct ChatMessage: Codable, Identifiable {
    /// Unique identifier for the message.
    var id: UUID
    
    /// The origin of the message (e.g., "You" or "Producer").
    let source: String
    
    /// The content of the message.
    let text: String
    
    /// When the message was created.
    let timestamp: Date
    
    init(source: String, text: String, timestamp: Date) {
        self.id = UUID()
        self.source = source
        self.text = text
        self.timestamp = timestamp
    }
}

/// Manages the chat conversation state and persistence.
///
/// ChatModel is responsible for managing the collection of chat messages,
/// providing loading and saving functionality, and tracking the loading state.
/// It conforms to ObservableObject to support SwiftUI's state management system.
class ChatModel: ObservableObject {
    /// The collection of chat messages in chronological order.
    @Published private(set) var messages: [ChatMessage] = []
    
    /// Indicates whether a network request is in progress.
    @Published private(set) var isLoading = false
    
    /// System logger for model-related events.
    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "ChatModel")
    /// The file URL where chat history is persisted.
    ///
    /// This URL is constructed using the ProjectDataDirectory specified in Config.plist.
    private let fileURL: URL = {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let projectDataDir = config["ProjectDataDirectory"] as? String,
              !projectDataDir.isEmpty else {
            // Log error and crash if config is missing or invalid - essential for operation
            let errorMsg = "FATAL ERROR: Could not load 'ProjectDataDirectory' from Config.plist. Please ensure the key exists and has a valid path string."
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "unknown", category: "ChatModel").critical("\(errorMsg)")
            fatalError(errorMsg)
        }

        // Ensure the directory exists (though it should, being the project dir)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: projectDataDir) {
             Logger(subsystem: Bundle.main.bundleIdentifier ?? "unknown", category: "ChatModel").warning("ProjectDataDirectory specified in Config.plist does not exist: \(projectDataDir)")
             // Proceed anyway, writing the file might create intermediate dirs if possible, or fail later.
        }

        // Construct the final URL
        return URL(fileURLWithPath: projectDataDir).appendingPathComponent("chatHistory.json")
    }()
    
    /// Adds a new message to the chat history and persists it.
    ///
    /// - Parameter message: The message to add to the conversation history.
    func addMessage(_ message: ChatMessage) {
        DispatchQueue.main.async {
            self.messages.append(message)
            self.saveChatHistory()
            
            // If the message is from the user, set isLoading to true
            if message.source == "You" {
                self.isLoading = true
            } else {
                // When receiving a response, set isLoading to false
                self.isLoading = false
            }
        }
    }
    
    /// Loads the chat history from persistent storage.
    ///
    /// This method attempts to load the chat history from the JSON file at `fileURL`.
    /// If the file doesn't exist or contains invalid data, it will leave the messages array empty.
    func loadChatHistory() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No chat history found at \(self.fileURL.path)")
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            logger.info("Loaded \(self.messages.count) messages from \(self.fileURL.path)")
        } catch {
            logger.error("Failed to load chat history: \(error.localizedDescription)")
        }
    }
    
    /// Saves the current chat history to persistent storage.
    ///
    /// This method serializes the messages array to JSON and writes it to the file at `fileURL`.
    /// It uses atomic writing to prevent data corruption in case of system crashes.
    private func saveChatHistory() {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Saved \(self.messages.count) messages to \(self.fileURL.path)")
        } catch {
            logger.error("Failed to save chat history: \(error.localizedDescription)")
        }
    }
}
