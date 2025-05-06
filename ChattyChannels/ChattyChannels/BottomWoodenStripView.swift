// BottomWoodenStripView.swift
//
// A test view to isolate and debug the wooden strip component at bottom of the app

import SwiftUI
import os.log

/// A view with a wooden strip at the bottom rather than top for debugging
struct BottomWoodenStripView: View {
    /// The service that provides audio level data
    @EnvironmentObject private var networkService: NetworkService
    
    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "Debug")
    
    var body: some View {
        VStack(spacing: 0) {
            // Normal VU meter content at top (leave intact)
            VUMeterView(levelService: LevelMeterService(oscService: OSCService()))
                .frame(height: 200)
            
            // Main chat content (leave intact)
            Spacer()
            
            // Debug text in the middle
            Text("WOODEN STRIP TEST - SHOULD BE AT BOTTOM")
                .font(.headline)
                .foregroundColor(.white)
                .padding()
            
            // Wooden strip at BOTTOM instead of top
            Rectangle()
                .fill(Color(red: 0.82, green: 0.53, blue: 0.18)) // Honey color
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .border(Color.black.opacity(0.5), width: 2)
                .overlay(
                    Text("BOTTOM WOODEN STRIP")
                        .font(.headline)
                        .foregroundColor(.black)
                )
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            logger.info("DEBUG: BottomWoodenStripView loaded")
            print("DEBUG: BottomWoodenStripView appeared")
        }
        .accessibilityIdentifier("BottomWoodenStripView")
    }
}

#Preview {
    BottomWoodenStripView()
        .environmentObject(NetworkService())
}
