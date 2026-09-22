import Testing
@testable import Nikamat

/// Invariants of the exercise catalogue. The library is data, and these are the
/// rules the renderer and planner rely on without checking them at runtime.
struct ExerciseLibraryTests {

    @Test func identifiersAreUnique() {
        let ids = ExerciseLibrary.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test(arguments: ExerciseLibrary.all.map(\.id))
    func exerciseIsWellFormed(id: String) throws {
        let exercise = try #require(ExerciseLibrary.exercise(id: id))
        #expect(exercise.keyframes.count >= 2, "hold and reps read the first and last keyframe")
        #expect(!exercise.tiers.isEmpty)
        if let sides = exercise.sides {
            #expect(sides.count == 2, "the second side is derived by mirroring the first")
        }
    }

    /// Interpolating between two different anchor kinds would blend
    /// incompatible descriptions of one limb and snap the elbow halfway.
    @Test(arguments: ExerciseLibrary.all.map(\.id))
    func anchorKindIsConstantAcrossKeyframes(id: String) throws {
        let exercise = try #require(ExerciseLibrary.exercise(id: id))
        let left = Set(exercise.keyframes.map { $0.left.anchor.kind })
        let right = Set(exercise.keyframes.map { $0.right.anchor.kind })
        #expect(left.count == 1, "left arm mixes anchors: \(left)")
        #expect(right.count == 1, "right arm mixes anchors: \(right)")
    }

    @Test(arguments: ExerciseLibrary.all.map(\.id))
    func mirroringTwiceIsIdentity(id: String) throws {
        let exercise = try #require(ExerciseLibrary.exercise(id: id))
        for pose in exercise.keyframes {
            #expect(pose.mirrored.mirrored == pose)
        }
    }

    /// The countdown is on screen, so no exercise may turn the face away from
    /// it or need anything beyond the chair (see docs/liikkeet.org).
    @Test(arguments: ExerciseLibrary.all.map(\.id))
    func gazeStaysOnTheScreen(id: String) throws {
        let exercise = try #require(ExerciseLibrary.exercise(id: id))
        #expect(exercise.prop == nil, "needs a wall or a doorframe")
        for pose in exercise.keyframes {
            #expect(abs(pose.headTurn) <= 15, "face turns \(pose.headTurn)° away")
            #expect((-10...15).contains(pose.headNod), "gaze tips \(pose.headNod)° off the screen")
        }
    }

    @Test func microBreaksNeverRequireStanding() {
        let pool = ExerciseLibrary.pool(for: .micro, allowStanding: true)
        #expect(!pool.isEmpty)
        #expect(pool.allSatisfy { $0.posture == .seated })
    }

    /// The planner wants five regions for a long break; fewer in the pool
    /// would silently make long breaks shorter than designed.
    @Test func longBreakPoolCoversEnoughRegions() {
        let seated = ExerciseLibrary.pool(for: .long, allowStanding: false)
        #expect(Set(seated.map(\.region)).count >= 5)
    }
}

extension HandAnchor {
    /// The anchor's case without its associated point.
    var kind: String {
        switch self {
        case .free: return "free"
        case .torso: return "torso"
        case .world: return "world"
        case .headPoint: return "headPoint"
        case .headBack: return "headBack"
        case .lowBack: return "lowBack"
        }
    }
}
