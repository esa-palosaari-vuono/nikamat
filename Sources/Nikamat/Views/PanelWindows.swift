import AppKit
import SwiftUI

/// Keeps at most one window per identifier, so choosing "Asetukset…" twice
/// brings the existing window forward instead of opening a second copy.
@MainActor
final class PanelWindows {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: CGSize, view: Content) {
        if let existing = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
