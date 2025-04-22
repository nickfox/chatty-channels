// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/MessageBubble.swift

import SwiftUI

/// A view that displays a single message in a chat-like bubble.
///
/// This component handles the visual representation of a message, including
/// its sender information, timestamp, and content.
struct MessageBubble: View {
    /// The message to display
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: sender name and timestamp
            HStack(spacing: 8) {
                // Sender name with color coding
                Text(message.source)
                    .foregroundColor(getSenderColor())
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                // Timestamp
                Text(getFormattedTimestamp())
                    .foregroundColor(.gray.opacity(0.5))
                    .font(.system(size: 11))
            }
            .padding(.bottom, 2)
            .padding(.horizontal, 16)
            
            // Message content
            VStack(alignment: .leading, spacing: 8) {
                // The actual message text
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.messageText.opacity(0.9))
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(getMessageBackground())
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    /// Returns the appropriate color for the sender name based on sender type
    /// - Returns: Color to use for the sender's name
    private func getSenderColor() -> Color {
        switch message.source {
        case "You":
            return Color.userColor    // Cyan for user
        case "Producer":
            return Color.assistantColor  // Magenta for assistant
        default:
            return Color.gray.opacity(0.8)
        }
    }
    
    /// Returns the appropriate background color for the message bubble
    /// - Returns: Color to use for the message background
    private func getMessageBackground() -> Color {
        return Color.messageBubble
    }
    
    /// Returns a formatted timestamp string from the message's date
    /// - Returns: Formatted timestamp string
    private func getFormattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma MMM d, yyyy"
        let formatted = formatter.string(from: message.timestamp)
        return formatted.replacingOccurrences(of: "AM", with: "\u{2009}am ")
                      .replacingOccurrences(of: "PM", with: "\u{2009}pm ")
    }
}

#Preview {
    VStack {
        MessageBubble(message: ChatMessage(
            source: "Producer",
            text: "Hello, how can I help you today?",
            timestamp: Date()
        ))
        
        MessageBubble(message: ChatMessage(
            source: "You",
            text: "I need help with my audio mix",
            timestamp: Date()
        ))
    }
    .padding()
    .background(Color.customBackground)
}
