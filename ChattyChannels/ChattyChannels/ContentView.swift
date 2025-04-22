// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/ContentView.swift

/// ContentView provides the main user interface for the ChattyChannels app.
///
/// This view presents a chat-style interface that allows the user to interact with
/// the AI assistant. It displays the chat history and provides a text field for
/// sending new messages.
import SwiftUI
import os.log

/// The main view of the ChattyChannels app.
///
/// ContentView presents a chat interface for interacting with the AI assistant.
/// It displays messages from both the user and the AI, and provides a text input
/// field for sending new messages.
struct ContentView: View {
    /// The model that manages chat messages and state.
    @StateObject private var chatModel = ChatModel()
    
    /// The service for communicating with the AI.
    @EnvironmentObject private var networkService: NetworkService
    
    /// The current text in the chat input field.
    @State private var chatInput = ""
    
    /// System logger for UI-related events.
    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "UI")
    
    /// The view's body, defining the user interface layout and behavior.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                ScrollViewReader { scrollView in
                    ZStack {
                        // Background that fills entire scroll area
                        Color(NSColor.windowBackgroundColor).opacity(0.9)
                            .ignoresSafeArea()
                        
                        // Messages container
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(chatModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            // Spacer to push content to the top when there are few messages
                            if !chatModel.messages.isEmpty {
                                Spacer(minLength: 20)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
                    }
                    .onChange(of: chatModel.messages.count) { _, _ in
                        withAnimation {
                            scrollView.scrollTo(chatModel.messages.last?.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
            .padding([.top, .leading, .trailing])
            .padding(.trailing, 8) // Extra padding for scrollbar
            
            // Loading indicator
            if chatModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing)
                }
                .padding(.top, 4)
            }
            
            // Text input field
            GrowingTextInput(text: $chatInput, onSubmit: sendChat)
                .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            logger.info("Control Room UI loaded")
            chatModel.loadChatHistory()
        }
    }
    
    /// Sends the current chat input to the AI and processes the response.
    ///
    /// This method is triggered when the user submits a message. It:
    /// 1. Validates that the input is not empty
    /// 2. Creates a message from the user's input and adds it to the chat history
    /// 3. Sends the message to the NetworkService to get an AI response
    /// 4. Adds the AI's response to the chat history
    /// 5. Handles any errors that occur during the process
    private func sendChat() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("Empty chat input ignored")
            return
        }
        
        let userMessage = ChatMessage(source: "You", text: chatInput, timestamp: Date())
        chatModel.addMessage(userMessage)
        logger.info("User sent: \(chatInput)")
        
        Task {
            do {
                // Use injected networkService and correct function name
                let response = try await networkService.sendMessage(chatInput)
                let producerMessage = ChatMessage(source: "Producer", text: response, timestamp: Date())
                await MainActor.run {
                    chatModel.addMessage(producerMessage)
                    logger.info("Producer replied: \(response)")
                }
            } catch {
                logger.error("Chat failed: \(error.localizedDescription)")
                let errorMessage = ChatMessage(source: "Producer", text: "Oops, something went wrong: \(error.localizedDescription)", timestamp: Date())
                await MainActor.run {
                    chatModel.addMessage(errorMessage)
                }
            }
        }
        chatInput = ""
    }
}

#Preview {
    ContentView()
        .environmentObject(NetworkService()) // Provide dummy service for preview
}
