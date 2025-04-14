// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/ChatModel.swift
import Foundation
import os.log

struct ChatMessage: Codable, Identifiable {
    var id: UUID
    let source: String
    let text: String
    let timestamp: Date
    
    init(source: String, text: String, timestamp: Date) {
        self.id = UUID()
        self.source = source
        self.text = text
        self.timestamp = timestamp
    }
}

class ChatModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoading = false
    
    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "ChatModel")
    // Construct path by reading base directory from Config.plist
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
    
    func addMessage(_ message: ChatMessage) {
        DispatchQueue.main.async {
            self.messages.append(message)
            self.saveChatHistory()
        }
    }
    
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
