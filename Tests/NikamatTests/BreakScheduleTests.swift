import Foundation
import Testing
@testable import Nikamat

private struct FakeSensors: PresenceSensing {
    var secondsSinceInput: Double
    var microphoneInUse: Bool
}

/// Drives a `BreakSchedule` through simulated time, one tick per second, the
/// way `Scheduler` does with the real clock.
private struct Harness {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }()

    /// A Monday, at the given time of day.
    static func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 2,
                                           hour: hour, minute: minute, second: second))!
    }

    var preferences = Preferences()
    var now: Date
    var schedule: BreakSchedule
    /// While true, every tick counts as fresh input: the user is typing.
    var active = true
    var lastInput: Date
    var microphone = false

    init(startingAt start: Date, preferences: Preferences = Preferences()) {
        self.preferences = preferences
        now = start
        lastInput = start
        schedule = BreakSchedule(now: start, preferences: preferences, calendar: Self.calendar)
    }

    mutating func tick() -> BreakSchedule.Action? {
        if active { lastInput = now }
        let sensors = FakeSensors(
            secondsSinceInput: now.timeIntervalSince(lastInput),
            microphoneInUse: microphone
        )
        return schedule.tick(now: now, preferences: preferences, sensors: sensors)
    }

    /// Tick every second up to and including `end`; returns what happened.
    mutating func run(until end: Date) -> [(Date, BreakSchedule.Action)] {
        var actions: [(Date, BreakSchedule.Action)] = []
        while now < end {
            now = now.addingTimeInterval(1)
            if let action = tick() { actions.append((now, action)) }
        }
        return actions
    }

    /// Only the breaks that opened, as (time, tier).
    mutating func fires(until end: Date) -> [(Date, Tier)] {
        run(until: end).compactMap { time, action in
            if case .fire(let tier) = action { return (time, tier) }
            return nil
        }
    }
}

struct BreakScheduleTests {
    private typealias H = Harness

    // MARK: - Arithmetic

    @Test func breaksAreAnchoredToTheClock() {
        #expect(H(startingAt: H.at(10, 5)).schedule.nextFire == H.at(10, 30))
        #expect(H(startingAt: H.at(10, 5)).schedule.nextTier == .micro)
        #expect(H(startingAt: H.at(10, 35)).schedule.nextFire == H.at(11, 0))
        // A boundary exactly now is already past.
        #expect(H(startingAt: H.at(10, 30)).schedule.nextFire == H.at(11, 0))
    }

    @Test func longBreakWinsWhenBothCoincide() {
        let harness = H(startingAt: H.at(10, 45))
        #expect(harness.schedule.nextFire == H.at(11, 0))
        #expect(harness.schedule.nextTier == .long)
    }

    // MARK: - Normal operation

    @Test func warnsThenFires() {
        var harness = H(startingAt: H.at(10, 29))
        let actions = harness.run(until: H.at(10, 30, 5))
        #expect(actions.map(\.1) == [.warn(.micro), .fire(.micro)])
        #expect(actions.map(\.0) == [H.at(10, 29, 45), H.at(10, 30)])
    }

    @Test func noWarningWhenDisabled() {
        var preferences = Preferences()
        preferences.warningSeconds = 0
        var harness = H(startingAt: H.at(10, 29), preferences: preferences)
        #expect(harness.run(until: H.at(10, 31)).map(\.1) == [.fire(.micro)])
    }

    @Test func aFullHourFiresMicroThenLong() {
        var harness = H(startingAt: H.at(10, 5))
        let fires = harness.fires(until: H.at(11, 5))
        #expect(fires.map(\.1) == [.micro, .long])
    }

    // MARK: - Reasons not to fire

    @Test func quietHoursDropTheBreak() {
        var harness = H(startingAt: H.at(21, 59))
        #expect(harness.fires(until: H.at(23, 5)).isEmpty)
        #expect(harness.schedule.deferralReason == "hiljainen aika")
    }

    @Test func awayFromDeskDefersUntilReturnPlusSettle() throws {
        var harness = H(startingAt: H.at(10, 20))
        harness.active = false
        #expect(harness.fires(until: H.at(10, 35)).isEmpty)
        #expect(harness.schedule.deferralReason == "et ole koneella")

        harness.active = true
        let fire = try #require(harness.fires(until: H.at(10, 40)).first)
        #expect(fire.0 == H.at(10, 35, 1).addingTimeInterval(BreakSchedule.settleSeconds))
        #expect(fire.1 == .micro)
    }

    @Test func aBreakMissedForTooLongIsWrittenOff() {
        var harness = H(startingAt: H.at(10, 20))
        harness.active = false
        _ = harness.run(until: H.at(10, 55))
        harness.active = true
        let fires = harness.fires(until: H.at(11, 1))
        // Not the stale 10:30 one on return, only the regular 11:00 break.
        #expect(fires.map(\.0) == [H.at(11, 0)])
        #expect(fires.map(\.1) == [.long])
    }

    @Test func microphoneDefersUntilItStops() {
        var harness = H(startingAt: H.at(10, 29))
        harness.microphone = true
        #expect(harness.fires(until: H.at(10, 33)).isEmpty)
        #expect(harness.schedule.deferralReason == "mikrofoni käytössä")
        harness.microphone = false
        #expect(harness.fires(until: H.at(10, 34)).map(\.0) == [H.at(10, 33, 1)])
    }

    @Test func microphoneIgnoredWhenDisabled() {
        var preferences = Preferences()
        preferences.deferForMicrophone = false
        var harness = H(startingAt: H.at(10, 29), preferences: preferences)
        harness.microphone = true
        #expect(harness.fires(until: H.at(10, 31)).count == 1)
    }

    // MARK: - Snooze

    /// Regression: snoozing from the break window used to lose the break,
    /// because closing the window rescheduled from the clock.
    @Test func snoozedBreakComesBackWithItsTier() {
        var harness = H(startingAt: H.at(10, 59))
        #expect(harness.fires(until: H.at(11, 0)).map(\.1) == [.long])

        // The user snoozes the open window, which then closes.
        harness.now = H.at(11, 0, 5)
        harness.schedule.snooze(tier: .long, now: harness.now, preferences: harness.preferences)
        harness.now = H.at(11, 0, 6)
        harness.schedule.breakFinished(now: harness.now, preferences: harness.preferences)

        let fires = harness.fires(until: H.at(11, 15))
        #expect(fires.map(\.1) == [.long])
        #expect(fires.map(\.0) == [H.at(11, 10, 5)])
    }

    @Test func snoozeFromMenuPushesTheNextBreak() {
        var harness = H(startingAt: H.at(10, 25))
        harness.schedule.snooze(now: harness.now, preferences: harness.preferences)
        #expect(harness.schedule.nextFire == H.at(10, 35))
        #expect(harness.fires(until: H.at(10, 40)).map(\.0) == [H.at(10, 35)])
    }

    @Test func snoozeWhileDeferredHoldsTheSameBreak() {
        var harness = H(startingAt: H.at(10, 29))
        harness.microphone = true
        _ = harness.run(until: H.at(10, 31))
        harness.schedule.snooze(now: harness.now, preferences: harness.preferences)
        harness.microphone = false
        #expect(harness.fires(until: H.at(10, 45)).map(\.0) == [H.at(10, 41)])
    }

    // MARK: - Sleep

    /// Regression: a break that fell due during sleep opened the instant the
    /// Mac woke up.
    @Test func longSleepDoesNotFireOnWake() {
        var harness = H(startingAt: H.at(11, 55))
        _ = harness.run(until: H.at(11, 58))
        harness.now = H.at(13, 10) // woke up after lunch
        #expect(harness.tick() == nil)
        let fires = harness.fires(until: H.at(13, 31))
        #expect(fires.map(\.0) == [H.at(13, 30)])
    }

    @Test func shortSleepFiresAfterSettling() {
        var harness = H(startingAt: H.at(10, 25))
        _ = harness.run(until: H.at(10, 29))
        harness.now = H.at(10, 31) // lid closed for two minutes
        #expect(harness.tick() == nil)
        let fires = harness.fires(until: H.at(10, 33))
        #expect(fires.map(\.0) == [H.at(10, 31).addingTimeInterval(BreakSchedule.settleSeconds)])
    }

    // MARK: - Controls

    @Test func pausedScheduleNeverFires() {
        var harness = H(startingAt: H.at(10, 5))
        harness.schedule.pause()
        #expect(harness.fires(until: H.at(12, 0)).isEmpty)
        harness.schedule.resume(now: harness.now, preferences: harness.preferences)
        #expect(harness.schedule.nextFire == H.at(12, 30))
        #expect(harness.fires(until: H.at(12, 30)).count == 1)
    }

    @Test func manualBreakSupersedesAWaitingOne() {
        var harness = H(startingAt: H.at(10, 29))
        harness.microphone = true
        _ = harness.run(until: H.at(10, 31))
        harness.schedule.openedManually()
        harness.microphone = false
        #expect(harness.fires(until: H.at(10, 35)).isEmpty)
    }

    @Test func changedIntervalsTakeEffectImmediately() {
        var harness = H(startingAt: H.at(10, 5))
        harness.preferences.microInterval = 15
        harness.schedule.reschedule(now: harness.now, preferences: harness.preferences)
        #expect(harness.schedule.nextFire == H.at(10, 15))
    }
}
