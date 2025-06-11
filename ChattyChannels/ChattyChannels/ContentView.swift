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
    
    // Services injected from ChattyChannelsApp
    @EnvironmentObject private var levelMeterService: LevelMeterService
    @EnvironmentObject private var calibrationService: CalibrationService
    
    /// The current text in the chat input field.
    @State private var chatInput = ""
    
    /// System logger for UI-related events.
    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "UI")
    
    /// The view's body, defining the user interface layout and behavior.
    var body: some View {
        // Wrap everything in a ZStack to put the wooden strip above everything
        ZStack(alignment: .top) {
            // Main content
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Wooden Strip (Neve Console Style)
                    Rectangle()
                        .fill(Color(red: 0.4, green: 0.2, blue: 0.1)) // Base solid dark reddish-brown
                        .frame(height: 23)
                        .frame(maxWidth: .infinity)
                        .border(Color.black.opacity(0.4), width: 0.5)
                        .overlay( // Add subtle grain simulation
                            Canvas { context, size in
                                let grainColor = Color.black.opacity(0.1) // Darker, semi-transparent grain
                                let lineCount = 6 // Increased line count to avoid exact center line
                                let lineHeight: CGFloat = 0.5 // Thickness of grain lines

                                for i in 0..<lineCount {
                                    let yPos = (size.height / CGFloat(lineCount + 1)) * CGFloat(i + 1)
                                    let path = Path { p in
                                        p.move(to: CGPoint(x: 0, y: yPos))
                                        p.addLine(to: CGPoint(x: size.width, y: yPos))
                                    }
                                    context.stroke(path, with: .color(grainColor), lineWidth: lineHeight)
                                }
                            }
                        )

                    // VU Meter component
                    VUMeterView(levelService: levelMeterService)
                        .frame(maxWidth: .infinity) // Ensure VUMeterView takes full available width
                        // Removed fixed height to allow natural sizing
                    
                    // Horizontal divider - Neve console style with padding on sides
                    HStack {
                        Spacer()
                            .frame(width: 20)
                        
                        NeveHorizontalDividerView()
                            .frame(height: 4)
                        
                        Spacer()
                            .frame(width: 20)
                    }
                    .padding(.vertical, 5) // Add some vertical spacing around the divider
                    
                    // Note: As per user request, we've removed the calibration status UI that appeared below the divider
                    // Any calibration errors will now only be logged, not displayed in the UI

                    // Main chat interface
                    VStack(spacing: 0) {
                        ScrollView {
                            ScrollViewReader { scrollView in
                                ZStack {
                                    // Background that fills entire scroll area
                                    Color(red: 40/255, green: 41/255, blue: 44/255) // Xcode dark background
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
                        .background(Color(red: 40/255, green: 41/255, blue: 44/255)) // Xcode dark background
                        .padding(.horizontal, 20) // Consistent horizontal padding
                        
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
                            .padding(.horizontal, 20) // Consistent horizontal padding
                            .padding(.vertical)       // Keep default vertical padding
                    } // End of main chat interface VStack
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(red: 40/255, green: 41/255, blue: 44/255)) // Xcode dark background
        .onAppear {
            logger.info("Control Room UI loaded")
            chatModel.loadChatHistory()
            
            // Log any calibration status changes instead of showing in UI
            if calibrationService.lastCalibrationError != nil {
                logger.error("Calibration error: \(calibrationService.lastCalibrationError ?? "Unknown error")")
            } else if case .completed(let mappedCount, let totalTracks) = calibrationService.calibrationState {
                logger.info("Calibration completed: Mapped \(mappedCount) of \(totalTracks) tracks")
            }
        }
        .onChange(of: calibrationService.calibrationState) { _, newState in
            // Log calibration state changes
            logger.info("Calibration state changed: \(newState.description)")
            
            if case .failed(let error) = newState {
                logger.error("Calibration failed: \(error)")
            }
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
        
        // Store the input in a local variable to ensure it doesn't get cleared before use
        let userInputText = chatInput
        
        let userMessage = ChatMessage(source: "You", text: userInputText, timestamp: Date())
        chatModel.addMessage(userMessage)
        logger.info("User sent: \(userInputText)")
        
        // Clear the input field immediately to improve UI responsiveness
        chatInput = ""
        
        Task {
            do {
                // Use the stored input instead of chatInput which is now empty
                let response = try await networkService.sendMessage(userInputText)
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
    }
}
