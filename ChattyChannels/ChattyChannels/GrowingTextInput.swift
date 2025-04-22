// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/GrowingTextInput.swift

import SwiftUI
import AppKit

/// A text input field that grows in height as the user types additional lines.
///
/// This component provides a multi-line text input that automatically expands
/// to accommodate additional content, up to a maximum height.
struct GrowingTextInput: View {
    /// The text being edited
    @Binding var text: String
    
    /// Callback triggered when the user submits the text
    let onSubmit: () -> Void
    
    /// Current height of the text editor
    @State private var textEditorHeight: CGFloat = 60
    
    /// The maximum height the text editor can grow to
    private let maxHeight: CGFloat = 140
    
    /// The minimum height of the text editor
    private let minHeight: CGFloat = 60
    
    /// Estimated height per line of text
    private let lineHeight: CGFloat = 20
    
    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .background(.clear)
            .frame(height: textEditorHeight)
            .padding(12)
            .background(Color.messageBubble)
            .foregroundColor(.messageText)
            .font(.system(size: 15))
            .cornerRadius(10)
            .onChange(of: text) { _, newText in
                // Calculate height based on line count
                let lineCount = newText.components(separatedBy: .newlines).count
                textEditorHeight = min(max(minHeight, CGFloat(lineCount * Int(lineHeight))), maxHeight)
            }
            .onKeyPress(.return, phases: .down) { keyPress in
                // Submit on Return/Enter (without Shift key)
                if !keyPress.modifiers.contains(.shift) {
                    onSubmit()
                    return .handled
                }
                return .ignored
            }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var text = "Hello, world!"
        var body: some View {
            GrowingTextInput(text: $text, onSubmit: {})
                .padding()
                .frame(width: 400)
        }
    }
    return PreviewWrapper()
}
