// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/KickVolumeController.swift

import Foundation

/// Controller for automated adjustment of the Kick track volume using a P-controller.
public final class KickVolumeController {
    private let pid: PIDController
    private let appleScriptService: AppleScriptServiceProtocol
    private let trackName: String

    /// Initializes the KickVolumeController.
    /// - Parameters:
    ///   - pid: PIDController instance configured for P-only control.
    ///   - appleScriptService: Service for volume get/set operations.
    ///   - trackName: Logic Pro track name; defaults to "Kick".
    public init(pid: PIDController,
                appleScriptService: AppleScriptServiceProtocol,
                trackName: String = "Kick") {
        self.pid = pid
        self.appleScriptService = appleScriptService
        self.trackName = trackName
    }

    /// Performs one control iteration: reads current volume, computes delta, and sets new volume.
    /// - Parameter target: Desired fader level in dB.
    /// - Returns: New fader level after applying the control delta.
    /// - Throws: AppleScriptError if get or set operations fail.
    public func controlOnce(target: Float) throws -> Float {
        let measured = try appleScriptService.getVolume(trackName: trackName)
        let delta = pid.nextOutput(setpoint: target, measured: measured)
        let newValue = measured + delta
        try appleScriptService.setVolume(trackName: trackName, db: newValue)
        return newValue
    }
}