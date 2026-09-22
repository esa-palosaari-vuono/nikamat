import Foundation

/// What the schedule can observe about the person at the desk. Read only when
/// a decision needs it, because asking Core Audio is not free.
protocol PresenceSensing {
    /// Seconds since the last keyboard, mouse or trackpad input.
    var secondsSinceInput: Double { get }
    /// Whether any process is recording from an audio input.
    var microphoneInUse: Bool { get }
}

/// Decides when a break is due, and — more importantly — when it is not.
///
/// Break times are anchored to the clock rather than to when the app started,
/// so breaks land on the half hour and the hour and become predictable. A long
/// break wins whenever the two intervals coincide.
///
/// Most of the code here is about *not* firing. An interruption that arrives
/// while you are away from the desk, in a meeting, or working at night teaches
/// you to dismiss the app on sight, and an app you dismiss on reflex has
/// stopped working no matter how good its exercises are.
///
/// This is a plain value with no timer, clock or system calls of its own: the
/// caller supplies the time, the preferences and the sensors on every call,
/// and carries out whatever `tick` returns. `Scheduler` does that for the app;
/// tests do it with a hand-moved clock.
struct BreakSchedule {
    /// Something the caller should do as a result of a tick.
    enum Action: Equatable {
        /// Announce that a break is about to open.
        case warn(Tier)
        /// Open a break now.
        case fire(Tier)
    }

    private(set) var nextFire: Date
    private(set) var nextTier: Tier = .micro
    private(set) var isPaused = false
    /// Why a due break has not opened yet, for the menu to explain itself.
    private(set) var deferralReason: String?

    /// A break that is due but has not been able to open yet.
    private struct Pending {
        let tier: Tier
        let due: Date
    }
    private var pending: Pending?
    private var warned = false
    private var snoozeUntil: Date?

    /// Presence tracking. `awayNow` is the raw idle state; `returnedAt` is when
    /// input resumed after being away, which starts the settling period.
    private var awayNow = false
    private var returnedAt: Date?
    /// When the loop last ran. A long gap means the Mac was asleep, because
    /// the timer does not fire during sleep.
    private var lastTick: Date?

    private let calendar: Calendar

    /// Grace period after coming back to the desk. Walking in and being handed
    /// a stretch before you have put your coffee down is its own annoyance.
    static let settleSeconds: TimeInterval = 45
    /// How long a deferred break keeps trying before it is written off.
    static let giveUpAfter: TimeInterval = 20 * 60
    /// A gap between ticks longer than this is treated as sleep.
    static let sleepGap: TimeInterval = 30

    init(now: Date, preferences: Preferences, calendar: Calendar = .current) {
        self.calendar = calendar
        self.nextFire = now
        scheduleNext(after: now, preferences: preferences)
    }

    // MARK: - Controls

    mutating func pause() {
        isPaused = true
        pending = nil
        deferralReason = nil
    }

    mutating func resume(now: Date, preferences: Preferences) {
        isPaused = false
        warned = false
        scheduleNext(after: now, preferences: preferences)
    }

    /// Push the current or next break back by the configured snooze.
    ///
    /// `tier` is the break that was on screen when the user snoozed it from the
    /// break window. By then it has already left the schedule, so it has to be
    /// put back explicitly or it would simply be lost.
    mutating func snooze(tier: Tier? = nil, now: Date, preferences: Preferences) {
        let until = now.addingTimeInterval(Double(preferences.snoozeMinutes) * 60)
        snoozeUntil = until
        if let tier {
            pending = nil
            nextFire = until
            nextTier = tier
        } else if pending == nil {
            // Nothing was due, so move the schedule itself rather than
            // silently arriving at the original time anyway.
            nextFire = max(nextFire, until)
        }
        warned = false
    }

    /// A break was opened by hand, outside the schedule. Whatever was waiting
    /// is superseded by it.
    mutating func openedManually() {
        pending = nil
        warned = false
        deferralReason = nil
    }

    /// Recompute the schedule, e.g. after the intervals were changed.
    mutating func reschedule(now: Date, preferences: Preferences) {
        scheduleNext(after: now, preferences: preferences)
        warned = false
    }

    /// Called when a break window closes, so the next one is measured from now
    /// rather than from a boundary that may already have passed.
    mutating func breakFinished(now: Date, preferences: Preferences) {
        // A snoozed break has already been put back on the schedule, and
        // recomputing from the clock would throw it away again.
        if let until = snoozeUntil, until > now { return }
        scheduleNext(after: now, preferences: preferences)
        warned = false
        deferralReason = nil
    }

    // MARK: - Schedule arithmetic

    /// The next time an interval of `minutes` divides the day, after `date`.
    private func nextBoundary(minutes: Int, after date: Date) -> Date {
        let interval = Double(max(1, minutes)) * 60
        let midnight = calendar.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(midnight)
        let index = (elapsed / interval).rounded(.down) + 1
        return midnight.addingTimeInterval(index * interval)
    }

    private mutating func scheduleNext(after date: Date, preferences: Preferences) {
        let micro = nextBoundary(minutes: preferences.microInterval, after: date)
        let long = nextBoundary(minutes: preferences.longInterval, after: date)
        // Within a second of each other counts as the same moment, and the
        // long break is the one worth having.
        if long <= micro.addingTimeInterval(1) {
            nextFire = long
            nextTier = .long
        } else {
            nextFire = micro
            nextTier = .micro
        }
    }

    // MARK: - The loop

    /// Advance to `now`. Meant to be called about once a second.
    mutating func tick(now: Date, preferences: Preferences, sensors: PresenceSensing) -> Action? {
        if let lastTick, now.timeIntervalSince(lastTick) > Self.sleepGap {
            // Waking from sleep is coming back to the desk, and deserves the
            // same grace period as returning from idle.
            awayNow = false
            returnedAt = now
        }
        lastTick = now
        updatePresence(now: now, preferences: preferences, sensors: sensors)

        guard !isPaused else { return nil }

        if pending == nil {
            if now >= nextFire {
                pending = Pending(tier: nextTier, due: nextFire)
                warned = true
                // After sleep nextFire can lie far in the past; scheduling from
                // it would queue every boundary that was slept through.
                scheduleNext(after: max(nextFire, now), preferences: preferences)
            } else if !warned, preferences.warningSeconds > 0,
                      now >= nextFire.addingTimeInterval(-Double(preferences.warningSeconds)),
                      case .allowed = readiness(now: now, preferences: preferences, sensors: sensors) {
                warned = true
                return .warn(nextTier)
            }
        }

        guard let due = pending else { return nil }
        // Checked before readiness: a break that fell due while the Mac was
        // asleep must not open the moment it wakes up.
        if now.timeIntervalSince(due.due) > Self.giveUpAfter {
            pending = nil
            warned = false
            deferralReason = nil
            return nil
        }
        switch readiness(now: now, preferences: preferences, sensors: sensors) {
        case .allowed:
            pending = nil
            warned = false
            deferralReason = nil
            return .fire(due.tier)
        case .blocked(let reason, let abandon):
            deferralReason = reason
            if abandon {
                pending = nil
                warned = false
            }
            return nil
        }
    }

    private mutating func updatePresence(now: Date, preferences: Preferences, sensors: PresenceSensing) {
        let idle = sensors.secondsSinceInput
        let threshold = Double(max(1, preferences.idleMinutes)) * 60
        if idle > threshold {
            if !awayNow {
                awayNow = true
                returnedAt = nil
            }
        } else if awayNow, idle < 5 {
            awayNow = false
            returnedAt = now
        }
    }

    private enum Readiness {
        case allowed
        /// `abandon` means the reason will not resolve on its own, so the
        /// occurrence should be dropped rather than retried.
        case blocked(String, abandon: Bool)
    }

    private mutating func readiness(
        now: Date, preferences: Preferences, sensors: PresenceSensing
    ) -> Readiness {
        if preferences.isQuiet(at: now, calendar: calendar) {
            return .blocked("hiljainen aika", abandon: true)
        }
        if let until = snoozeUntil {
            if now < until { return .blocked("lykätty", abandon: false) }
            snoozeUntil = nil
        }
        if preferences.respectIdle {
            if awayNow {
                return .blocked("et ole koneella", abandon: false)
            }
            if let returned = returnedAt, now.timeIntervalSince(returned) < Self.settleSeconds {
                return .blocked("juuri palasit", abandon: false)
            }
        }
        if preferences.deferForMicrophone, sensors.microphoneInUse {
            return .blocked("mikrofoni käytössä", abandon: false)
        }
        return .allowed
    }
}
