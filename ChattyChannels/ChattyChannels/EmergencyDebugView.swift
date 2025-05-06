// EmergencyDebugView.swift
//
// A minimal emergency debug view that contains ONLY a wooden strip

import SwiftUI

/// Ultra-minimal view for debugging - contains ONLY a wooden strip
struct EmergencyDebugView: View {
    var body: some View {
        // The most minimal possible implementation
        Rectangle()
            .fill(Color(red: 0.82, green: 0.53, blue: 0.18)) // Honey color
            .ignoresSafeArea()
            .overlay(
                Text("EMERGENCY DEBUG VIEW")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
            )
            .onAppear {
                print("EmergencyDebugView appeared")
            }
    }
}

#Preview {
    EmergencyDebugView()
}
