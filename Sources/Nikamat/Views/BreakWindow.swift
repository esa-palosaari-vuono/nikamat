import AppKit
import SwiftUI

/// Where a running break is shown. `BreakCoordinator` talks to this rather than
/// to a window, so the lifecycle can be exercised without AppKit.
@MainActor
protocol BreakDisplay: AnyObject {
    /// Called when the user closes the window by its own close button.
    var onUserClose: (() -> Void)? { get set }
    func show(session: BreakSession, log: BreakLog, onSnooze: @escaping () -> Void, onClose: @escaping () -> Void)
    func close()
}

/// The break window: a floating panel rather than a full-screen takeover. It
/// is impossible to miss but always possible to close, which is the difference
/// between a reminder and a hostage situation.
///
/// This class knows about windows and nothing else. What a close or a snooze
/// means for the break is `BreakCoordinator`'s business.
@MainActor
final class BreakWindow: BreakDisplay {
    var onUserClose: (() -> Void)?

    private var window: NSWindow?

    func show(
        session: BreakSession,
        log: BreakLog,
        onSnooze: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        close()
        let view = BreakView(session: session, log: log, onSnooze: onSnooze, onClose: onClose)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = session.plan.tier.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        // Follow the user to whichever Space they are working in, instead of
        // yanking them back to the one the app happened to launch on.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        place(window)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let window else { return }
        self.window = nil
        // orderOut rather than close: close() would call windowWillClose and
        // report a user close for a window the app is taking down itself.
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Centre the window on the display the user is actually looking at.
    ///
    /// `NSWindow.center()` uses the "main" screen, which on a multi-display
    /// desk is whichever screen last had key focus -- not necessarily the one
    /// in front of you. A break window that opens on a dark secondary display
    /// is worse than no break window: macOS stops rendering fully occluded
    /// windows, so it is invisible *and* it counts as shown. The mouse pointer
    /// is the cheapest reliable answer to "where is the user".
    private func place(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let area = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        window.setFrameOrigin(CGPoint(
            x: (area.midX - size.width / 2).rounded(),
            // Slightly above centre: it sits better in the visual field than
            // dead centre, and clears a dock at the bottom.
            y: (area.midY - size.height / 2 + size.height * 0.06).rounded()
        ))
    }

    private lazy var windowDelegate = WindowDelegate { [weak self] in
        guard let self else { return }
        self.window = nil
        self.onUserClose?()
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        private let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}
