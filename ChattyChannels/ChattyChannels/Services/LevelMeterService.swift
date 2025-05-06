// LevelMeterService.swift
//
// Service for processing and providing audio level data to the VU meter

import Foundation
import Combine
import SwiftUI
import os.log

/// Service that processes OSC audio level data for display in VU meters.
///
/// This service subscribes to the OSC service's level updates, processes them,
/// and publishes the processed data for consumption by VU meter components.
class LevelMeterService: ObservableObject {
    /// Published left channel audio level
    @Published var leftChannel = AudioLevel(channel: .left)
    
    /// Published right channel audio level
    @Published var rightChannel = AudioLevel(channel: .right)
    
    /// Name of the currently monitored track
    @Published var currentTrack: String = "No Track Selected"
    
    /// System logger for level meter events
    private let logger = Logger(subsystem: "com.nickfox.ChattyChannels", category: "LevelMeter")
    
    /// Reference to the OSC service
    private var oscService: OSCService
    
    /// Subscription to OSC level updates
    private var oscSubscription: AnyCancellable?
    
    /// Initializes the service with a reference to the OSC service.
    ///
    /// - Parameter oscService: The OSC service to subscribe to for level updates.
    init(oscService: OSCService) {
        self.oscService = oscService
        logger.info("LevelMeterService initialized")
        setupOSCSubscription()
    }
    
    /// Sets up the subscription to OSC level updates.
    private func setupOSCSubscription() {
        // For v0.6, we'll use a simulated level data source
        // In a future version, this will connect to the actual OSC data
        
        // Create a timer publisher that simulates level data at 30fps
        let timer = Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()
        
        oscSubscription = timer.sink { [weak self] _ in
            self?.simulateAudioLevels()
        }
        
        logger.info("Set up simulated audio level subscription")
    }
    
    /// Simulates audio level data for development and testing.
    ///
    /// This is a temporary function that generates realistic-looking level data
    /// until the actual OSC integration is implemented.
    private func simulateAudioLevels() {
        // Create a slow-moving baseline with some randomness
        let time = Date().timeIntervalSince1970
        let baselineLeft = (sin(time * 0.5) * 0.3) + 0.5
        let baselineRight = (sin(time * 0.4 + 0.3) * 0.3) + 0.5
        
        // Add some random fluctuation
        let fluctuationLeft = Double.random(in: -0.1...0.1)
        let fluctuationRight = Double.random(in: -0.1...0.1)
        
        // Ensure values stay in valid range
        let newLeftValue = Float(max(0.0, min(1.0, baselineLeft + fluctuationLeft)))
        let newRightValue = Float(max(0.0, min(1.0, baselineRight + fluctuationRight)))
        
        // Occasional peaks
        if Int(time * 10) % 50 == 0 {
            // Create an occasional peak
            leftChannel.value = Float.random(in: 0.8...1.0)
        } else {
            leftChannel.value = newLeftValue
        }
        
        if Int(time * 10) % 73 == 0 {
            // Create an occasional peak on right channel (different rhythm)
            rightChannel.value = Float.random(in: 0.8...1.0)
        } else {
            rightChannel.value = newRightValue
        }
        
        // Update peak values
        leftChannel.peakValue = max(leftChannel.peakValue, leftChannel.value)
        rightChannel.peakValue = max(rightChannel.peakValue, rightChannel.value)
        
        // Decay peak values over time
        leftChannel.peakValue *= 0.99
        rightChannel.peakValue *= 0.99
    }
    
    /// Processes actual OSC data and updates the audio levels.
    ///
    /// This method will be implemented in a future version to process real OSC data.
    /// - Parameter data: The OSC data to process.
    private func processOSCData(_ data: Any) {
        // This will be implemented with actual OSC data in a future version
        // For now, we're using the simulated data above
    }
    
    /// Sets the current track name.
    ///
    /// - Parameter name: The name of the track to display.
    func setCurrentTrack(_ name: String) {
        currentTrack = name
        logger.info("Track set to: \(name)")
    }
    
    /// Resets the peak values for both channels.
    func resetPeaks() {
        leftChannel.peakValue = 0.0
        rightChannel.peakValue = 0.0
        logger.info("Peak values reset")
    }
    
    /// Cleans up resources when the service is deallocated.
    deinit {
        oscSubscription?.cancel()
        logger.info("LevelMeterService deallocated")
    }
}
