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

    private var stepStart: Date
    private var pauseStart: Date?
    private var pausedTotal: TimeInterval = 0
    private var log: [LoggedStep] = []
    private var boundaryTimer: Timer?

    init(plan: BreakPlan, now: Date = Date()) {
        self.plan = plan
        self.stepStart = now
        // 5 Hz is plenty to notice a step boundary; the drawing does not
        // depend on this timer.
        boundaryTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceIfDue() }
        }
    }

    deinit { boundaryTimer?.invalidate() }

    var currentStep: BreakStep? {
        stepIndex < plan.steps.count ? plan.steps[stepIndex] : nil
    }

    /// Seconds spent on the current step, excluding paused time.
    func elapsed(at now: Date = Date()) -> Double {
        let paused = pausedTotal + (pauseStart.map { now.timeIntervalSince($0) } ?? 0)
        return max(0, now.timeIntervalSince(stepStart) - paused)
    }

    func remainingInStep(at now: Date = Date()) -> Double {
        guard let step = currentStep else { return 0 }
        return max(0, step.duration - elapsed(at: now))
    }

    /// Seconds left in the whole break, used for the header and progress bar.
    func remainingTotal(at now: Date = Date()) -> Double {
        guard stepIndex < plan.steps.count else { return 0 }
        let laterSteps = plan.steps[(stepIndex + 1)...].reduce(0) { $0 + $1.duration }
        return remainingInStep(at: now) + laterSteps
    }

    /// The figure's configuration right now.
    func frame(at now: Date = Date()) -> MovementFrame? {
        currentStep?.movement.frame(at: elapsed(at: now))
    }

    // MARK: - Controls

    func togglePause() {
        if let start = pauseStart {
            pausedTotal += Date().timeIntervalSince(start)
            pauseStart = nil
            isPaused = false
        } else {
            pauseStart = Date()
            isPaused = true
        }
    }

    /// Move on without finishing the current step. Recorded as not completed,
    /// which is what feeds the "most skipped exercise" statistic.
    func skipStep() {
        recordCurrentStep(completed: false)
        advance()
    }

    /// End the break early. `.snoozed` is what the snooze button reports so the
    /// log can distinguish postponing from refusing.
    func end(_ outcome: BreakOutcome) {
        guard finished == nil else { return }
        if outcome != .skipped && outcome != .snoozed {
            recordCurrentStep(completed: false)
        }
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        finished = outcome
        onFinish?(outcome, log)
    }

    // MARK: - Progression

    private func advanceIfDue() {
        guard finished == nil, !isPaused, let step = currentStep else { return }
        if elapsed() >= step.duration {
            recordCurrentStep(completed: true)
            advance()
        }
    }

    private func advance() {
        guard finished == nil else { return }
        if stepIndex + 1 >= plan.steps.count {
            let anyDone = log.contains { $0.completed }
            let allDone = log.allSatisfy { $0.completed } && log.count == plan.steps.count
            boundaryTimer?.invalidate()
            boundaryTimer = nil
            stepIndex = plan.steps.count
            finished = allDone ? .completed : (anyDone ? .partial : .skipped)
            onFinish?(finished!, log)
        } else {
            stepIndex += 1
            stepStart = Date()
            pausedTotal = 0
            pauseStart = nil
            isPaused = false
        }
    }

    private func recordCurrentStep(completed: Bool) {
        guard let step = currentStep, log.count == stepIndex else { return }
        log.append(LoggedStep(
            exerciseID: step.exercise.id,
            exerciseName: step.exercise.name,
            side: step.sideLabel,
            plannedSeconds: step.duration,
            actualSeconds: elapsed(),
            completed: completed
        ))
    }
}
