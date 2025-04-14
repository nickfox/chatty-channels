//
//  ChattyChannelsApp.swift
//  ChattyChannels
//
//  Created by Nick on 4/1/25.
//

import SwiftUI
import Combine // Needed for managing subscriptions
import OSLog    // For logging

@main
struct ChattyChannelsApp: App {
    // Create instances of the services as StateObjects
    @StateObject private var oscService = OSCService()
    @StateObject private var networkService = NetworkService()

    // Logger
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "App")

    // Store cancellables for Combine subscriptions
    @State private var cancellables = Set<AnyCancellable>()

    var body: some Scene {
        WindowGroup {
            // Pass services to ContentView if needed (e.g., via environment)
            // For now, ContentView doesn't need them directly for this logic
            ContentView()
                .environmentObject(networkService) // Inject the service
                .task { // Use .task for async setup tied to the Scene lifecycle
                    setupServiceSubscription()
                }
        }
    }

    // Function to set up the subscription pipeline
    private func setupServiceSubscription() {
        logger.info("Setting up OSCService to NetworkService subscription.")

        oscService.chatRequestPublisher
            .sink { request in // Remove [weak self] for struct
                // No need for guard let self = self with structs
                self.logger.info("Received chat request via OSC: ID=\(request.instanceID), Msg='\(request.userMessage)'")

                // Call NetworkService asynchronously
                Task {
                    do {
                        self.logger.debug("Sending message to NetworkService...")
                        let aiResponse = try await self.networkService.sendMessage(request.userMessage)
                        self.logger.info("Received AI response: '\(aiResponse)'")

                        // Send response back via OSCService
                        self.oscService.sendResponse(message: aiResponse)

                    } catch {
                        self.logger.error("Error during AI request or OSC response: \(error.localizedDescription)")
                        // Optionally send an error message back via OSC
                        self.oscService.sendResponse(message: "Error: Could not process request.")
                    }
                }
            }
            .store(in: &cancellables) // Store subscription to keep it alive

        logger.info("Subscription setup complete.")
    }
}
