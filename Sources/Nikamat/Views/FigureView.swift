import SwiftUI

/// Draws the exercising figure for one pose.
///
/// The figure is a torso, head and arms — no legs, because every exercise in
/// the library happens above the hips and a pair of legs would only shrink the
/// part you need to look at. Everything is drawn in *head units* and scaled to
/// the canvas at the end, so the same pose data works at any size.
struct FigureView: View {
    let pose: Pose
    let orientation: Orientation
    let highlight: Highlight
    let prop: Prop?

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var renderer = FigureRenderer(
                skeleton: Skeleton.resolve(pose, orientation: orientation),
                pose: pose,
                orientation: orientation,
                highlight: highlight,
                prop: prop,
                size: size
            )
            renderer.draw(into: &context)
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// The drawing itself. Kept as a struct with the transform precomputed so the
/// individual body parts read as drawing instructions rather than arithmetic.
struct FigureRenderer {
    let skeleton: Skeleton
    let pose: Pose
    let orientation: Orientation
    let highlight: Highlight
    let prop: Prop?
    let size: CGSize

    // Palette. `ink` and the fills are semantic colours so the figure follows
    // the system appearance; the accent is fixed, because it has to read as
    // "this is the part that is working" in both light and dark.
    private let ink = Color.primary.opacity(0.80)
    private let fill = Color.primary.opacity(0.055)
    private let propColor = Color.primary.opacity(0.085)
    private let accent = Color(red: 0.89, green: 0.42, blue: 0.22)

    /// Extent of the drawing in head units: wide enough for a doorframe, tall
    /// enough for both hands overhead and hands hanging past the hips.
    private var extent: CGSize {
        // Props push the hands wider than the body ever goes on its own.
        CGSize(width: prop == nil ? 3.10 : 3.55, height: 3.55)
    }
    /// Body-space y that lands in the middle of the canvas.
    private let verticalCentre = 0.12
    private var scale: Double {
        min(size.width / extent.width, size.height / extent.height) * 0.96
    }

    /// Body space to canvas. Body y = 0.05 is the vertical middle of the
    /// figure, so that is what lands in the middle of the canvas.
    private func p(_ q: CGPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + q.x * scale, y: size.height / 2 + (q.y - verticalCentre) * scale)
    }

    /// A width given in head units, in canvas points.
    private func w(_ units: Double) -> Double { units * scale }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        Path { $0.move(to: p(a)); $0.addLine(to: p(b)) }
    }

    private func polyline(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: p(first))
            for point in points.dropFirst() { path.addLine(to: p(point)) }
        }
    }

    private func dot(_ center: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(
            x: p(center).x - w(radius), y: p(center).y - w(radius),
            width: w(radius) * 2, height: w(radius) * 2
        ))
    }

    private func round(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: w(width), lineCap: .round, lineJoin: .round)
    }

    mutating func draw(into context: inout GraphicsContext) {
        drawProp(&context)
        drawHighlightGlow(&context)
        drawArms(&context, layer: .behind)
        switch orientation {
        case .front: drawTorsoFrontal(&context)
        case .back:
            drawTorsoFrontal(&context)
            drawScapulae(&context)
        case .side: drawTorsoSagittal(&context)
        }
        drawNeckAndHead(&context)
        drawArms(&context, layer: .front)
    }

    // MARK: - Props

    private func drawProp(_ context: inout GraphicsContext) {
        guard let prop else { return }
        switch prop {
        case .wall:
            // A plain panel with a few hairlines: enough to read as "wall"
            // without competing with the figure for attention.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(propColor.opacity(0.5))
            )
            for x in stride(from: -1.5, through: 1.5, by: 0.75) {
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: p(CGPoint(x: x, y: 0)).x, y: 0))
                        path.addLine(to: CGPoint(x: p(CGPoint(x: x, y: 0)).x, y: size.height))
                    },
                    with: .color(propColor), lineWidth: w(0.012)
                )
            }
        case .doorway:
            for side in [-1.0, 1.0] {
                let post = Path(CGRect(
                    x: p(CGPoint(x: side * Body.doorwayHalf - 0.075, y: 0)).x,
                    y: p(CGPoint(x: 0, y: -1.55)).y,
                    width: w(0.15),
                    height: w(3.15)
                ))
                context.fill(post, with: .color(propColor))
            }
            let lintel = Path(CGRect(
                x: p(CGPoint(x: -Body.doorwayHalf - 0.075, y: 0)).x,
                y: p(CGPoint(x: 0, y: -1.55)).y,
                width: w(Body.doorwayHalf * 2 + 0.15),
                height: w(0.15)
            ))
            context.fill(lintel, with: .color(propColor))
        }
    }

    // MARK: - Highlight

    /// A soft accent laid *under* the figure, so the target area glows without
    /// the line work losing its crispness.
    private func drawHighlightGlow(_ context: inout GraphicsContext) {
        let glow = accent.opacity(0.22)
        switch highlight {
        case .none, .scapulae:
            // Scapulae are accented by tinting the blades themselves.
            return
        case .neck:
            context.stroke(
                line(CGPoint(x: skeleton.neck.x, y: skeleton.neck.y + 0.14), skeleton.headBottom),
                with: .color(glow), style: round(0.30)
            )
        case .traps:
            // A side bend stretches the side you are bending *away* from, so
            // the glow follows the tension instead of lighting up both sides
            // and telling the user nothing.
            for (side, shoulder) in [(-1.0, skeleton.leftShoulder), (1.0, skeleton.rightShoulder)] {
                let tension = pose.headTilt * -side
                let strength = 0.30 + 0.70 * min(1, max(0, tension / 25))
                let path = Path { path in
                    path.move(to: p(skeleton.neck))
                    path.addQuadCurve(
                        to: p(shoulder),
                        control: p(CGPoint(x: shoulder.x * 0.45, y: skeleton.neck.y - 0.10))
                    )
                }
                context.stroke(path, with: .color(accent.opacity(0.24 * strength)), style: round(0.24))
            }
        case .shoulders:
            for shoulder in [skeleton.leftShoulder, skeleton.rightShoulder] {
                context.fill(dot(shoulder, radius: 0.30), with: .color(glow))
            }
        case .chest:
            let path = Path { path in
                path.move(to: p(CGPoint(x: skeleton.leftShoulder.x + 0.24, y: skeleton.leftShoulder.y + 0.10)))
                path.addQuadCurve(
                    to: p(CGPoint(x: skeleton.rightShoulder.x - 0.24, y: skeleton.rightShoulder.y + 0.10)),
                    control: p(CGPoint(x: 0, y: skeleton.neck.y + 0.36))
                )
            }
            context.stroke(path, with: .color(glow), style: round(0.16))
        case .thoracic:
            let thoracicPart = orientation == .side
                ? skeleton.spine
                : Array(skeleton.spine.suffix(6))
            context.stroke(polyline(thoracicPart), with: .color(glow), style: round(0.34))
        }
    }

    // MARK: - Torso

    /// Front and back views share a torso: a tapered trunk with deltoid caps.
    private func drawTorsoFrontal(_ context: inout GraphicsContext) {
        let ls = skeleton.leftShoulder, rs = skeleton.rightShoulder
        let lh = skeleton.leftHip, rh = skeleton.rightHip
        let neckTop = CGPoint(x: skeleton.neck.x, y: skeleton.neck.y + 0.02)
        let trunk = Path { path in
            path.move(to: p(ls))
            // The slope from shoulder up to the neck: this single curve is
            // most of what makes the figure read as a body and not a crate.
            path.addQuadCurve(
                to: p(neckTop),
                control: p(CGPoint(x: ls.x * 0.40, y: ls.y - 0.02))
            )
            path.addQuadCurve(
                to: p(rs),
                control: p(CGPoint(x: rs.x * 0.40, y: rs.y - 0.02))
            )
            // Down the right side, narrowing at the waist.
            path.addCurve(
                to: p(rh),
                control1: p(CGPoint(x: rs.x + 0.03, y: rs.y + 0.30)),
                control2: p(CGPoint(x: rh.x + 0.06, y: rh.y - 0.42))
            )
            // A rounded pelvis, because a flat cut looks like furniture.
            path.addQuadCurve(to: p(lh), control: p(CGPoint(x: 0, y: Body.hipY + 0.20)))
            path.addCurve(
                to: p(ls),
                control1: p(CGPoint(x: lh.x - 0.06, y: lh.y - 0.42)),
                control2: p(CGPoint(x: ls.x - 0.03, y: ls.y + 0.30))
            )
            path.closeSubpath()
        }
        context.fill(trunk, with: .color(fill))
        context.stroke(trunk, with: .color(ink), style: round(0.05))
        for shoulder in [ls, rs] {
            context.fill(dot(shoulder, radius: 0.135), with: .color(ink))
        }
    }

    /// Side view: the spine carries the posture, and the chest wall is drawn as
    /// an offset from it, so thoracic flexion and extension are visible as the
    /// whole trunk changing shape rather than as a tilted rectangle.
    private func drawTorsoSagittal(_ context: inout GraphicsContext) {
        let spine = skeleton.spine
        let front: [CGPoint] = spine.enumerated().map { index, point in
            let t = Double(index) / Double(max(spine.count - 1, 1))
            let depth = 0.46 + 0.18 * sin(.pi * t)
            return CGPoint(x: point.x + depth, y: point.y)
        }
        let trunk = Path { path in
            path.move(to: p(spine[0]))
            for point in spine.dropFirst() { path.addLine(to: p(point)) }
            for point in front.reversed() { path.addLine(to: p(point)) }
            path.closeSubpath()
        }
        context.fill(trunk, with: .color(fill))
        context.stroke(trunk, with: .color(ink), style: round(0.05))
        context.stroke(polyline(spine), with: .color(ink.opacity(0.55)), style: round(0.035))
        context.fill(dot(skeleton.rightShoulder, radius: 0.135), with: .color(ink))
    }

    /// Back view only: the shoulder blades, whose whole job is to be visibly
    /// closer together when the user retracts them.
    private func drawScapulae(_ context: inout GraphicsContext) {
        let tinted = highlight == .scapulae
        for side in [-1.0, 1.0] {
            let cx = side * (skeleton.scapulaGap + 0.15)
            let cy = skeleton.scapulaY
            let blade = Path { path in
                let top = CGPoint(x: cx - side * 0.13, y: cy - 0.21)
                let outer = CGPoint(x: cx + side * 0.17, y: cy - 0.11)
                let bottom = CGPoint(x: cx + side * 0.02, y: cy + 0.24)
                path.move(to: p(top))
                path.addQuadCurve(to: p(outer), control: p(CGPoint(x: cx + side * 0.09, y: cy - 0.22)))
                path.addQuadCurve(to: p(bottom), control: p(CGPoint(x: cx + side * 0.16, y: cy + 0.12)))
                path.addQuadCurve(to: p(top), control: p(CGPoint(x: cx - side * 0.14, y: cy + 0.02)))
                path.closeSubpath()
            }
            context.fill(blade, with: .color(tinted ? accent.opacity(0.55) : Color.primary.opacity(0.16)))
            context.stroke(blade, with: .color(tinted ? accent : ink.opacity(0.7)), style: round(0.035))
        }
        // The spine, so "towards the spine" has something to be towards.
        var dashed = round(0.03)
        dashed.dash = [w(0.07), w(0.06)]
        context.stroke(
            line(CGPoint(x: 0, y: skeleton.neck.y + 0.12), CGPoint(x: 0, y: Body.hipY - 0.18)),
            with: .color(ink.opacity(0.45)), style: dashed
        )
    }

    // MARK: - Head

    private func drawNeckAndHead(_ context: inout GraphicsContext) {
        context.stroke(
            line(CGPoint(x: skeleton.neck.x, y: skeleton.neck.y + 0.10), skeleton.headBottom),
            with: .color(ink), style: round(0.20)
        )

        // Draw the head in its own rotated context so the features tilt and
        // nod with the skull instead of sliding around on it.
        var head = context
        head.translateBy(x: p(skeleton.headCenter).x, y: p(skeleton.headCenter).y)
        head.rotate(by: .radians(skeleton.headAngle))

        let rx = w(Body.headRadiusX * skeleton.headScaleX)
        let ry = w(Body.headRadiusY * skeleton.headScaleY)
        let skull = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        head.fill(skull, with: .color(fill))
        head.stroke(skull, with: .color(ink), lineWidth: w(0.055))

        let feature = Color.primary.opacity(0.62)
        func spot(_ x: Double, _ y: Double, _ r: Double) -> Path {
            Path(ellipseIn: CGRect(x: x - w(r), y: y - w(r), width: w(r) * 2, height: w(r) * 2))
        }

        switch orientation {
        case .front:
            // A turned head is drawn by sliding the features towards the
            // direction of gaze and putting the far ear into view.
            let shift = skeleton.faceOffset * rx * 0.52
            // Features slide towards the chin as the face tips away, and the
            // crown comes into view.
            let drop = ry * 0.34 * sin(skeleton.headNod)
            head.fill(spot(shift - rx * 0.34, -ry * 0.14 + drop, 0.045), with: .color(feature))
            head.fill(spot(shift + rx * 0.34, -ry * 0.14 + drop, 0.045), with: .color(feature))
            let mouth = Path { path in
                path.move(to: CGPoint(x: shift - rx * 0.26, y: ry * 0.38 + drop))
                path.addQuadCurve(
                    to: CGPoint(x: shift + rx * 0.26, y: ry * 0.38 + drop),
                    control: CGPoint(x: shift, y: ry * 0.50 + drop)
                )
            }
            head.stroke(mouth, with: .color(feature), style: round(0.035))
            // A pronounced nod brings the top of the head into view, which
            // together with the vertical foreshortening is what makes "nose
            // towards the armpit" legible from the front.
            if skeleton.headNod > 0.26 {
                let crown = Path { path in
                    path.move(to: CGPoint(x: -rx * 0.76, y: -ry * 0.30))
                    path.addQuadCurve(
                        to: CGPoint(x: rx * 0.76, y: -ry * 0.30),
                        control: CGPoint(x: 0, y: -ry * 1.02)
                    )
                }
                head.stroke(crown, with: .color(feature.opacity(0.45)), style: round(0.032))
            }
            // Ears are drawn in every front-facing pose: they are the clearest
            // cue for how far the head has tilted, and when the head turns the
            // near one slides out of view while the far one comes into it.
            for earSide in [-1.0, 1.0] {
                let visibility = 1 - max(0, skeleton.faceOffset * earSide) * 0.9
                guard visibility > 0.2 else { continue }
                let ear = Path(ellipseIn: CGRect(
                    x: earSide * rx * 0.90 - w(0.055), y: -w(0.055),
                    width: w(0.11), height: w(0.15)
                ))
                head.fill(ear, with: .color(ink.opacity(visibility)))
            }
        case .side:
            // Facing +x: a nose to make the direction unmistakable, plus the
            // jaw line, which is what makes a chin tuck legible.
            let nose = Path { path in
                path.move(to: CGPoint(x: rx * 0.86, y: -ry * 0.06))
                path.addLine(to: CGPoint(x: rx * 1.30, y: ry * 0.10))
                path.addLine(to: CGPoint(x: rx * 0.80, y: ry * 0.22))
            }
            head.stroke(nose, with: .color(ink), style: round(0.045))
            head.fill(spot(rx * 0.38, -ry * 0.16, 0.045), with: .color(feature))
            let jaw = Path { path in
                path.move(to: CGPoint(x: rx * 0.74, y: ry * 0.52))
                path.addQuadCurve(
                    to: CGPoint(x: -rx * 0.30, y: ry * 0.86),
                    control: CGPoint(x: rx * 0.30, y: ry * 0.92)
                )
            }
            head.stroke(jaw, with: .color(feature), style: round(0.035))
        case .back:
            // The back of a head is hard to draw without accidentally drawing
            // a face: any single arc across the middle reads as a mouth.
            // Strands falling from the crown do not have that problem.
            for strand in [-1.0, -0.33, 0.33, 1.0] {
                let hair = Path { path in
                    path.move(to: CGPoint(x: strand * rx * 0.26, y: -ry * 0.78))
                    path.addQuadCurve(
                        to: CGPoint(x: strand * rx * 0.66, y: ry * 0.62),
                        control: CGPoint(x: strand * rx * 0.62, y: -ry * 0.10)
                    )
                }
                head.stroke(hair, with: .color(feature.opacity(0.55)), style: round(0.03))
            }
            for earSide in [-1.0, 1.0] {
                let ear = Path(ellipseIn: CGRect(
                    x: earSide * rx * 0.92 - w(0.05), y: -w(0.05),
                    width: w(0.10), height: w(0.14)
                ))
                head.fill(ear, with: .color(ink))
            }
        }
    }

    // MARK: - Arms

    /// Whether an arm passes in front of the trunk or behind it.
    enum ArmLayer { case behind, front }

    /// An arm whose hand rests on the body — folded across the chest, laced
    /// behind the head — has to be drawn in front of the trunk to be visible.
    /// An arm hanging at the side belongs behind it, so the shoulder looks
    /// attached rather than pasted on.
    private func drawArms(_ context: inout GraphicsContext, layer: ArmLayer) {
        let sides: [(chain: ArmChain, pose: ArmPose)] = orientation == .side
            ? [(skeleton.rightArm, pose.right)]
            : [(skeleton.leftArm, pose.left), (skeleton.rightArm, pose.right)]
        let arms = sides.filter { entry in
            // Side view shows only the near arm, and the near arm is always in
            // front of the trunk.
            if orientation == .side { return layer == .front }
            let inFront: Bool
            switch entry.pose.anchor {
            case .free, .world, .lowBack: inFront = false
            case .torso, .headPoint, .headBack: inFront = true
            }
            return (layer == .front) == inFront
        }.map(\.chain)
        for arm in arms {
            context.stroke(
                polyline([arm.shoulder, arm.elbow, arm.hand]),
                with: .color(ink), style: round(0.115)
            )
            context.fill(dot(arm.hand, radius: 0.082), with: .color(ink))
        }
    }
}
