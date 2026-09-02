import AppKit

// Entry point. Two modes: the real menu bar app, and a headless pose-rendering
// mode used to review the exercise drawings (see PoseSheet).
//
// Top-level code runs on the main thread but is not itself actor-isolated, so
// the whole body is wrapped in an assertion of what is already true.
MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--render-poses"), index + 1 < arguments.count {
        PoseSheet.render(to: arguments[index + 1])
        exit(0)
    }
    if arguments.contains("--exercises") {
        ExerciseListing.printOrgTable()
        exit(0)
    }
    if arguments.contains("--selftest") {
        SelfTest.run()
        exit(0)
    }
    if let index = arguments.firstIndex(of: "--render-break"), index + 1 < arguments.count {
        let tier: Tier = arguments.contains("long") ? .long : .micro
        let seconds = arguments.compactMap(Double.init).first ?? 6
        BreakPreview.render(to: arguments[index + 1], tier: tier, secondsIn: seconds)
        exit(0)
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    // Accessory: menu bar only, no Dock icon and no menus of its own.
    application.setActivationPolicy(.accessory)
    application.run()
}
