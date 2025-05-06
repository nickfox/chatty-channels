// NeedleView.swift
//
// SwiftUI view for the VU meter needle

import SwiftUI

/// A SwiftUI view that renders the needle for the VU meter.
///
/// This component creates a simple needle with a pivot point that can be rotated
/// based on audio levels.
struct NeedleView: View {
    /// The color of the needle
    var color: Color = .black
    
    /// The length of the needle
    var length: CGFloat = 40
    
    /// The width of the needle
    var width: CGFloat = 2
    
    /// The diameter of the pivot point
    var pivotDiameter: CGFloat = 8
    
    var body: some View {
        VStack(spacing: 0) {
            // Needle shaft
            Rectangle()
                .fill(color)
                .frame(width: width, height: length)
            
            // Pivot point
            Circle()
                .fill(color)
                .frame(width: pivotDiameter, height: pivotDiameter)
        }
    }
}

#Preview("Needle at different angles", traits: .sizeThatFitsLayout) {
    VStack {
        NeedleView()
            .rotationEffect(.degrees(-45), anchor: .bottom)
            .padding()
        
        NeedleView()
            .rotationEffect(.degrees(0), anchor: .bottom)
            .padding()
        
        NeedleView()
            .rotationEffect(.degrees(45), anchor: .bottom)
            .padding()
    }
    .frame(height: 300)
    .background(Color.gray.opacity(0.2))
}
