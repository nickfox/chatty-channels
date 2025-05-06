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
            Color(NSColor.windowBackgroundColor)
            
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
                                .frame(width: 150, height: 90) // Reduced size by 25%
                            
                            // Right channel meter
                            SingleMeterView(audioLevel: $levelService.rightChannel, channel: .right)
                                .frame(width: 150, height: 90) // Reduced size by 25%
                        }
                        .frame(width: 326) // Adjusted width for new meter size (150 + 26 + 150)
                        
                        // Increased right margin by 30%
                        Spacer()
                            .frame(width: 26) // Increased from 20 to 26
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
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(red: 0.25, green: 0.25, blue: 0.25))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .frame(width: 326, alignment: .center) // Center text within the meter area width

                        // Same fixed right margin as meters
                        Spacer()
                            .frame(width: 26)
                            .layoutPriority(0)
                    }
                    .padding(.bottom, 10)
                }
                
                // Horizontal divider - Neve console style with padding on sides
                HStack {
                    Spacer()
                        .frame(width: 20)
                    
                    NeveHorizontalDividerView()
                        .frame(height: 4)
                    
                    Spacer()
                        .frame(width: 20)
                }
            }
        }
    }
}

#Preview("VU Meter View", traits: .sizeThatFitsLayout) {
    // Preview wrapper
    VUMeterView(levelService: LevelMeterService(oscService: OSCService()))
        .frame(height: 250)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
}
