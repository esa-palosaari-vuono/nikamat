import CoreGraphics
import Foundation

/// Everything the renderer needs to draw one frame, in body space.
///
/// Resolving a pose happens in one place, before any drawing, because several
/// parts depend on each other: an assisting hand has to know where the head
/// ended up after the tilt, and the scapulae have to know where the shoulders
/// ended up after the shrug.
struct Skeleton {
    var neck: CGPoint
    var headCenter: CGPoint
    /// Where the neck meets the skull. The neck is drawn to here rather than
    /// to the head's centre, so it never appears to run through the skull.
    var headBottom: CGPoint
    /// Rotation of the head about the neck base, in radians.
    var headAngle: Double
    /// Horizontal offset of the facial features, -1...1, for the front view's
    /// depiction of a turned head.
    var faceOffset: Double
    var headScaleX: Double
    /// Vertical foreshortening of the head. Seen from the front, a nod is not
    /// a rotation but a projection: the face tips away from the viewer and the
    /// skull draws shorter. Without this, "lower your nose towards your
    /// armpit" is completely invisible from the front.
    var headScaleY: Double
    /// Nod, in radians, for the renderer's facial detail.
    var headNod: Double
    var leftShoulder: CGPoint
    var rightShoulder: CGPoint
    var leftHip: CGPoint
    var rightHip: CGPoint
    var leftArm: ArmChain
    var rightArm: ArmChain
    /// Sampled spine, hips first, neck last. The side and back views draw it.
    var spine: [CGPoint]
    /// Half-distance from the spine to each shoulder blade, back view only.
    var scapulaGap: Double
    var scapulaY: Double

    static func resolve(_ pose: Pose, orientation: Orientation) -> Skeleton {
        let hipCenter = CGPoint(x: 0, y: Body.hipY)
        let tilt = radians(pose.torsoTilt)
        let turnFactor = cos(radians(pose.torsoTurn))

        // The trunk leans as a unit about the hips, so everything above it
        // inherits the lean.
        func leaned(_ p: CGPoint) -> CGPoint {
            tilt == 0 ? p : rotate(p, around: hipCenter, by: tilt)
        }

        // Thoracic extension lifts and slightly straightens the trunk;
        // flexion sinks it. 0.06 hu is small on purpose: this is a posture
        // change, not a growth spurt.
        let neckRaw = CGPoint(x: 0, y: -0.06 * pose.thoracic)
        let neck = leaned(neckRaw)

        // Shoulders. In the frontal and back views they sit at the body's
        // half-width, widening as the chest opens and foreshortening as the
        // trunk turns. Seen from the side, both shoulders project onto almost
        // the same place -- just in front of the spine -- so the half-width
        // would fling the arm out into empty space ahead of the chest.
        let half = orientation == .side
            ? 0.18
            : Body.shoulderHalf * (1 + 0.10 * pose.chestOpen) * turnFactor
        func shoulder(_ side: Double, _ arm: ArmPose) -> CGPoint {
            let raw = CGPoint(
                x: (orientation == .side ? half : side * half)
                    + sin(radians(pose.torsoTurn)) * 0.10,
                y: neckRaw.y + Body.shoulderY - 0.30 * arm.shoulderLift - 0.03 * pose.thoracic
            )
            return leaned(raw)
        }
        let leftShoulder = shoulder(-1, pose.left)
        let rightShoulder = shoulder(1, pose.right)

        // Head. In the frontal plane the tilt is a rotation about the neck
        // base; in the sagittal plane it is the nod, plus the forward or
        // retracted slide that the chin-tuck drill is all about.
        let headAngle: Double
        var headRaw: CGPoint
        switch orientation {
        case .front, .back:
            headAngle = radians(pose.headTilt)
            headRaw = CGPoint(
                x: neckRaw.x,
                y: neckRaw.y + Body.headCenter.y + 0.10 * sin(radians(pose.headNod))
            )
        case .side:
            headAngle = radians(pose.headNod)
            headRaw = CGPoint(x: neckRaw.x + pose.headSlide, y: neckRaw.y + Body.headCenter.y)
        }
        let headCenter = leaned(rotate(headRaw, around: neckRaw, by: headAngle))
        let headBottom = leaned(rotate(
            CGPoint(x: headRaw.x, y: headRaw.y + Body.headRadiusY * 0.88),
            around: neckRaw, by: headAngle
        ))

        // Hands are resolved against the geometry above, so an anchored hand
        // tracks whatever it is holding on to.
        func hand(_ side: Double, _ arm: ArmPose, shoulder: CGPoint) -> CGPoint? {
            switch arm.anchor {
            case .free:
                return nil
            case .world(let p):
                return p
            case .torso(let p):
                return leaned(CGPoint(x: p.x * turnFactor, y: neckRaw.y + p.y))
            case .headPoint(let local):
                let onHead = CGPoint(x: headRaw.x + local.x, y: headRaw.y + local.y)
                return leaned(rotate(onHead, around: neckRaw, by: headAngle))
            case .headBack:
                let local = CGPoint(
                    x: headRaw.x + side * Body.headRadiusX * 0.78,
                    y: headRaw.y + 0.04
                )
                return leaned(rotate(local, around: neckRaw, by: headAngle))
            case .lowBack:
                // Clasped hands meet near the midline at the small of the
                // back, low enough that the upper arms hang down the sides
                // instead of crossing over the stomach.
                return leaned(CGPoint(x: side * 0.09, y: neckRaw.y + Body.hipY - 0.10))
            }
        }

        func arm(_ side: Double, _ arm: ArmPose, shoulder: CGPoint) -> ArmChain {
            if let target = hand(side, arm, shoulder: shoulder) {
                let elbow = solveElbow(
                    shoulder: shoulder, hand: target,
                    elbowOut: arm.elbowOut, side: side
                )
                return ArmChain(shoulder: shoulder, elbow: elbow, hand: target)
            }
            let swing = orientation == .side ? arm.flexion : arm.abduction
            // An opening chest carries the arms further out to the sides even
            // when no anchor names a position for them.
            return chainFromAngles(
                shoulder: shoulder,
                swing: swing + 12 * pose.chestOpen,
                bend: arm.elbow,
                side: side
            )
        }

        // Spine: a quadratic bow whose depth is the thoracic parameter. In the
        // side view the bow is sagittal (a slump bulges backwards, away from
        // the face at +x); in the back view it shows as a slight lateral sway
        // from the trunk lean only.
        let bow = orientation == .side ? 0.30 * pose.thoracic : 0
        let spine: [CGPoint] = stride(from: 0.0, through: 1.0, by: 0.1).map { t in
            let control = CGPoint(x: bow, y: Body.hipY * 0.45 + neckRaw.y * 0.55)
            let x = (1 - t) * (1 - t) * hipCenter.x + 2 * (1 - t) * t * control.x + t * t * neckRaw.x
            let y = (1 - t) * (1 - t) * hipCenter.y + 2 * (1 - t) * t * control.y + t * t * neckRaw.y
            return leaned(CGPoint(x: x, y: y))
        }

        let averageLift = (pose.left.shoulderLift + pose.right.shoulderLift) / 2
        return Skeleton(
            neck: neck,
            headCenter: headCenter,
            headBottom: headBottom,
            headAngle: headAngle,
            faceOffset: sin(radians(pose.headTurn)),
            headScaleX: 1 - 0.14 * abs(sin(radians(pose.headTurn))),
            headScaleY: orientation == .side
                ? 1
                : 1 - 0.32 * abs(sin(radians(pose.headNod))),
            headNod: radians(pose.headNod),
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: leaned(CGPoint(x: -Body.hipHalf * turnFactor, y: Body.hipY)),
            rightHip: leaned(CGPoint(x: Body.hipHalf * turnFactor, y: Body.hipY)),
            leftArm: arm(-1, pose.left, shoulder: leftShoulder),
            rightArm: arm(1, pose.right, shoulder: rightShoulder),
            spine: spine,
            // Retraction pulls the blades towards the spine; a shrug rides
            // them up, a depression drags them down.
            scapulaGap: 0.31 - 0.19 * pose.scapulaSqueeze,
            scapulaY: neckRaw.y + 0.44 - 0.18 * averageLift
        )
    }
}
