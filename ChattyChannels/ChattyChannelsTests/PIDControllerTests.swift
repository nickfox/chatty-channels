// /Users/nickfox137/Documents/chatty-channel/ChattyChannels/ChattyChannelsTests/PIDControllerTests.swift
//
// Unit-tests for the minimal PIDController used in v0.5.
// Uses the lightweight `Testing` package already adopted in the project.
//
import Testing
@testable import ChattyChannels

struct PIDControllerTests {

    /// Helper to simulate the closed loop for a fixed number of iterations.
    private func runLoop(controller: PIDController,
                         start: Float,
                         target: Float,
                         iterations: Int) -> [Float] {
        var measured = start
        var history: [Float] = [measured]

        for _ in 0..<iterations {
            let delta = controller.nextOutput(setpoint: target, measured: measured)
            measured += delta
            history.append(measured)
        }
        return history
    }

    @Test
    func testConvergesWithinThreeStepsKickMinus3dB() throws {
        let Kp: Float = 1.0   // Pure P-controller as specified in plan
        let controller = PIDController(gain: .init(kp: Kp))

        // Spec: start at 0 dB, aim at –3 dB -> converge ≤3 steps, steady-state ≤±0.1 dB
        let target: Float = -3.0
        let history = runLoop(controller: controller,
                              start: 0,
                              target: target,
                              iterations: 3)

        // Take the last value after N iterations
        let final = try #require(history.last)

        #expect(abs(final - target) <= 0.1,
                "Expected final error ≤0.1 dB but got \(final - target)")

        // Optional: Ensure monotonic move toward setpoint (no wild oscillation)
        // (Not part of spec but good sanity check)
        for (prev, next) in zip(history, history.dropFirst()) {
            #expect(abs(next - target) <= abs(prev - target),
                    "Controller should move monotonically toward setpoint.")
        }
    }
}