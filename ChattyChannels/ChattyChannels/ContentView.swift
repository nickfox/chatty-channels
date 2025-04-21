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
        VStack(spacing: 10) {
            Text("Control Room")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(chatModel.messages) { message in
                        Text("\(message.source): \(message.text)")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(message.source == "You" ? Color.teal.opacity(0.2) : Color.gray.opacity(0.2))
                            .cornerRadius(5)
                            .frame(maxWidth: .infinity, alignment: message.source == "You" ? .trailing : .leading)
                    }
                }
                .padding(.horizontal)
            }
            
            HStack {
                TextField("Chat with Producer", text: $chatInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.send)
                    .onSubmit { sendChat() }
                    .disabled(chatModel.isLoading)
                
                if chatModel.isLoading {
                    ProgressView()
                }
            }
            .padding(.horizontal)
        }
        .frame(width: 350, height: 400)
        .background(Color.black.opacity(0.9))
        .cornerRadius(10)
        .shadow(radius: 5)
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
        guard !chatInput.isEmpty else {
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
