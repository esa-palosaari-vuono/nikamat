import Foundation

/// `Nikamat --selftest` exercises the parts that are otherwise only reachable
/// by waiting half an hour and doing some stretches: it plans both kinds of
/// break, writes them to the log as if they had been performed, and reads the
/// statistics back out.
///
/// This is a diagnostic, not a unit test: it writes to a scratch database in
/// the temporary directory, prints what it did and leaves the rows behind for
/// inspection. The unit tests live in `Tests/`.
@MainActor
enum SelfTest {
    static func run() {
        // A scratch file, so the diagnostic's fictional breaks stay out of
        // the real log.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("nikamat-selftest.sqlite3")
        try? FileManager.default.removeItem(at: scratch)
        let log = BreakLog(path: scratch.path)
        print("tietokanta: \(log.path)\n")

        for tier in [Tier.micro, .long] {
            let plan = BreakPlanner.plan(tier: tier, preferences: Preferences(), lastUsed: log.lastUsed())
            print("\(tier.title): \(plan.steps.count) vaihetta, \(Int(plan.duration)) s")
            for step in plan.steps {
                let side = step.sideLabel.map { " (\($0))" } ?? ""
                let label = (step.exercise.name + side).padding(
                    toLength: 36, withPad: " ", startingAt: 0
                )
                print("  \(label)\(Int(step.duration)) s  ·  \(step.exercise.region.label)")
            }
            let steps = plan.steps.map { step in
                LoggedStep(
                    exerciseID: step.exercise.id,
                    exerciseName: step.exercise.name,
                    region: step.exercise.region,
                    side: step.sideLabel,
                    plannedSeconds: step.duration,
                    actualSeconds: step.duration,
                    completed: true
                )
            }
            log.record(
                plan: plan, outcome: .completed, steps: steps,
                startedAt: Date().addingTimeInterval(-plan.duration)
            )
            print()
        }

        let summary = log.summary()
        print("""
            yhteenveto
              tänään   \(summary.todayDone) / \(summary.todayOffered) (\(Int(summary.todayMinutes)) min)
              7 päivää \(summary.weekDone) / \(summary.weekOffered)
              putki    \(summary.streak) \(summary.streak == 1 ? "päivä" : "päivää")
              päiviä kirjattu: \(summary.recent.count)
            """)
        if let skipped = summary.mostSkipped {
            print("  heikoin: \(skipped.name) \(skipped.percent) %")
        }
    }
}
