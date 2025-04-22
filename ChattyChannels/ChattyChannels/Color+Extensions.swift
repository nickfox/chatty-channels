// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/Color+Extensions.swift

import SwiftUI
import AppKit

/// Extensions to the Color struct to provide consistent colors across the application.
extension Color {
    /// The primary background color that matches the system window background
    static var customBackground: Color {
        Color(NSColor.windowBackgroundColor)
    }
    
    /// Used for message bubbles
    static var messageBubble: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.4)
    }
    
    /// Secondary background color for alternate areas
    static var secondaryBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }
    
    /// Text background color
    static var tertiaryBackground: Color {
        Color(NSColor.textBackgroundColor)
    }
    
    /// Standard text color for normal text content
    static var messageText: Color {
        Color(NSColor.labelColor)
    }
    
    /// Secondary text color for less important information
    static var secondaryText: Color {
        Color(NSColor.secondaryLabelColor)
    }
    
    /// User message indicator color
    static var userColor: Color {
        Color(red: 0.0, green: 0.8, blue: 1.0, opacity: 0.7) // Cyan
    }
    
    /// Assistant message indicator color
    static var assistantColor: Color {
        Color(red: 1.0, green: 0.2, blue: 0.7, opacity: 0.5) // Magenta
    }
}
