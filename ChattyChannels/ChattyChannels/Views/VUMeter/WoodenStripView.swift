// WoodenStripView.swift
//
// A SwiftUI view that renders a realistic wooden strip inspired by vintage Neve consoles

import SwiftUI

/// A view that renders a wooden strip similar to those found on vintage Neve 1073 consoles.
///
/// This creates a visually distinct wooden strip inspired by classic Neve consoles.
struct WoodenStripView: View {
    var body: some View {
        // Most basic implementation possible - guaranteed to be visible
        Rectangle()
            .fill(Color(red: 0.82, green: 0.53, blue: 0.18)) // Original honey color
            .frame(maxWidth: .infinity)
            .border(Color.black.opacity(0.3), width: 1)
    }
}

/// Preview provider for the WoodenStripView.
struct WoodenStripView_Previews: PreviewProvider {
    static var previews: some View {
        WoodenStripView()
            .frame(height: 50)
            .padding()
            .previewLayout(.sizeThatFits)
            .background(Color(.windowBackgroundColor))
    }
}
