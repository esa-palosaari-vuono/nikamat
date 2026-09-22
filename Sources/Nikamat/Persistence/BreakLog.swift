import Foundation

/// Everything the app knows about breaks you have and have not done.
///
/// The store doubles as the app's memory for planning: the planner asks it when
/// each exercise was last performed so that variety is a property of the data
/// rather than of a random number generator.
///
/// A broken or unwritable database must never stop the reminders, so every
/// operation degrades to a no-op with a message on stderr. Losing statistics is
/// a nuisance; losing the thing that gets you to move is the actual failure.
@MainActor
final class BreakLog {
    static let shared = BreakLog()

    /// Where the file lives. Printed in Settings so it can be opened elsewhere.
    let path: String
    private var database: Database?

    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "fi_FI")
        return formatter
    }()

    private init() {
        // NIKAMAT_DB redirects the store elsewhere. Diagnostics use it so that
        // running --selftest never writes fictional breaks into real history.
        if let override = ProcessInfo.processInfo.environment["NIKAMAT_DB"] {
            path = override
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: override).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Nikamat", isDirectory: true)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            path = support.appendingPathComponent("nikamat.sqlite3").path
        }
        do {
            let database = try Database(path: path)
            try Self.migrate(database)
            self.database = database
        } catch {
            FileHandle.standardError.write(Data("Nikamat: \(error)\n".utf8))
        }
    }

    // MARK: - Schema

    /// Tables plus a couple of views.
    ///
    /// The views exist for readers outside this app: `v_days` and
    /// `v_exercises` answer the two questions anyone actually asks of this
    /// data without them having to work out the joins first. They are dropped
    /// and recreated on every launch, because a view is derived data and an
    /// old one left behind by a previous version would quietly disagree with
    /// the code that documents it.
    private static func migrate(_ database: Database) throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS breaks (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at      TEXT    NOT NULL,
                ended_at        TEXT    NOT NULL,
                day             TEXT    NOT NULL,
                tier            TEXT    NOT NULL,
                outcome         TEXT    NOT NULL,
                planned_steps   INTEGER NOT NULL,
                completed_steps INTEGER NOT NULL,
                planned_seconds REAL    NOT NULL,
                actual_seconds  REAL    NOT NULL
            );

            CREATE TABLE IF NOT EXISTS break_steps (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                break_id        INTEGER NOT NULL REFERENCES breaks(id) ON DELETE CASCADE,
                ordinal         INTEGER NOT NULL,
                exercise_id     TEXT    NOT NULL,
                exercise_name   TEXT    NOT NULL,
                region          TEXT    NOT NULL,
                side            TEXT,
                planned_seconds REAL    NOT NULL,
                actual_seconds  REAL    NOT NULL,
                completed       INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS breaks_day ON breaks(day);
            CREATE INDEX IF NOT EXISTS steps_exercise ON break_steps(exercise_id);

            -- Earlier versions logged a break closed without doing
            -- anything as 'partial', which counted it as done.
            UPDATE breaks SET outcome = 'skipped'
            WHERE outcome = 'partial' AND completed_steps = 0;

            DROP VIEW IF EXISTS v_days;
            DROP VIEW IF EXISTS v_exercises;

            CREATE VIEW v_days AS
                SELECT day,
                       COUNT(*)                                                    AS tarjottu,
                       SUM(outcome IN ('completed', 'partial'))                    AS tehty,
                       SUM(outcome = 'completed')                                  AS kokonaan,
                       SUM(tier = 'micro')                                         AS mikro,
                       SUM(tier = 'long')                                          AS pitka,
                       ROUND(SUM(actual_seconds) / 60.0, 1)                        AS minuutit
                FROM breaks
                GROUP BY day
                ORDER BY day DESC;

            CREATE VIEW v_exercises AS
                SELECT s.exercise_name                                             AS liike,
                       CASE s.region
                           WHEN 'neck'      THEN 'niska'
                           WHEN 'traps'     THEN 'ylatrapetsi'
                           WHEN 'shoulders' THEN 'hartiat'
                           WHEN 'scapulae'  THEN 'lapaluut'
                           WHEN 'chest'     THEN 'rintakeha'
                           WHEN 'thoracic'  THEN 'rintaranka'
                           ELSE s.region
                       END                                                         AS alue,
                       COUNT(*)                                                    AS kerrat,
                       SUM(s.completed)                                            AS loppuun,
                       ROUND(100.0 * SUM(s.completed) / COUNT(*))                  AS prosentti,
                       MAX(b.started_at)                                           AS viimeksi
                FROM break_steps s
                JOIN breaks b ON b.id = s.break_id
                GROUP BY s.exercise_id
                ORDER BY kerrat DESC;
            """)
    }

    // MARK: - Writing

    func record(
        plan: BreakPlan,
        outcome: BreakOutcome,
        steps: [LoggedStep],
        startedAt: Date,
        endedAt: Date = Date()
    ) {
        guard let database else { return }
        do {
            let breakID = try database.run(
                """
                INSERT INTO breaks
                    (started_at, ended_at, day, tier, outcome,
                     planned_steps, completed_steps, planned_seconds, actual_seconds)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(Self.timestamp.string(from: startedAt)),
                    .text(Self.timestamp.string(from: endedAt)),
                    .text(Self.day.string(from: startedAt)),
                    .text(plan.tier.rawValue),
                    .text(outcome.rawValue),
                    .int(plan.steps.count),
                    .int(steps.filter(\.completed).count),
                    .double(plan.duration),
                    .double(steps.reduce(0) { $0 + $1.actualSeconds })
                ]
            )
            for (ordinal, step) in steps.enumerated() {
                let region = ExerciseLibrary.exercise(id: step.exerciseID)?.region.rawValue ?? ""
                try database.run(
                    """
                    INSERT INTO break_steps
                        (break_id, ordinal, exercise_id, exercise_name, region,
                         side, planned_seconds, actual_seconds, completed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .int(breakID), .int(ordinal),
                        .text(step.exerciseID), .text(step.exerciseName), .text(region),
                        step.side.map { Database.Value.text($0) } ?? .null,
                        .double(step.plannedSeconds), .double(step.actualSeconds),
                        .int(step.completed ? 1 : 0)
                    ]
                )
            }
        } catch {
            FileHandle.standardError.write(Data("Nikamat: \(error)\n".utf8))
        }
    }

    // MARK: - Reading

    /// When each exercise was last performed, for the planner's variety rule.
    func lastUsed() -> [String: Date] {
        guard let database else { return [:] }
        let rows = (try? database.query(
            """
            SELECT s.exercise_id, MAX(b.started_at)
            FROM break_steps s JOIN breaks b ON b.id = s.break_id
            GROUP BY s.exercise_id
            """
        ) { ($0.text(0), $0.text(1)) }) ?? []
        return rows.reduce(into: [:]) { result, row in
            if let date = Self.timestamp.date(from: row.1) { result[row.0] = date }
        }
    }

    /// What the menu bar's statistics panel shows.
    struct Summary {
        var todayDone = 0
        var todayOffered = 0
        var todayMinutes = 0.0
        var weekDone = 0
        var weekOffered = 0
        var streak = 0
        /// The exercise most often abandoned, with its completion percentage.
        var mostSkipped: (name: String, percent: Int)?
        /// The last fourteen days, oldest first, for the small bar chart.
        var recent: [(day: String, done: Int, offered: Int)] = []
    }

    func summary(now: Date = Date()) -> Summary {
        guard let database else { return Summary() }
        var summary = Summary()
        let today = Self.day.string(from: now)

        let todayRows = (try? database.query(
            "SELECT tehty, tarjottu, minuutit FROM v_days WHERE day = ?",
            [.text(today)]
        ) { ($0.int(0), $0.int(1), $0.double(2)) }) ?? []
        if let row = todayRows.first {
            summary.todayDone = row.0
            summary.todayOffered = row.1
            summary.todayMinutes = row.2
        }

        // Rolling seven days rather than the calendar week: on a Monday
        // morning a calendar week says nothing.
        let weekAgo = Self.day.string(from: now.addingTimeInterval(-6 * 86400))
        let weekRows = (try? database.query(
            "SELECT SUM(tehty), SUM(tarjottu) FROM v_days WHERE day >= ?",
            [.text(weekAgo)]
        ) { ($0.int(0), $0.int(1)) }) ?? []
        if let row = weekRows.first {
            summary.weekDone = row.0
            summary.weekOffered = row.1
        }

        summary.recent = ((try? database.query(
            "SELECT day, tehty, tarjottu FROM v_days ORDER BY day DESC LIMIT 14"
        ) { ($0.text(0), $0.int(1), $0.int(2)) }) ?? []).reversed()

        // A streak counts back from today, but an unbroken run that ends
        // yesterday still counts: the day is not over yet.
        let days = Set(summary.recent.filter { $0.done > 0 }.map(\.day))
        var cursor = now
        if !days.contains(today) { cursor = now.addingTimeInterval(-86400) }
        while days.contains(Self.day.string(from: cursor)) {
            summary.streak += 1
            cursor = cursor.addingTimeInterval(-86400)
        }

        let skipped = (try? database.query(
            "SELECT liike, prosentti FROM v_exercises WHERE kerrat >= 3 ORDER BY prosentti ASC LIMIT 1"
        ) { ($0.text(0), $0.int(1)) }) ?? []
        if let row = skipped.first, row.1 < 100 {
            summary.mostSkipped = (row.0, row.1)
        }
        return summary
    }
}
