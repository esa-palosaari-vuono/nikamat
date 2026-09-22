import Foundation
import Testing
@testable import Nikamat

/// A clock the test moves by hand.
final class ManualClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
struct BreakSessionTests {
    private let clock = ManualClock()
    private let plan = BreakPlanner.plan(tier: .micro, preferences: Preferences(), lastUsed: [:])

    /// A session plus a record of what it reported when it finished.
    private final class Finish {
        var calls: [(BreakOutcome, [LoggedStep])] = []
    }

    private func makeSession() -> (BreakSession, Finish) {
        let clock = self.clock
        let session = BreakSession(plan: plan, clock: { clock.now }, autoAdvance: false)
        let finish = Finish()
        session.onFinish = { finish.calls.append(($0, $1)) }
        return (session, finish)
    }

    /// Run the current step to its end and let the session notice.
    private func completeStep(_ session: BreakSession) {
        clock.advance(session.remainingInStep(at: clock.now) + 0.01)
        session.tick()
    }

    @Test func runningEveryStepCompletesTheBreak() throws {
        let (session, finish) = makeSession()
        for _ in plan.steps { completeStep(session) }
        #expect(session.finished == .completed)
        let call = try #require(finish.calls.first)
        #expect(finish.calls.count == 1)
        #expect(call.0 == .completed)
        #expect(call.1.count == plan.steps.count)
        #expect(call.1.allSatisfy { $0.completed })
    }

    /// Regression: closing at once used to be logged as 'partial', which the
    /// statistics count as done.
    @Test func abandoningBeforeAnythingIsDoneIsSkipped() throws {
        let (session, finish) = makeSession()
        clock.advance(2)
        session.abandon()
        #expect(session.finished == .skipped)
        let steps = try #require(finish.calls.first?.1)
        #expect(steps.count == 1)
        #expect(steps[0].completed == false)
        #expect(abs(steps[0].actualSeconds - 2) < 1e-9)
    }

    @Test func abandoningAfterAStepIsPartial() {
        let (session, finish) = makeSession()
        completeStep(session)
        session.abandon()
        #expect(session.finished == .partial)
        #expect(finish.calls.first?.1.map(\.completed) == [true, false])
    }

    @Test func snoozeDoesNotLogTheStepOnScreen() {
        let (session, finish) = makeSession()
        completeStep(session)
        session.snooze()
        #expect(session.finished == .snoozed)
        #expect(finish.calls.first?.1.count == 1)
    }

    @Test func skippingEveryStepIsSkipped() {
        let (session, _) = makeSession()
        for _ in plan.steps { session.skipStep() }
        #expect(session.finished == .skipped)
    }

    @Test func finishIsReportedOnlyOnce() {
        let (session, finish) = makeSession()
        session.abandon()
        session.abandon()
        session.snooze()
        session.skipStep()
        completeStep(session)
        #expect(finish.calls.count == 1)
    }

    @Test func pausedTimeDoesNotCount() {
        let (session, _) = makeSession()
        clock.advance(3)
        session.togglePause()
        clock.advance(100)
        session.tick()
        #expect(session.stepIndex == 0, "a paused step must not advance")
        #expect(abs(session.elapsed(at: clock.now) - 3) < 1e-9)
        session.togglePause()
        clock.advance(1)
        #expect(abs(session.elapsed(at: clock.now) - 4) < 1e-9)
    }

    @Test func remainingTotalCoversTheWholeBreak() {
        let (session, _) = makeSession()
        #expect(abs(session.remainingTotal(at: clock.now) - plan.duration) < 1e-9)
        clock.advance(5)
        #expect(abs(session.remainingTotal(at: clock.now) - (plan.duration - 5)) < 1e-9)
    }
}
