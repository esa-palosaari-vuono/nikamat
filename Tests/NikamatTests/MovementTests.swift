import Testing
@testable import Nikamat

/// `Movement.frame(at:)` is a pure function of elapsed time, and both the
/// animation and the countdown depend on it.
struct MovementTests {
    private let rest = Pose()
    private let end = Pose(headTilt: 30)

    @Test func holdEasesInHoldsAndReturns() {
        let movement = Movement(pattern: .hold(seconds: 20), keyframes: [rest, end])
        #expect(movement.frame(at: 0).pose == rest)
        #expect(movement.frame(at: 0).phase == "vie")

        let middle = movement.frame(at: 10)
        #expect(middle.phase == "pidä")
        // The breathing oscillation stays within a few percent of end range.
        #expect(middle.pose.headTilt > 28 && middle.pose.headTilt <= 30)

        #expect(movement.frame(at: 20).pose == rest)
        #expect(movement.frame(at: 20).repetition == nil)
    }

    @Test func repsCountRepetitionsAndPhases() {
        let movement = Movement(pattern: .reps(count: 3, hold: 5, release: 3), keyframes: [rest, end])
        #expect(movement.frame(at: 0.5).phase == "purista")
        #expect(movement.frame(at: 3).phase == "pidä")
        #expect(movement.frame(at: 3).pose.headTilt == 30)
        #expect(movement.frame(at: 7).phase == "rentouta")
        #expect(movement.frame(at: 7).pose == rest)

        #expect(movement.frame(at: 0).repetition == 1)
        #expect(movement.frame(at: 8.1).repetition == 2)
        #expect(movement.frame(at: 23).repetition == 3)
        #expect(movement.frame(at: 23).repetitionCount == 3)
    }

    /// The session can sample slightly past the end of a step before it
    /// notices the boundary; that must clamp, not overflow.
    @Test func samplingPastTheEndClamps() {
        let reps = Movement(pattern: .reps(count: 2, hold: 2, release: 2), keyframes: [rest, end])
        #expect(reps.frame(at: 100).repetition == 2)
        let cycle = Movement(pattern: .cycle(count: 2, period: 4), keyframes: [rest, end, rest])
        #expect(cycle.frame(at: 100).repetition == 2)
    }

    @Test func cycleClosesTheLoop() {
        let quarter = Pose(headTurn: 40)
        let movement = Movement(pattern: .cycle(count: 2, period: 4), keyframes: [rest, quarter])
        #expect(movement.frame(at: 0).pose == rest)
        #expect(movement.frame(at: 2).pose == quarter)
        // Back at the start of the second cycle.
        #expect(abs(movement.frame(at: 4).pose.headTurn) < 1e-9)
        #expect(movement.frame(at: 4).repetition == 2)
    }

    @Test func scalingKeepsPatternsSensible() {
        #expect(MovementPattern.hold(seconds: 20).scaled(by: 0.1) == .hold(seconds: 4))
        #expect(MovementPattern.hold(seconds: 20).scaled(by: 1.25) == .hold(seconds: 25))
        #expect(MovementPattern.reps(count: 6, hold: 5, release: 3).scaled(by: 0.05)
                == .reps(count: 1, hold: 5, release: 3))
        #expect(MovementPattern.cycle(count: 8, period: 4).scaled(by: 0.5)
                == .cycle(count: 4, period: 4))
        #expect(MovementPattern.reps(count: 6, hold: 5, release: 3).duration == 48)
    }
}
