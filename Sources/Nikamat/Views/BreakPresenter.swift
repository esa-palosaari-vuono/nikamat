import AppKit
import SwiftUI

/// Owns the break window and the session inside it.
///
/// The window is a floating panel rather than a full-screen takeover: it is
/// impossible to miss but always possible to close, which is the difference
/// between a reminder and a hostage situation.
@MainActor
final class BreakPresenter {
    /// Called when the break window has closed, for any reason.
    var onDismiss: (() -> Void)?
    /// Called when the user asked to be reminded again shortly.
    var onSnooze: (() -> Void)?

    private var window: NSWindow?
    private var session: BreakSession?
    private var plan: BreakPlan?
    private var startedAt = Date()
    private var closeTask: Task<Void, Never>?

    var isPresenting: Bool { window != nil }

    func present(plan: BreakPlan) {
        guard !plan.steps.isEmpty else { return }
        // A second break arriving while one is open would stack windows; the
        // one already on screen is the one the user is in the middle of.
        guard window == nil else { return }

        self.plan = plan
        startedAt = Date()
        let session = BreakSession(plan: plan)
        self.session = session

        session.onFinish = { [weak self] outcome, steps in
            guard let self, let plan = self.plan else { return }
            BreakLog.shared.record(
                plan: plan, outcome: outcome, steps: steps, startedAt: self.startedAt
            )
            // Leave the closing screen up briefly: it is the only feedback
            // that the break counted.
            self.closeTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(outcome == .completed ? 2.4 : 1.2))
                self.close()
            }
        }

        let view = BreakView(
            session: session,
            onSnooze: { [weak self] in
                self?.finish(.snoozed)
                self?.onSnooze?()
            },
            onClose: { [weak self] in self?.finish(.partial) }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = plan.tier.title
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

    /// End the break with an explicit outcome, then let `onFinish` close up.
    private func finish(_ outcome: BreakOutcome) {
        guard let session, session.finished == nil else {
            close()
            return
        }
        if outcome == .snoozed || outcome == .partial {
            // A break the user walked away from still deserves credit for the
            // steps that were completed, so record the outcome the session
            // itself worked out where there is one.
            session.end(outcome)
        }
    }

    private func close() {
        // Both the window's close button and the session's own completion
        // timer can arrive here; only the first should count.
        guard window != nil else { return }
        closeTask?.cancel()
        closeTask = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        session = nil
        plan = nil
        onDismiss?()
    }

    /// Closing the window with its close button has to run the same path as the
    /// Sulje button, or a break could end without being logged.
    private lazy var windowDelegate: WindowDelegate = WindowDelegate { [weak self] in
        self?.finish(.partial)
        self?.close()
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        private let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}
