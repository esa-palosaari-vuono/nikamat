import CoreGraphics
import Foundation

// MARK: - Small vector helpers
//
// Core Graphics gives us points but no arithmetic, and the kinematics below
// reads far better with it than with x/y bookkeeping at every step.

func + (a: CGPoint, b: CGVector) -> CGPoint { CGPoint(x: a.x + b.dx, y: a.y + b.dy) }
func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
func * (v: CGVector, s: Double) -> CGVector { CGVector(dx: v.dx * s, dy: v.dy * s) }

extension CGVector {
    var length: Double { (dx * dx + dy * dy).squareRoot() }
    var normalized: CGVector { length > 1e-9 ? self * (1 / length) : CGVector(dx: 0, dy: 1) }
    /// Rotated 90° counter-clockwise on screen (y grows downwards).
    var perpendicular: CGVector { CGVector(dx: -dy, dy: dx) }
}

func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

/// Rotate `point` around `pivot`. Positive angles turn clockwise on screen,
/// because y grows downwards in view coordinates.
func rotate(_ point: CGPoint, around pivot: CGPoint, by angle: Double) -> CGPoint {
    let dx = point.x - pivot.x, dy = point.y - pivot.y
    let c = cos(angle), s = sin(angle)
    return CGPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
}

/// The three joints of one arm, in body space.
struct ArmChain {
    var shoulder: CGPoint
    var elbow: CGPoint
    var hand: CGPoint
}

/// Place the elbow for a two-link arm whose shoulder and hand are both known.
///
/// There are two exact solutions in the plane, mirror images across the
/// shoulder-to-hand line, and `elbowOut` picks between them: +1 is the
/// anatomical one (elbow away from the midline), -1 the reverse. Fractional
/// values shorten the offset, which is not an anatomical fudge but a
/// projection: an elbow pointing towards the viewer genuinely draws as a
/// shorter line than one pointing sideways.
func solveElbow(
    shoulder: CGPoint,
    hand: CGPoint,
    upper: Double = Body.upperArm,
    fore: Double = Body.foreArm,
    elbowOut: Double,
    side: Double
) -> CGPoint {
    let toHand = hand - shoulder
    let d = min(toHand.length, upper + fore - 1e-4)
    guard d > 1e-6 else { return shoulder + CGVector(dx: 0, dy: upper) }
    let dir = toHand.normalized
    // Distance from the shoulder to the foot of the elbow's perpendicular.
    let a = (upper * upper - fore * fore + d * d) / (2 * d)
    let h = (max(0, upper * upper - a * a)).squareRoot()
    let midpoint = shoulder + dir * a
    return midpoint + dir.perpendicular * (h * elbowOut * side)
}

/// Forward kinematics for an arm described by joint angles.
///
/// `swing` is the angle away from straight down in the drawing plane — that is
/// abduction in the front and back views, flexion in the side view — and
/// `bend` flexes the forearm towards the midline.
func chainFromAngles(
    shoulder: CGPoint,
    swing: Double,
    bend: Double,
    side: Double
) -> ArmChain {
    let swingRad = radians(swing) * side
    let upperDir = CGVector(dx: sin(swingRad), dy: cos(swingRad))
    let elbow = shoulder + upperDir * Body.upperArm
    let foreDir = CGVector(
        dx: sin(swingRad - radians(bend) * side),
        dy: cos(swingRad - radians(bend) * side)
    )
    return ArmChain(shoulder: shoulder, elbow: elbow, hand: elbow + foreDir * Body.foreArm)
}
