import Foundation
import Testing
@testable import Nikamat

@MainActor
struct BreakLogTests {
    private let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("nikamat-test-\(UUID().uuidString).sqlite3").path

    private let plan = BreakPlanner.plan(tier: .micro, preferences: Preferences(), lastUsed: [:])

    /// Noon, `daysAgo` days before a fixed reference day.
    private func day(_ daysAgo: Int) -> Date {
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12))!
        return Calendar.current.date(byAdding: .day, value: -daysAgo, to: reference)!
    }

    private func steps(completed: Int) -> [LoggedStep] {
        plan.steps.enumerated().map { index, step in
            LoggedStep(
                exerciseID: step.exercise.id, exerciseName: step.exercise.name,
                region: step.exercise.region, side: step.sideLabel,
                plannedSeconds: step.duration, actualSeconds: step.duration,
                completed: index < completed
            )
        }
    }

    private func record(_ log: BreakLog, _ outcome: BreakOutcome, completed: Int, at date: Date) {
        log.record(plan: plan, outcome: outcome, steps: steps(completed: completed),
                   startedAt: date, endedAt: date.addingTimeInterval(60))
    }

    @Test func partialCountsAsDoneButSkippedDoesNot() {
        let log = BreakLog(path: path)
        record(log, .completed, completed: plan.steps.count, at: day(0))
        record(log, .partial, completed: 1, at: day(0))
        record(log, .skipped, completed: 0, at: day(0))
        record(log, .snoozed, completed: 0, at: day(0))

        let summary = log.summary(now: day(0))
        #expect(summary.todayOffered == 4)
        #expect(summary.todayDone == 2)
    }

    /// Rows written before the outcome fix said 'partial' for a break closed
    /// without doing anything; opening the log corrects them.
    @Test func migrationCorrectsEmptyPartialBreaks() throws {
        _ = BreakLog(path: path)
        let database = try Database(path: path)
        try database.execute("""
            INSERT INTO breaks (started_at, ended_at, day, tier, outcome, planned_steps,
                                completed_steps, planned_seconds, actual_seconds)
            VALUES ('2026-03-30T10:00:00Z', '2026-03-30T10:00:05Z', '2026-03-30', 'micro',
                    'partial', 3, 0, 60, 5),
                   ('2026-03-30T11:00:00Z', '2026-03-30T11:00:30Z', '2026-03-30', 'micro',
                    'partial', 3, 1, 60, 30)
            """)
        _ = BreakLog(path: path)
        let outcomes = try database.query("SELECT outcome FROM breaks ORDER BY id") { $0.text(0) }
        #expect(outcomes == ["skipped", "partial"])
    }

    @Test func streakIsNotCappedAtTheChartWindow() {
        let log = BreakLog(path: path)
        for daysAgo in 0..<20 {
            record(log, .completed, completed: plan.steps.count, at: day(daysAgo))
        }
        let summary = log.summary(now: day(0))
        #expect(summary.streak == 20)
        #expect(summary.recent.count == 14)
    }

    @Test func streakRules() {
        let days: Set<String> = ["2026-03-27", "2026-03-28", "2026-03-29"]
        // Nothing yet today: a run ending yesterday still counts.
        #expect(BreakLog.streak(activeDays: days, now: day(0)) == 3)
        #expect(BreakLog.streak(activeDays: days.union(["2026-03-30"]), now: day(0)) == 4)
        // A missed day breaks it.
        #expect(BreakLog.streak(activeDays: ["2026-03-28"], now: day(0)) == 0)
    }

    /// 29 March 2026 is 23 hours long in European time zones. Stepping back
    /// 86 400 seconds from half past midnight on the 30th lands on the 28th and
    /// skips it. Uses the machine's time zone, so this only exercises the DST
    /// case where that night has a change (as in Finland).
    @Test func streakSurvivesDaylightSavingChange() {
        let days: Set<String> = ["2026-03-28", "2026-03-29", "2026-03-30"]
        let justAfterMidnight = Calendar.current.date(
            from: DateComponents(year: 2026, month: 3, day: 30, hour: 0, minute: 30)
        )!
        #expect(BreakLog.streak(activeDays: days, now: justAfterMidnight) == 3)
    }

    @Test func lastUsedIsTheMostRecentPerExercise() throws {
        let log = BreakLog(path: path)
        record(log, .completed, completed: plan.steps.count, at: day(3))
        record(log, .completed, completed: plan.steps.count, at: day(1))
        let lastUsed = log.lastUsed()
        let id = try #require(plan.steps.first?.exercise.id)
        #expect(lastUsed[id] == day(1))
    }

    @Test func weekIsARollingSevenDays() {
        let log = BreakLog(path: path)
        for daysAgo in [0, 6, 7] {
            record(log, .completed, completed: plan.steps.count, at: day(daysAgo))
        }
        let summary = log.summary(now: day(0))
        #expect(summary.weekOffered == 2)
    }

    @Test func failedTransactionLeavesNothingBehind() throws {
        let database = try Database(path: path)
        try database.execute("CREATE TABLE t (x INTEGER NOT NULL)")
        #expect(throws: Database.Error.self) {
            try database.transaction {
                try database.run("INSERT INTO t VALUES (1)")
                try database.run("INSERT INTO t VALUES (NULL)")
            }
        }
        let count = try database.query("SELECT COUNT(*) FROM t") { $0.int(0) }
        #expect(count == [0])
    }

    @Test func unwritableLocationDegradesToNoOps() {
        let log = BreakLog(path: "/dev/null/nikamat.sqlite3")
        record(log, .completed, completed: 1, at: day(0))
        #expect(log.lastUsed().isEmpty)
        #expect(log.summary().todayOffered == 0)
    }
}
