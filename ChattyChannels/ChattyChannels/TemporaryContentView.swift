// TemporaryContentView.swift
//
// A temporary replacement for ContentView to debug the wooden strip issue

import SwiftUI
import os.log

/// A temporary replacement view to debug wooden strip rendering
struct TemporaryContentView: View {
    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "Debug")
    
    var body: some View {
        VStack(spacing: 0) {
            // Try with Color instead of Rectangle
            VStack(spacing: 0) {
                Color(red: 0.82, green: 0.53, blue: 0.18) // Honey color direct color view
                    .frame(height: 50)
                    .border(Color.black.opacity(0.7), width: 2) // Thicker border
                    .overlay(
                        Text("COLOR VIEW WOODEN STRIP")
                            .foregroundColor(.black)
                            .font(.system(size: 14, weight: .bold))
                    )
                    .onAppear {
                        print("DEBUG: Color wooden strip appeared")
                    }
                    
                ZStack { // Original Rectangle version
                    Rectangle()
                        .fill(Color(red: 0.82, green: 0.53, blue: 0.18)) // Honey color
                        .frame(height: 50)
                        .border(Color.black.opacity(0.7), width: 2) // Thicker, more visible border
                    
                    // Add debug text directly on the wooden strip to see if it appears
                    Text("RECTANGLE WOODEN STRIP")
                        .foregroundColor(.black)
                        .font(.system(size: 14, weight: .bold))
                }
                .onAppear {
                    print("DEBUG: Rectangle wooden strip appeared")
                }
            }
            
            // Rest of the UI is just a placeholder
            Spacer()
            
            // Bright red debug footer
            Rectangle()
                .fill(Color.red)
                .frame(height: 30)
                .overlay(
                    Text("DEBUG FOOTER")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))
                )
                .onAppear {
                    print("DEBUG: Red debug footer appeared")
                }
            Text("Debug Mode - Testing Wooden Strip")
                .padding()
                .onAppear {
                    print("DEBUG: Debug text appeared")
                }
            Spacer()
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            print("DEBUG: TemporaryContentView appeared")
            logger.info("DEBUG: TemporaryContentView loaded")
        }
        // Add accessibility identifiers for view debugging
        .accessibilityIdentifier("TemporaryContentView")
    }
}

// Preview for SwiftUI canvas
#Preview {
    TemporaryContentView()
}
