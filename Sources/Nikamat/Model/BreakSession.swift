import Foundation

/// How a break ended, which is the interesting part of the log: a break you
/// snoozed away tells you more about your day than one you completed.
enum BreakOutcome: String, Codable {
    case completed
    case partial
    case skipped
    case snoozed

    var label: String {
        switch self {
        case .completed: return "tehty"
        case .partial: return "kesken"
        case .skipped: return "ohitettu"
        case .snoozed: return "lykätty"
        }
    }
}

/// One finished (or abandoned) step, ready to be written to the log.
struct LoggedStep {
    let exerciseID: String
    let exerciseName: String
    let region: Region
    let side: String?
    let plannedSeconds: Double
    let actualSeconds: Double
    let completed: Bool
}

/// A break in progress.
///
/// The session is the single owner of the clock. Timing is derived from
/// wall-clock timestamps rather than accumulated ticks, so the countdown stays
/// truthful even if the app is starved of CPU, and the view can redraw at
/// whatever rate the display runs at by asking for the pose at a given instant.
/// Published properties change only at step boundaries, so a smooth 120 Hz
/// animation costs no SwiftUI invalidations at all.
@MainActor
final class BreakSession: ObservableObject {
    let plan: BreakPlan

    @Published private(set) var stepIndex = 0
    @Published private(set) var isPaused = false
    @Published private(set) var finished: BreakOutcome?

    /// Called once when the break ends, for whatever reason.
    var onFinish: ((BreakOutcome, [LoggedStep]) -> Void)?

    private let clock: () -> Date
    private var stepStart: Date
    private var pauseStart: Date?
    private var pausedTotal: TimeInterval = 0
    private var log: [LoggedStep] = []
    private var boundaryTimer: Timer?

    /// - Parameters:
    ///   - startedAt: When the first step began. Backdating it puts a preview
    ///     mid-exercise.
    ///   - clock: The session's notion of now; tests substitute their own.
    ///   - autoAdvance: Run the boundary timer. Tests turn it off and call
    ///     `tick()` themselves.
    init(
        plan: BreakPlan,
        startedAt: Date? = nil,
        clock: @escaping () -> Date = Date.init,
        autoAdvance: Bool = true
    ) {
        self.plan = plan
        self.clock = clock
        self.stepStart = startedAt ?? clock()
        guard autoAdvance else { return }
        // 5 Hz is plenty to notice a step boundary; the drawing does not
        // depend on this timer.
        boundaryTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit { boundaryTimer?.invalidate() }

    var currentStep: BreakStep? {
        stepIndex < plan.steps.count ? plan.steps[stepIndex] : nil
    }

    /// Seconds spent on the current step, excluding paused time.
    func elapsed(at now: Date) -> Double {
        let paused = pausedTotal + (pauseStart.map { now.timeIntervalSince($0) } ?? 0)
        return max(0, now.timeIntervalSince(stepStart) - paused)
    }

    func remainingInStep(at now: Date) -> Double {
        guard let step = currentStep else { return 0 }
        return max(0, step.duration - elapsed(at: now))
    }

    /// Seconds left in the whole break, used for the header and progress bar.
    func remainingTotal(at now: Date) -> Double {
        guard stepIndex < plan.steps.count else { return 0 }
        let laterSteps = plan.steps[(stepIndex + 1)...].reduce(0) { $0 + $1.duration }
        return remainingInStep(at: now) + laterSteps
    }

    /// The figure's configuration right now.
    func frame(at now: Date) -> MovementFrame? {
        currentStep?.movement.frame(at: elapsed(at: now))
    }

    // MARK: - Controls

    func togglePause() {
        guard finished == nil else { return }
        if let start = pauseStart {
            pausedTotal += clock().timeIntervalSince(start)
            pauseStart = nil
            isPaused = false
        } else {
            pauseStart = clock()
            isPaused = true
        }
    }

    /// Move on without finishing the current step. Recorded as not completed,
    /// which is what feeds the "most skipped exercise" statistic.
    func skipStep() {
        guard finished == nil else { return }
        recordCurrentStep(completed: false)
        advance()
    }

    /// The user closed the window before the break was over. The step on
    /// screen counts as abandoned, and the outcome follows from what was
    /// actually done: some steps make it partial, none make it skipped.
    func abandon() {
        guard finished == nil else { return }
        recordCurrentStep(completed: false)
        finish(outcomeFromLog())
    }

    /// The user postponed the break. Recorded as `.snoozed` so the log can
    /// distinguish postponing from refusing.
    func snooze() {
        guard finished == nil else { return }
        finish(.snoozed)
    }

    // MARK: - Progression

    /// Move to the next step once the current one has run its course.
    func tick() {
        guard finished == nil, !isPaused, let step = currentStep else { return }
        if elapsed(at: clock()) >= step.duration {
            recordCurrentStep(completed: true)
            advance()
        }
    }

    private func advance() {
        guard finished == nil else { return }
        if stepIndex + 1 >= plan.steps.count {
            stepIndex = plan.steps.count
            finish(outcomeFromLog())
        } else {
            stepIndex += 1
            stepStart = clock()
            pausedTotal = 0
            pauseStart = nil
            isPaused = false
        }
    }

    private func outcomeFromLog() -> BreakOutcome {
        let allDone = log.count == plan.steps.count && log.allSatisfy(\.completed)
        if allDone { return .completed }
        return log.contains(where: \.completed) ? .partial : .skipped
    }

    private func finish(_ outcome: BreakOutcome) {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        finished = outcome
        onFinish?(outcome, log)
    }

    private func recordCurrentStep(completed: Bool) {
        guard let step = currentStep, log.count == stepIndex else { return }
        log.append(LoggedStep(
            exerciseID: step.exercise.id,
            exerciseName: step.exercise.name,
            region: step.exercise.region,
            side: step.sideLabel,
            plannedSeconds: step.duration,
            actualSeconds: elapsed(at: clock()),
            completed: completed
        ))
    }
}
