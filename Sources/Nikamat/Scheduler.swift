import Foundation

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
@MainActor
final class Scheduler: ObservableObject {
    @Published private(set) var nextFire = Date()
    @Published private(set) var nextTier: Tier = .micro
    @Published private(set) var isPaused = false
    /// Why a due break has not opened yet, for the menu to explain itself.
    @Published private(set) var deferralReason: String?

    /// Called when a break should open.
    var onFire: ((Tier) -> Void)?
    /// Called every second, for the menu bar countdown.
    var onTick: (() -> Void)?

    private let settings: Settings
    private var timer: Timer?

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

    /// Grace period after coming back to the desk. Walking in and being handed
    /// a stretch before you have put your coffee down is its own annoyance.
    private let settleSeconds: TimeInterval = 45
    /// How long a deferred break keeps trying before it is written off.
    private let giveUpAfter: TimeInterval = 20 * 60

    init(settings: Settings) {
        self.settings = settings
        scheduleNext(after: Date())
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - Controls

    func pause() {
        isPaused = true
        pending = nil
        deferralReason = nil
    }

    func resume() {
        isPaused = false
        warned = false
        scheduleNext(after: Date())
    }

    /// Push the current or next break back by the configured snooze.
    func snooze() {
        let until = Date().addingTimeInterval(Double(settings.snoozeMinutes) * 60)
        snoozeUntil = until
        if pending == nil {
            // Nothing was due, so move the schedule itself rather than
            // silently arriving at the original time anyway.
            nextFire = max(nextFire, until)
        }
        warned = false
    }

    /// Open a break right now, outside the schedule.
    func fireNow(tier: Tier) {
        pending = nil
        warned = false
        deferralReason = nil
        onFire?(tier)
    }

    /// Recompute the schedule, e.g. after the intervals were changed.
    func reschedule() {
        scheduleNext(after: Date())
        warned = false
    }

    /// Called when a break window closes, so the next one is measured from now
    /// rather than from a boundary that may already have passed.
    func breakFinished() {
        scheduleNext(after: Date())
        warned = false
        deferralReason = nil
    }

    // MARK: - Schedule arithmetic

    /// The next time an interval of `minutes` divides the day, after `date`.
    private func nextBoundary(minutes: Int, after date: Date) -> Date {
        let interval = Double(max(1, minutes)) * 60
        let midnight = Calendar.current.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(midnight)
        let index = (elapsed / interval).rounded(.down) + 1
        return midnight.addingTimeInterval(index * interval)
    }

    private func scheduleNext(after date: Date) {
        let micro = nextBoundary(minutes: settings.microInterval, after: date)
        let long = nextBoundary(minutes: settings.longInterval, after: date)
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

    private func tick() {
        let now = Date()
        updatePresence(now: now)
        onTick?()

        guard !isPaused else { return }

        if pending == nil {
            if now >= nextFire {
                pending = Pending(tier: nextTier, due: nextFire)
                warned = true
                scheduleNext(after: nextFire)
            } else if !warned, settings.warningSeconds > 0,
                      now >= nextFire.addingTimeInterval(-Double(settings.warningSeconds)),
                      case .allowed = readiness(now: now) {
                warned = true
                let tier = nextTier
                Notifier.shared.announce(
                    title: tier == .long ? "Pitkä tauko alkaa" : "Mikrotauko alkaa",
                    body: "Nikamat avaa harjoituksen hetken kuluttua.",
                    withSound: settings.playSounds
                )
            }
        }

        guard let pending else { return }
        switch readiness(now: now) {
        case .allowed:
            self.pending = nil
            warned = false
            deferralReason = nil
            onFire?(pending.tier)
        case .blocked(let reason, let abandon):
            deferralReason = reason
            if abandon || now.timeIntervalSince(pending.due) > giveUpAfter {
                self.pending = nil
                warned = false
            }
        }
    }

    private func updatePresence(now: Date) {
        let idle = IdleMonitor.secondsSinceInput
        let threshold = Double(max(1, settings.idleMinutes)) * 60
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

    private func readiness(now: Date) -> Readiness {
        if settings.isQuiet(at: now) {
            return .blocked("hiljainen aika", abandon: true)
        }
        if let until = snoozeUntil {
            if now < until { return .blocked("lykätty", abandon: false) }
            snoozeUntil = nil
        }
        if settings.respectIdle {
            if awayNow {
                return .blocked("et ole koneella", abandon: false)
            }
            if let returned = returnedAt, now.timeIntervalSince(returned) < settleSeconds {
                return .blocked("juuri palasit", abandon: false)
            }
        }
        if settings.deferForMicrophone, MicrophoneMonitor.isInUse {
            return .blocked("mikrofoni käytössä", abandon: false)
        }
        return .allowed
    }
}
