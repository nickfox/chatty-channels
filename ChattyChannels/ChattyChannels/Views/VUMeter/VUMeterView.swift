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
    
    // Get the most recently active track (for v0.7 OSC integration)
    // This allows VU meters to automatically follow whichever track is sending RMS data
    private var activeTrackUUID: String {
        // Find the track with the most recent update time
        let sortedTracks = levelService.audioLevels.sorted { lhs, rhs in
            let lhsTime = lhs.value.lastUpdateTime
            let rhsTime = rhs.value.lastUpdateTime
            return lhsTime > rhsTime
        }
        
        // Return the most recently updated track UUID, or a default
        return sortedTracks.first?.key ?? "NO_ACTIVE_TRACK"
    }
    
    // Computed properties for compatibility with v0.7 data model
    private var leftChannelBinding: Binding<AudioLevel> {
        Binding<AudioLevel>(
            get: {
                // Get the AudioLevel for the most active track or create a default one
                let activeLevel = levelService.audioLevels[activeTrackUUID] ?? 
                    AudioLevel(id: activeTrackUUID, rmsValue: 0.0, peakRmsValue: 0.0, trackName: "No Active Track")
                
                // For demo and backward compatibility - we'll treat the same level as both L and R channels
                return activeLevel
            },
            set: { newLevel in
                // We don't actually modify the level here as it's managed by LevelMeterService
            }
        )
    }
    
    private var rightChannelBinding: Binding<AudioLevel> {
        // We're using the same binding for both channels for now
        // In a future version, we could map to different tracks for L/R channels
        return leftChannelBinding
    }
    
    // Current track name - defaults to "No Active Track" if not available
    private var currentTrackName: String {
        if let track = levelService.audioLevels[activeTrackUUID]?.trackName {
            return track
        }
        return "No Active Track"
    }
    
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
                            SingleMeterView(audioLevel: leftChannelBinding)
                                .frame(width: 112, height: 69) // Re-applying frame, 112, 69
                            
                            // Right channel meter
                            SingleMeterView(audioLevel: rightChannelBinding)
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
                        Text(currentTrackName)
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

// Helper struct for preview setup
struct VUMeterPreviewWrapper: View {
    @StateObject var levelServiceInstance = LevelMeterService()
    
    init(populateData: Bool = true) {
        if populateData {
            let kickTrackUUID = "KICK_TRACK_UUID"
            levelServiceInstance.audioLevels[kickTrackUUID] = AudioLevel(id: kickTrackUUID, rmsValue: 0.6, peakRmsValue: 0.9, trackName: "Kick")
        }
    }

    var body: some View {
        VUMeterView(levelService: levelServiceInstance)
    }
}

#Preview("VU Meter View - Kick Track", traits: .sizeThatFitsLayout) {
    VUMeterPreviewWrapper(populateData: true)
        .frame(width: 300, height: 150)
        .padding()
        .background(Color.gray.opacity(0.2))
}
