import Foundation

/// One thing to do, for one length of time: an exercise, and for bilateral
/// exercises which side this is. A bilateral exercise becomes two steps, so
/// each side gets its own countdown and its own place in the progress row.
struct BreakStep: Identifiable {
    let id = UUID()
    let exercise: Exercise
    /// Index into `exercise.sides`, or nil for a symmetric exercise.
    let sideIndex: Int?
    /// The exercise's pattern after scaling to the break's target length.
    let pattern: MovementPattern

    var sideLabel: String? {
        guard let sides = exercise.sides, let i = sideIndex else { return nil }
        return sides[i]
    }

    var duration: Double { pattern.duration }

    /// Keyframes for this step, mirrored for the second side.
    var movement: Movement {
        let frames = (sideIndex ?? 0) == 1
            ? exercise.keyframes.map { $0.mirrored }
            : exercise.keyframes
        return Movement(pattern: pattern, keyframes: frames)
    }
}

/// A composed break: which tier, and the ordered steps.
struct BreakPlan {
    let tier: Tier
    let steps: [BreakStep]

    var duration: Double { steps.reduce(0) { $0 + $1.duration } }
}

/// Composes breaks out of the library.
///
/// Two goals fight each other here. A break should be *varied*, so the same
/// three stretches don't become the only three you ever do, and it should be
/// *predictably short*, so it never feels like it derailed the morning. The
/// planner therefore picks one exercise from each of several body regions,
/// preferring whatever has gone longest unused, and then scales the timings so
/// the total lands near the configured target.
@MainActor
enum BreakPlanner {

    /// Order in which regions appear in a break: mobilise first, stretch last.
    /// A cold upper trapezius does not want to be pulled into end range as the
    /// opening move.
    private static let regionOrder: [Region] = [.shoulders, .neck, .traps, .scapulae, .thoracic, .chest]

    static func plan(
        tier: Tier,
        settings: Settings,
        lastUsed: [String: Date],
        now: Date = Date()
    ) -> BreakPlan {
        let allowStanding = settings.includeStanding && tier == .long
        let pool = ExerciseLibrary.pool(for: tier, allowStanding: allowStanding)
        guard !pool.isEmpty else { return BreakPlan(tier: tier, steps: []) }

        let wantedRegions = tier == .micro ? 2 : 5
        let target = Double(tier == .micro ? settings.microTarget : settings.longTarget)

        // Rank regions by how long ago anything from them was last done. A
        // region never touched sorts first, which front-loads variety on a
        // fresh install.
        let byRegion = Dictionary(grouping: pool, by: \.region)
        let staleness: [(region: Region, age: Date)] = byRegion.map { region, exercises in
            let newest = exercises.compactMap { lastUsed[$0.id] }.max() ?? .distantPast
            return (region, newest)
        }
        // Ties are the normal case on a fresh install, where nothing has been
        // done yet, so they are broken by the canonical region order. Without
        // that, the first breaks of a new install would be a different random
        // selection every time and impossible to reason about.
        let chosenRegions = staleness
            .sorted {
                $0.age != $1.age
                    ? $0.age < $1.age
                    : (regionOrder.firstIndex(of: $0.region) ?? 0)
                        < (regionOrder.firstIndex(of: $1.region) ?? 0)
            }
            .prefix(wantedRegions)
            .map(\.region)

        // Within a region, the exercise unused longest, so the second-choice
        // variants actually come up instead of rotting in the library.
        var picked: [Exercise] = chosenRegions.compactMap { region in
            byRegion[region]?.min {
                (lastUsed[$0.id] ?? .distantPast) < (lastUsed[$1.id] ?? .distantPast)
            }
        }
        picked.sort {
            (regionOrder.firstIndex(of: $0.region) ?? 0) < (regionOrder.firstIndex(of: $1.region) ?? 0)
        }

        // Scale every exercise by one common factor so the break lands near
        // the target without distorting their relative lengths. The clamp keeps
        // a stretch from being cut to something useless or stretched to a
        // small eternity.
        let natural = picked.reduce(0.0) { $0 + $1.duration() }
        let factor = min(1.25, max(0.55, natural > 0 ? target / natural : 1))

        var steps: [BreakStep] = []
        for exercise in picked {
            let pattern = exercise.pattern.scaled(by: factor)
            if let sides = exercise.sides {
                for i in sides.indices {
                    steps.append(BreakStep(exercise: exercise, sideIndex: i, pattern: pattern))
                }
            } else {
                steps.append(BreakStep(exercise: exercise, sideIndex: nil, pattern: pattern))
            }
        }
        return BreakPlan(tier: tier, steps: steps)
    }
}
