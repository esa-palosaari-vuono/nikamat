import Foundation

/// Turns elapsed time into a figure pose and a phase label.
///
/// This is deliberately a pure function of (pattern, keyframes, elapsed): the
/// break session owns the clock, the view owns the drawing, and neither needs
/// to keep animation state of its own. Pausing, skipping and resuming all fall
/// out of simply passing a different elapsed value.
struct Movement {
    let pattern: MovementPattern
    let keyframes: [Pose]

    /// Seconds spent easing into and out of a held stretch. Long enough to read
    /// as movement rather than a jump, short enough not to eat the hold.
    private static let rampIn = 1.4
    private static let rampOut = 0.9

    func frame(at elapsed: Double) -> MovementFrame {
        let rest = keyframes.first ?? .neutral
        let end = keyframes.last ?? .neutral

        switch pattern {
        case .hold(let seconds):
            let remaining = seconds - elapsed
            let u: Double
            if elapsed < Self.rampIn {
                u = easeInOut(elapsed / Self.rampIn)
            } else if remaining < Self.rampOut {
                u = easeInOut(max(0, remaining) / Self.rampOut)
            } else {
                // A slow breathing oscillation at the end range. Without it a
                // held stretch looks like a frozen screenshot and the user
                // starts wondering whether the app hung.
                let breath = sin((elapsed - Self.rampIn) * 2 * .pi / 5.0)
                u = 1 - 0.035 * (1 - breath) / 2
            }
            return MovementFrame(
                pose: Pose.lerp(rest, end, u),
                phase: elapsed < Self.rampIn ? "vie" : "pidä",
                repetition: nil,
                repetitionCount: nil
            )

        case .reps(let count, let hold, let release):
            let period = hold + release
            let index = min(count - 1, Int(elapsed / period))
            let inRep = elapsed - Double(index) * period
            // Contract briskly, hold, then let go a little more slowly.
            let rise = min(1.0, hold * 0.35)
            let fall = min(1.0, release * 0.5)
            let u: Double
            let phase: String
            if inRep < rise {
                u = easeInOut(inRep / rise)
                phase = "purista"
            } else if inRep < hold {
                u = 1
                phase = "pidä"
            } else if inRep < hold + fall {
                u = easeInOut(1 - (inRep - hold) / fall)
                phase = "rentouta"
            } else {
                u = 0
                phase = "rentouta"
            }
            return MovementFrame(
                pose: Pose.lerp(rest, end, u),
                phase: phase,
                repetition: index + 1,
                repetitionCount: count
            )

        case .cycle(let count, let period):
            let index = min(count - 1, Int(elapsed / period))
            let inCycle = (elapsed - Double(index) * period) / period
            // Walk the keyframe ring: n keyframes make n segments, the last of
            // which returns to the first, so the loop closes seamlessly.
            let n = max(keyframes.count, 2)
            let position = inCycle * Double(n)
            let segment = min(n - 1, Int(position))
            let local = easeInOut(position - Double(segment))
            let from = keyframes[segment % keyframes.count]
            let to = keyframes[(segment + 1) % keyframes.count]
            return MovementFrame(
                pose: Pose.lerp(from, to, local),
                phase: "jatka",
                repetition: index + 1,
                repetitionCount: count
            )
        }
    }
}
