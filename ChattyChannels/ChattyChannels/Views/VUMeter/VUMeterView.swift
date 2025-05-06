// VUMeterView.swift
//
// Main SwiftUI view for the stereo VU meter component with Neve console styling

import SwiftUI

/// A SwiftUI view that displays a stereo pair of VU meters.
///
/// This is the main container component for the VU meter functionality. It displays
/// a left and right channel meter and the current track name.
/// Styling inspired by classic Neve 1073 recording consoles, such as the horizontal divider,
/// is applied, but overarching elements like a top wooden strip are managed by the parent view.
struct VUMeterView: View {
    /// The service that provides audio level data
    @ObservedObject var levelService: LevelMeterService
    
    var body: some View {
        ZStack(alignment: .top) {
            // Base background
            Color(red: 40/255, green: 41/255, blue: 44/255) // Xcode dark background
            
            VStack(spacing: 0) {
                // Main meter area
                VStack(spacing: 0) {
                    // VU meters container - positioned to the right
                    HStack {
                        // This large spacer pushes all content to the right
                        Spacer()
                            .layoutPriority(1)
                        
                        // Meters with spacing between them matching the right padding
                        HStack(spacing: 26) { // Increased spacing to match right padding
                            // Left channel meter
                            SingleMeterView(audioLevel: $levelService.leftChannel, channel: .left)
                                .frame(width: 112, height: 69) // Re-applying frame, 112, 69
                            
                            // Right channel meter
                            SingleMeterView(audioLevel: $levelService.rightChannel, channel: .right)
                                .frame(width: 112, height: 69) // Re-applying frame, 112, 69
                        }
                        .frame(width: 250) // Adjusted width for new meter size (112 + 26 + 112)
                        
                        // Increased right margin by 30%
                        Spacer()
                            .frame(width: 20) // Align with divider padding
                            .layoutPriority(0)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    
                    // Track label - styled to match the chat portion of the app and centered
                    // Replicated structure from meter HStack to center label under meters
                    HStack {
                        // This large spacer pushes all content to the right
                        Spacer()
                            .layoutPriority(1)

                        // Label centered within the same width as the meter container
                        Text(levelService.currentTrack)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(white: 0.7)) // More subtle gray
                            .padding(.vertical, 0)
                            .padding(.horizontal, 10)
                            .frame(width: 250, alignment: .center) // Center text within the new meter area width

                        // Same fixed right margin as meters
                        Spacer()
                            .frame(width: 20) // Align with divider padding
                            .layoutPriority(0)
                    }
                    .padding(.bottom, 10)
                }
                // Horizontal divider removed, will be managed by ContentView
            }
        }
        .frame(height: 100) // Debug frame, width removed
        // .background(Color.green) // Debug background removed
    }
}

#Preview("VU Meter View", traits: .sizeThatFitsLayout) {
    // Preview wrapper
    VUMeterView(levelService: LevelMeterService(oscService: OSCService()))
        .frame(height: 250)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
}
