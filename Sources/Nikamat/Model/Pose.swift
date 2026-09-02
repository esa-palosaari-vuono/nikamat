import CoreGraphics
import Foundation

/// Fixed proportions of the drawn figure, expressed in *head units* (hu):
/// one hu is roughly one head height, which keeps the numbers in the pose
/// library readable ("hand 0.6 hu above the shoulder") and makes the whole
/// figure scale to any canvas size by a single multiplication.
///
/// The origin sits at the base of the neck (roughly C7) with y growing
/// downwards, matching Core Graphics' view coordinates so the renderer needs
/// no axis flip.
enum Body {
    // Slightly egg-shaped rather than round: a circle looks identical at
    // every angle, so a round head makes a 30-degree neck tilt invisible.
    static let headRadiusX = 0.375
    static let headRadiusY = 0.50
    static let neckLength = 0.26
    static let shoulderHalf = 0.70
    static let shoulderY = 0.12
    static let hipY = 1.34
    static let hipHalf = 0.46
    // Roughly anatomical: upper arm a little under one head height, forearm
    // and hand a little under that again. Shortening them made the figure look
    // like a child and, worse, made it unable to reach its own head -- which
    // several of these stretches require.
    static let upperArm = 0.80
    static let foreArm = 0.72

    /// Half-width of the drawn doorframe. Set so that a horizontal upper arm
    /// puts the elbow just inside the post, which is the actual shape of a
    /// doorway pec stretch.
    static let doorwayHalf = 1.62

    /// Head centre in the neutral pose, before any head transform.
    static let headCenter = CGPoint(x: 0, y: -(neckLength + headRadiusY))

    /// Shoulder joint for `side` (-1 = the figure's left as drawn on the
    /// canvas, +1 = right), ignoring shrug, which the renderer adds.
    static func shoulder(_ side: Double) -> CGPoint {
        CGPoint(x: side * shoulderHalf, y: shoulderY)
    }
}

/// Where a hand is held. Angles describe *how* a limb is oriented, but many
/// desk stretches are defined by *where the hand ends up* — palm on the temple,
/// fingers laced behind the head, forearm flat against a doorframe. Anchors
/// express that directly and are resolved by the renderer, which is the only
/// place that knows the current head and torso transforms.
///
/// Invariant: every keyframe of one exercise must use the same anchor *case*.
/// Interpolating between "hand hanging free" and "hand on the head" would
/// otherwise have to blend two incompatible descriptions of the same limb, and
/// the elbow would visibly snap halfway through. Exercises therefore start with
/// the hand already placed, and the movement only changes the head or torso.
enum HandAnchor: Equatable {
    /// Follow the joint angles in `ArmPose`.
    case free
    /// A point in *torso* space: it leans and foreshortens with the trunk, so
    /// arms folded across the chest stay folded while the trunk rotates.
    case torso(CGPoint)
    /// A point fixed in the drawing, used for props. A palm on a doorframe
    /// stays on the doorframe no matter what the trunk does.
    case world(CGPoint)
    /// A point in head-local head units, which rotates with the skull, so an
    /// assisting hand keeps its grip through the whole tilt. (-0.22, -0.30) is
    /// the left side of the crown, (0.38, 0) the right temple.
    case headPoint(CGPoint)
    /// Fingers laced behind the head.
    case headBack
    /// Hands clasped behind the lower back.
    case lowBack
}

/// One arm. `abduction` lifts the upper arm away from the body in the frontal
/// plane (0 = hanging down, 90 = horizontal); `flexion` swings it forward in
/// the sagittal plane, which is what the side view shows; `elbow` bends the
/// forearm. `shoulderLift` shrugs (+1) or depresses (-1) that shoulder, which
/// several of the scapular drills depend on.
struct ArmPose: Equatable {
    var abduction: Double = 10
    var flexion: Double = 0
    /// Forearm flexion. Positive bends the hand towards the midline, which is
    /// what a hanging arm does; negative bends it up and out, which is what a
    /// goalpost or a W position does.
    var elbow: Double = 10
    var shoulderLift: Double = 0
    var anchor: HandAnchor = .free
    /// How far the elbow breaks away from the shoulder-to-hand line when an
    /// anchor is solved by inverse kinematics. 1 is the anatomically correct
    /// outward solution, -1 the inward one, and values in between shorten the
    /// drawn offset -- which is not a cheat but a foreshortening: an elbow
    /// pointing at the viewer really does project onto a shorter line.
    var elbowOut: Double = 1

    static func lerp(_ a: ArmPose, _ b: ArmPose, _ t: Double) -> ArmPose {
        ArmPose(
            abduction: mix(a.abduction, b.abduction, t),
            flexion: mix(a.flexion, b.flexion, t),
            elbow: mix(a.elbow, b.elbow, t),
            shoulderLift: mix(a.shoulderLift, b.shoulderLift, t),
            // Anchors are invariant across an exercise's keyframes, so taking
            // the destination's is exact rather than a compromise.
            anchor: t < 0.5 ? a.anchor : b.anchor,
            elbowOut: mix(a.elbowOut, b.elbowOut, t)
        )
    }

    /// Mirrored across the midline, for generating the second side of a
    /// bilateral exercise from a single authored pose.
    var mirrored: ArmPose {
        var copy = self
        copy.anchor = anchor.mirrored
        return copy
    }
}

extension HandAnchor {
    var mirrored: HandAnchor {
        switch self {
        case .torso(let p): return .torso(CGPoint(x: -p.x, y: p.y))
        case .world(let p): return .world(CGPoint(x: -p.x, y: p.y))
        case .headPoint(let p): return .headPoint(CGPoint(x: -p.x, y: p.y))
        default: return self
        }
    }
}

/// A single frame of body configuration. Every field defaults to a relaxed
/// upright posture, so a pose in the exercise library only states what actually
/// differs from sitting still — which is what makes the library readable.
struct Pose: Equatable {
    /// Degrees; + tips the right ear toward the right shoulder.
    var headTilt: Double = 0
    /// Degrees; + turns the face to the figure's right.
    var headTurn: Double = 0
    /// Degrees; + drops the chin toward the chest, - lifts it.
    var headNod: Double = 0
    /// Head units; + pokes the chin forward, - retracts it.
    var headSlide: Double = 0
    /// 0 = neutral, 1 = shoulder blades fully drawn together.
    var scapulaSqueeze: Double = 0
    /// 0 = neutral, 1 = chest wide and arms carried behind the frontal plane.
    var chestOpen: Double = 0
    /// -1 = slumped thoracic flexion, +1 = thoracic extension.
    var thoracic: Double = 0
    /// Degrees; + leans the torso toward the figure's right.
    var torsoTilt: Double = 0
    /// Degrees; + rotates the torso toward the figure's right.
    var torsoTurn: Double = 0
    var left = ArmPose()
    var right = ArmPose()

    static let neutral = Pose()

    static func lerp(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        Pose(
            headTilt: mix(a.headTilt, b.headTilt, t),
            headTurn: mix(a.headTurn, b.headTurn, t),
            headNod: mix(a.headNod, b.headNod, t),
            headSlide: mix(a.headSlide, b.headSlide, t),
            scapulaSqueeze: mix(a.scapulaSqueeze, b.scapulaSqueeze, t),
            chestOpen: mix(a.chestOpen, b.chestOpen, t),
            thoracic: mix(a.thoracic, b.thoracic, t),
            torsoTilt: mix(a.torsoTilt, b.torsoTilt, t),
            torsoTurn: mix(a.torsoTurn, b.torsoTurn, t),
            left: ArmPose.lerp(a.left, b.left, t),
            right: ArmPose.lerp(a.right, b.right, t)
        )
    }

    /// The same pose performed to the other side. Bilateral exercises author
    /// one direction and derive the other from this, which guarantees the two
    /// sides stay symmetrical as poses are tweaked.
    var mirrored: Pose {
        Pose(
            headTilt: -headTilt,
            headTurn: -headTurn,
            headNod: headNod,
            headSlide: headSlide,
            scapulaSqueeze: scapulaSqueeze,
            chestOpen: chestOpen,
            thoracic: thoracic,
            torsoTilt: -torsoTilt,
            torsoTurn: -torsoTurn,
            left: right.mirrored,
            right: left.mirrored
        )
    }
}

// MARK: - Interpolation helpers

func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// Smooth acceleration and deceleration. Stretches look wrong with linear
/// motion: real movement into end range slows down as tissue tightens.
func easeInOut(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * (3 - 2 * x)
}
