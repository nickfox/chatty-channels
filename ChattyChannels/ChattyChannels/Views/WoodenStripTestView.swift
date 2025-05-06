// WoodenStripTestView.swift
//
// A test view to isolate and debug the wooden strip component

import SwiftUI

/// A simple test view for debugging the wooden strip.
/// This view only renders the wooden strip against a dark background
/// to help isolate any rendering issues.
struct WoodenStripTestView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Wooden strip with specified height
            Rectangle()
                .fill(Color(red: 0.82, green: 0.53, blue: 0.18)) // Original honey color
                .frame(height: 50)
                .border(Color.black.opacity(0.3), width: 1)
            
            // Spacer to push the strip to the top
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct WoodenStripTestView_Previews: PreviewProvider {
    static var previews: some View {
        WoodenStripTestView()
            .frame(width: 800, height: 600)
    }
}
