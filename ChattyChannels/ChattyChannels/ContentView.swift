// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/ContentView.swift
import SwiftUI
import os.log

struct ContentView: View {
    @StateObject private var chatModel = ChatModel()
    @EnvironmentObject private var networkService: NetworkService // Inject NetworkService
    @State private var chatInput = ""
    
    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "UI")
    
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
