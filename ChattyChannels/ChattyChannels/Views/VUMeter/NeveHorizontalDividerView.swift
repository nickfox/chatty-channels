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
        // Single rectangle with a gradient to create a subtle metallic sheen
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(white: 0.40), location: 0.0),   // Top highlight edge
                        .init(color: Color(white: 0.35), location: 0.25),  // End of highlight
                        .init(color: Color(white: 0.28), location: 0.60),  // Main body color
                        .init(color: Color(white: 0.22), location: 1.0)    // Bottom shadow edge
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        // The .frame(height: 4) is applied by the parent view (ContentView)
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
