import Foundation

/// Owns one break from start to finish: plans it, runs its session, logs how it
/// ended, and tells the schedule.
///
/// Every way a break can end goes through here — running to completion, the
/// Sulje button, the window's close button, Lykkää — and the outcome itself is
/// always decided by the session, which is the only party that knows which
/// steps were actually done.
@MainActor
final class BreakCoordinator {
    /// The break was snoozed; the schedule should bring this tier back.
    var onSnoozed: ((Tier) -> Void)?
    /// The break window has gone, for whatever reason.
    var onEnded: (() -> Void)?

    private let log: BreakLog
    private let display: BreakDisplay
    private let preferences: @MainActor () -> Preferences
    private let makeSession: @MainActor (BreakPlan) -> BreakSession
    /// Runs an action after a delay. Injected so tests need not wait.
    private let after: (Double, @escaping @MainActor () -> Void) -> Void

    private var session: BreakSession?

    var isRunning: Bool { session != nil }

    init(
        log: BreakLog,
        display: BreakDisplay,
        preferences: @escaping @MainActor () -> Preferences,
        makeSession: @escaping @MainActor (BreakPlan) -> BreakSession = { BreakSession(plan: $0) },
        after: @escaping (Double, @escaping @MainActor () -> Void) -> Void = { delay, action in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                action()
            }
        }
    ) {
        self.log = log
        self.display = display
        self.preferences = preferences
        self.makeSession = makeSession
        self.after = after
        display.onUserClose = { [weak self] in self?.userClosedWindow() }
    }

    func start(tier: Tier) {
        // A second break arriving while one is open would stack windows; the
        // one already on screen is the one the user is in the middle of.
        guard session == nil else { return }
        let plan = BreakPlanner.plan(tier: tier, preferences: preferences(), lastUsed: log.lastUsed())
        guard !plan.steps.isEmpty else { return }

        let session = makeSession(plan)
        let startedAt = Date()
        session.onFinish = { [weak self, weak session] outcome, steps in
            guard let self, let session else { return }
            self.finished(session, outcome: outcome, steps: steps, startedAt: startedAt)
        }
        self.session = session
        display.show(
            session: session,
            log: log,
            onSnooze: { [weak self] in self?.userRequestedEnd(snooze: true) },
            onClose: { [weak self] in self?.userRequestedEnd(snooze: false) }
        )
    }

    // MARK: - Ending

    /// Sulje or Lykkää. While the break runs this ends the session, which then
    /// reports back through `finished`; on the closing screen it just closes.
    private func userRequestedEnd(snooze: Bool) {
        guard let session else { return }
        guard session.finished == nil else { return dismiss() }
        if snooze { session.snooze() } else { session.abandon() }
    }

    /// The window's own close button: end the session if it is still running,
    /// so the break is logged, then drop it without the closing screen.
    private func userClosedWindow() {
        session?.abandon()
        dismiss(windowAlreadyClosed: true)
    }

    private func finished(
        _ session: BreakSession, outcome: BreakOutcome, steps: [LoggedStep], startedAt: Date
    ) {
        log.record(plan: session.plan, outcome: outcome, steps: steps, startedAt: startedAt)
        if outcome == .snoozed { onSnoozed?(session.plan.tier) }
        // Leave the closing screen up briefly: it is the only feedback that
        // the break counted.
        after(outcome == .completed ? 2.4 : 1.2) { [weak self, weak session] in
            // Only if this break is still the one on screen.
            guard let self, let session, self.session === session else { return }
            self.dismiss()
        }
    }

    private func dismiss(windowAlreadyClosed: Bool = false) {
        guard session != nil else { return }
        session = nil
        if !windowAlreadyClosed { display.close() }
        onEnded?()
    }
}
