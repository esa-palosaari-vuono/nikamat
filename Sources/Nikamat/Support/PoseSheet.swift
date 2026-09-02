import AppKit
import SwiftUI

/// Renders every exercise's start and end pose to a PNG contact sheet.
///
/// This exists because pose data is impossible to review by reading it: a
/// plausible-looking 30 degrees of head tilt can still come out as a figure
/// dislocating its own shoulder. `Nikamat --render-poses <dir>` makes the whole
/// library inspectable at a glance, which is also the fastest way to check that
/// a new exercise looks like the movement it claims to be.
@MainActor
enum PoseSheet {
    static func render(to directory: String) {
        let url = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for exercise in ExerciseLibrary.all {
            let sheet = SheetView(exercise: exercise)
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else {
                FileHandle.standardError.write(Data("render failed: \(exercise.id)\n".utf8))
                continue
            }
            try? png.write(to: url.appendingPathComponent("\(exercise.id).png"))
        }
        print("Renderöity \(ExerciseLibrary.all.count) liikettä hakemistoon \(directory)")
    }

    /// One exercise across the full sweep of its movement, sampled evenly so
    /// the in-between poses get reviewed too, not just the extremes.
    private struct SheetView: View {
        let exercise: Exercise

        /// Five poses spanning the movement's whole range.
        ///
        /// Sampling the *clock* would be misleading: a 25-second hold spends
        /// 24 of those seconds at full stretch, so five evenly spaced instants
        /// would show five identical figures. Sampling the keyframes shows
        /// what the movement actually travels through.
        private var samples: [Pose] {
            let frames = exercise.keyframes
            guard frames.count > 1 else { return frames }
            switch exercise.pattern {
            case .hold, .reps:
                return (0..<5).map { Pose.lerp(frames[0], frames[frames.count - 1], Double($0) / 4) }
            case .cycle:
                // Walk the keyframe ring, which is how a cycle is played back.
                return (0..<5).map { index in
                    let position = Double(index) / 5 * Double(frames.count)
                    let segment = Int(position) % frames.count
                    return Pose.lerp(
                        frames[segment],
                        frames[(segment + 1) % frames.count],
                        position - Double(Int(position))
                    )
                }
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(exercise.name)
                    .font(.system(size: 20, weight: .semibold))
                Text("\(exercise.region.label) · \(exercise.posture.label) · \(Int(exercise.pattern.duration)) s")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, pose in
                        FigureView(
                            pose: pose,
                            orientation: exercise.orientation,
                            highlight: exercise.highlight,
                            prop: exercise.prop
                        )
                        .frame(width: 200, height: 210)
                    }
                }
                Text(exercise.cue)
                    .font(.system(size: 13))
            }
            .padding(20)
            .frame(width: 1040)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
