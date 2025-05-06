// PeakIndicatorView.swift
//
// SwiftUI view for the VU meter peak indicator LED

import SwiftUI

/// A SwiftUI view that renders the peak indicator LED for the VU meter.
///
/// This component creates a circular LED that illuminates when audio levels exceed 0dB.
struct PeakIndicatorView: View {
    /// Whether the peak indicator is active
    var isActive: Bool
    
    /// The diameter of the LED
    var diameter: CGFloat = 8
    
    /// The color of the LED when active
    var activeColor: Color = .red
    
    /// The color of the LED when inactive
    var inactiveColor: Color = .red.opacity(0.3)
    
    var body: some View {
        Circle()
            .fill(isActive ? activeColor : inactiveColor)
            .frame(width: diameter, height: diameter)
            .shadow(color: isActive ? activeColor.opacity(0.8) : .clear, radius: isActive ? 4 : 0)
            .animation(.easeOut(duration: 0.1), value: isActive)
    }
}

#Preview("Peak Indicator States", traits: .sizeThatFitsLayout) {
    VStack(spacing: 30) {
        PeakIndicatorView(isActive: true)
            .padding()
        
        PeakIndicatorView(isActive: false)
            .padding()
    }
    .frame(height: 100)
    .background(Color.black.opacity(0.8))
}
