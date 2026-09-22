import Foundation
import Testing
@testable import Nikamat

struct BreakPlannerTests {
    private let regionOrder: [Region] = [.shoulders, .neck, .traps, .scapulae, .thoracic, .chest]

    @Test func microBreakIsTwoSeatedRegions() {
        let plan = BreakPlanner.plan(tier: .micro, preferences: Preferences(), lastUsed: [:])
        #expect(plan.tier == .micro)
        #expect(Set(plan.steps.map(\.exercise.region)).count == 2)
        #expect(plan.steps.allSatisfy { $0.exercise.posture == .seated })
    }

    @Test func longBreakRespectsStandingPreference() {
        var preferences = Preferences()
        preferences.includeStanding = false
        let plan = BreakPlanner.plan(tier: .long, preferences: preferences, lastUsed: [:])
        #expect(Set(plan.steps.map(\.exercise.region)).count == 5)
        #expect(plan.steps.allSatisfy { $0.exercise.posture == .seated })
    }

    /// Scaling is clamped to 0.55...1.25, so the total lands on target only
    /// when the natural length is within reach; the default targets are.
    @Test(arguments: [Tier.micro, .long])
    func durationLandsNearTarget(tier: Tier) {
        let preferences = Preferences()
        let target = Double(tier == .micro ? preferences.microTarget : preferences.longTarget)
        let plan = BreakPlanner.plan(tier: tier, preferences: preferences, lastUsed: [:])
        #expect(abs(plan.duration - target) / target < 0.25, "\(plan.duration) s for \(target) s")
    }

    @Test(arguments: [10_000, 1])
    func extremeTargetsAreClamped(target: Int) {
        var preferences = Preferences()
        preferences.longTarget = target
        let plan = BreakPlanner.plan(tier: .long, preferences: preferences, lastUsed: [:])
        let exercises = Dictionary(plan.steps.map { ($0.exercise.id, $0.exercise) }) { a, _ in a }
        let natural = exercises.values.reduce(0) { $0 + $1.duration() }
        // Whole seconds and whole repetitions round each exercise a little.
        let slack = Double(plan.steps.count) * 4
        #expect(plan.duration <= natural * 1.25 + slack)
        #expect(plan.duration >= natural * 0.55 - slack)
    }

    @Test func stepsFollowTheCanonicalRegionOrder() {
        let plan = BreakPlanner.plan(tier: .long, preferences: Preferences(), lastUsed: [:])
        let positions = plan.steps.map { regionOrder.firstIndex(of: $0.exercise.region)! }
        #expect(positions == positions.sorted())
    }

    /// Variety comes from the log: whatever was done most recently is what
    /// the next break avoids.
    @Test func recentlyUsedRegionsAreAvoided() {
        let now = Date()
        let first = BreakPlanner.plan(tier: .micro, preferences: Preferences(), lastUsed: [:])
        let used = Dictionary(first.steps.map { ($0.exercise.id, now) }) { a, _ in a }
        let second = BreakPlanner.plan(tier: .micro, preferences: Preferences(), lastUsed: used)
        let firstRegions = Set(first.steps.map(\.exercise.region))
        let secondRegions = Set(second.steps.map(\.exercise.region))
        #expect(firstRegions.isDisjoint(with: secondRegions))
    }

    @Test func bilateralExercisesBecomeTwoMirroredSteps() throws {
        let plan = BreakPlanner.plan(tier: .long, preferences: Preferences(), lastUsed: [:])
        let sided = plan.steps.filter { $0.sideIndex != nil }
        let first = try #require(sided.first)
        let second = try #require(sided.first { $0.exercise.id == first.exercise.id && $0.sideIndex == 1 })
        #expect(first.sideLabel == first.exercise.sides?[0])
        #expect(second.sideLabel == first.exercise.sides?[1])
        #expect(second.movement.keyframes == first.movement.keyframes.map(\.mirrored))
    }
}
