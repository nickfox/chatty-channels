// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannels/PIDController.swift
//
// Simple PID controller used for volume automation (v0.5)
//
import Foundation

/// Represents the gain constants for a PID controller.
public struct PIDGain {
    public let kp: Float
    public let ki: Float
    public let kd: Float

    public init(kp: Float, ki: Float = 0, kd: Float = 0) {
        self.kp = kp
        self.ki = ki
        self.kd = kd
    }
}

/// Minimalistic PID controller (P-only in v0.5) for dB level convergence.
public final class PIDController {

    private let gain: PIDGain
    private var integral: Float = 0
    private var previousError: Float = 0
    private var firstCall = true

    public init(gain: PIDGain) {
        self.gain = gain
    }

    /// Resets the internal integrator and derivative state.
    public func reset() {
        integral = 0
        previousError = 0
        firstCall = true
    }

    /// Calculates the next control output (delta) to apply.
    ///
    /// - Parameters:
    ///   - setpoint: Desired target value.
    ///   - measured: Current measured value.
    ///   - dt: Time elapsed since last call (seconds). Default = 1.
    /// - Returns: Control delta that should be **added** to `measured`.
    public func nextOutput(setpoint: Float, measured: Float, dt: Float = 1.0) -> Float {
        let error = setpoint - measured

        // Integral term
        integral += error * dt

        // Derivative term
        let derivative: Float
        if firstCall {
            derivative = 0
            firstCall = false
        } else {
            derivative = (error - previousError) / dt
        }
        previousError = error

        // PID formula
        let output = gain.kp * error + gain.ki * integral + gain.kd * derivative
        return output
    }
}