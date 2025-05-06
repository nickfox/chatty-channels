// NeveHorizontalDividerView.swift
//
// A SwiftUI view that renders a metallic divider inspired by vintage Neve consoles

import SwiftUI

/// A view that renders a horizontal divider similar to those found on vintage Neve 1073 consoles.
///
/// This view creates a realistic metallic-looking divider that separates different sections
/// of the console interface, mimicking the channel strip divisions on classic recording consoles.
struct NeveHorizontalDividerView: View {
    var body: some View {
        // Simplified metallic divider with strong visual presence
        ZStack {
            VStack(spacing: 0) {
                // Top highlight
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(height: 1)
                
                // Main metallic section - more visible with stronger metallic look
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.gray.opacity(0.7),
                                Color.gray.opacity(0.9),
                                Color.gray.opacity(0.7)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 3)
                
                // Bottom shadow
                Rectangle()
                    .fill(Color.black.opacity(0.4))
                    .frame(height: 1)
            }
            // Fix the white pixelation with proper shape clipping
            .clipShape(RoundedRectangle(cornerRadius: 0.1))
            // Add a clean edge to prevent any edge artifacts
            .overlay(
                RoundedRectangle(cornerRadius: 0.1)
                    .strokeBorder(Color.gray.opacity(0.6), lineWidth: 0.5)
                    .blur(radius: 0.2)
            )
        }
    }
}

/// Preview provider for the NeveHorizontalDividerView.
struct NeveHorizontalDividerView_Previews: PreviewProvider {
    static var previews: some View {
        NeveHorizontalDividerView()
            .frame(height: 4)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
