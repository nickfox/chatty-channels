// SingleMeterView.swift
//
// SwiftUI view for a single VU meter (left or right channel)

import SwiftUI

/// A SwiftUI view that renders a single VU meter for one audio channel.
///
/// This component includes the meter face, animated needle, and peak indicator.
/// It handles the proper VU meter ballistics for needle movement.
struct SingleMeterView: View {
    /// The audio level data to display
    @Binding var audioLevel: AudioLevel
    
    /// The channel this meter represents
    var channel: AudioLevel.AudioChannel
    
    // MARK: - Animation Properties
    
    /// Current rotation angle of the needle
    @State private var needleRotation: Double = -45.0
    
    /// Target rotation angle of the needle
    @State private var needleTarget: Double = -45.0
    
    /// Whether the peak indicator is active
    @State private var isPeakActive: Bool = false
    
    /// Timestamp for when to deactivate the peak indicator
    @State private var peakHoldTime: Date = Date()
    
    /// How long to hold the peak indicator lit (in seconds)
    let peakHoldDuration: TimeInterval = 1.5
    
    /// Timer for smooth animation updates
    let timer = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in // Re-introduce GeometryReader
            ZStack {
                // Meter background image
                Image("vu_meter")
                    .resizable()   // Correct order: resizable first
                    .interpolation(.high) // Add high quality interpolation
                    .scaledToFit() // Then scaledToFit
                    // Frame is applied in parent view

                // Needle
                NeedleView(
                    color: .black,
                    length: geometry.size.height * 0.5,
                    width: max(1, geometry.size.width * 0.004), // Use geometry
                    pivotDiameter: max(4, geometry.size.width * 0.02) // Use geometry
                )
                .rotationEffect(.degrees(needleRotation), anchor: .bottom)
                .position(x: geometry.size.width * 0.5, // Use geometry
                          y: geometry.size.height * 0.67) // Use geometry

                // Peak indicator - fixed position near the top of the VU meter
                PeakIndicatorView(
                    isActive: isPeakActive,
                    diameter: 6, // Fixed size
                    activeColor: .red,
                    inactiveColor: .red.opacity(0.15)
                )
                .position(x: geometry.size.width * 0.77, // Use geometry
                          y: geometry.size.height * 0.3) // Use geometry
            }
            // Removed .clipped()
            .onReceive(timer) { _ in
                updateMeter()
            }
        }
    }
    
    /// Updates the meter display based on the current audio level.
    ///
    /// This method is called on a timer to provide smooth animation.
    /// It implements proper VU meter ballistics for realistic needle movement.
    private func updateMeter() {
        // Get dB value and constrain to VU meter range
        let dbValue = audioLevel.dbValue
        let constrainedDb = min(max(dbValue, -20), 3)
        
        // Map dB to rotation angle
        needleTarget = mapDbToRotation(db: constrainedDb)
        
        // Apply VU meter ballistics (300ms integration time)
        // This coefficient determines how quickly the needle responds to changes
        needleRotation += (needleTarget - needleRotation) * 0.15
        
        // Handle peak LED
        if audioLevel.isPeaking {
            isPeakActive = true
            peakHoldTime = Date().addingTimeInterval(peakHoldDuration)
        } else if isPeakActive && Date() > peakHoldTime {
            isPeakActive = false
        }
    }
    
    /// Maps a dB value to a needle rotation angle.
    ///
    /// - Parameter db: The dB value to map (-20 to +3 dB range)
    /// - Returns: The rotation angle in degrees
    private func mapDbToRotation(db: Float) -> Double {
        // Map from dB scale to rotation degrees
        // VU meters typically have -20dB at -45° and +3dB at +45°
        
        // Normalize -20 to +3 range to 0-1
        let normalizedValue = (db + 20) / 23
        
        // Apply non-linear mapping to match VU meter scale
        // VU meters have non-linear scales with more detail in the -3 to +3 range
        let adjustedValue = pow(Double(normalizedValue), 0.9)
        
        // Convert to rotation angle (from -45° to +45°)
        return -45.0 + adjustedValue * 90.0
    }
}

#Preview {
    // Create a state object for the preview
    struct PreviewWrapper: View {
        @State private var level = AudioLevel(value: 0.2, channel: .left)
        
        var body: some View {
            VStack {
                SingleMeterView(audioLevel: $level, channel: .left)
                    .frame(width: 300, height: 180)
                    .padding()
                
                // Controls for the preview
                VStack {
                    Text("Level: \(Int(level.value * 100))%")
                    Slider(value: $level.value, in: 0...1)
                    
                    Button("Peak") {
                        level.value = 1.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            level.value = 0.2
                        }
                    }
                }
                .padding()
            }
            .padding()
            .frame(height: 400)
        }
    }
    
    return PreviewWrapper()
}
