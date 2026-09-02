import AppKit
import SwiftUI

/// Renders the break window to a PNG without opening a window.
///
/// `Nikamat --render-break <file> [tier] [seconds]` snapshots the layout at a
/// chosen point inside a break, which is the only practical way to review the
/// window's proportions and wording without a screen recording permission and
/// a stopwatch.
@MainActor
enum BreakPreview {
    static func render(to file: String, tier: Tier, secondsIn: Double) {
        let settings = Settings()
        let plan = BreakPlanner.plan(
            tier: tier, settings: settings, lastUsed: BreakLog.shared.lastUsed()
        )
        guard !plan.steps.isEmpty else {
            FileHandle.standardError.write(Data("tyhjä suunnitelma\n".utf8))
            return
        }
        // Backdating the session's start is what puts the preview mid-exercise
        // instead of at the very first frame.
        let session = BreakSession(plan: plan, now: Date().addingTimeInterval(-secondsIn))
        let view = BreakView(session: session, onSnooze: {}, onClose: {})
            .frame(width: 520, height: 640)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("renderöinti ei onnistunut\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: file))
        let names = plan.steps.map { step in
            step.sideLabel.map { "\(step.exercise.name) (\($0))" } ?? step.exercise.name
        }
        print("""
            \(tier.title): \(plan.steps.count) vaihetta, \(Int(plan.duration)) s
            \(names.joined(separator: "\n"))
            """)
    }
}
