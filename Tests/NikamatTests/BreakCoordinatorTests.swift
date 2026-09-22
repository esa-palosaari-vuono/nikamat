import Foundation
import Testing
@testable import Nikamat

@MainActor
private final class FakeDisplay: BreakDisplay {
    var onUserClose: (() -> Void)?
    var shown = 0
    var closed = 0
    var pressSnooze: (() -> Void)?
    var pressClose: (() -> Void)?

    func show(session: BreakSession, log: BreakLog, onSnooze: @escaping () -> Void, onClose: @escaping () -> Void) {
        shown += 1
        pressSnooze = onSnooze
        pressClose = onClose
    }

    func close() { closed += 1 }
}

/// Every way a break can end, end to end: session, log, window and schedule
/// callbacks together.
@MainActor
struct BreakCoordinatorTests {
    private let clock = ManualClock()
    private let display = FakeDisplay()
    private let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("nikamat-test-\(UUID().uuidString).sqlite3").path
    private let log: BreakLog
    private let coordinator: BreakCoordinator

    /// Delayed actions, run by hand.
    private final class Deferred { var actions: [@MainActor () -> Void] = [] }
    private let deferred = Deferred()

    private final class Events { var snoozed: [Tier] = []; var ended = 0 }
    private let events = Events()

    private var session: BreakSession?

    init() {
        log = BreakLog(path: path)
        let clock = clock, deferred = deferred, events = events
        coordinator = BreakCoordinator(
            log: log,
            display: display,
            preferences: { Preferences() },
            makeSession: { BreakSession(plan: $0, clock: { clock.now }, autoAdvance: false) },
            after: { _, action in deferred.actions.append(action) }
        )
        coordinator.onSnoozed = { events.snoozed.append($0) }
        coordinator.onEnded = { events.ended += 1 }
    }

    private func outcomes() throws -> [String] {
        try Database(path: path).query("SELECT outcome FROM breaks ORDER BY id") { $0.text(0) }
    }

    private func runDeferred() {
        let actions = deferred.actions
        deferred.actions = []
        actions.forEach { $0() }
    }

    @Test func closeRightAwayLogsSkippedAndClosesAfterTheClosingScreen() throws {
        coordinator.start(tier: .micro)
        #expect(display.shown == 1)
        #expect(coordinator.isRunning)

        display.pressClose?()
        #expect(try outcomes() == ["skipped"])
        #expect(display.closed == 0, "the closing screen stays up briefly")

        runDeferred()
        #expect(display.closed == 1)
        #expect(events.ended == 1)
        #expect(!coordinator.isRunning)
        #expect(events.snoozed.isEmpty)
    }

    @Test func snoozeLogsAndHandsTheTierBack() throws {
        coordinator.start(tier: .long)
        display.pressSnooze?()
        #expect(try outcomes() == ["snoozed"])
        #expect(events.snoozed == [.long])
        runDeferred()
        #expect(events.ended == 1)
    }

    @Test func closeButtonOnTheWindowLogsAndEndsAtOnce() throws {
        coordinator.start(tier: .micro)
        display.onUserClose?()
        #expect(try outcomes() == ["skipped"])
        #expect(events.ended == 1)
        #expect(display.closed == 0, "the window is already closing itself")
        // The closing-screen timer that was queued must not end it again.
        runDeferred()
        #expect(events.ended == 1)
    }

    @Test func closingTheClosingScreenEndsAtOnce() throws {
        coordinator.start(tier: .micro)
        display.pressSnooze?()
        display.pressClose?()
        #expect(events.ended == 1)
        #expect(display.closed == 1)
        runDeferred()
        #expect(events.ended == 1)
        #expect(try outcomes() == ["snoozed"])
    }

    @Test func aSecondBreakWhileOneIsOpenIsIgnored() {
        coordinator.start(tier: .micro)
        coordinator.start(tier: .long)
        #expect(display.shown == 1)
    }

    @Test func aNewBreakCanStartAfterTheLastEnded() throws {
        coordinator.start(tier: .micro)
        display.pressClose?()
        runDeferred()
        coordinator.start(tier: .micro)
        #expect(display.shown == 2)
        #expect(coordinator.isRunning)
    }
}
