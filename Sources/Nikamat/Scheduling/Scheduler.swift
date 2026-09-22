import Foundation

/// Runs a `BreakSchedule` against the real clock and the real Mac.
///
/// All the decisions live in `BreakSchedule`; this class only supplies what it
/// needs every second and carries out what it returns: a notification for a
/// warning, `onFire` for a break.
///
/// Observable only for the paused state, which the settings window shows as
/// a switch; everything else is read on demand.
@MainActor
final class Scheduler: ObservableObject {
    /// Called when a break should open.
    var onFire: ((Tier) -> Void)?
    /// Called every second, for the menu bar countdown.
    var onTick: (() -> Void)?

    private(set) var schedule: BreakSchedule
    private let settings: Settings
    private let sensors: PresenceSensing
    private let notifier: Notifier
    private var timer: Timer?

    var nextFire: Date { schedule.nextFire }
    var nextTier: Tier { schedule.nextTier }
    var isPaused: Bool { schedule.isPaused }
    var deferralReason: String? { schedule.deferralReason }

    private var preferences: Preferences { settings.preferences }

    init(settings: Settings, sensors: PresenceSensing = SystemSensors(), notifier: Notifier) {
        self.settings = settings
        self.sensors = sensors
        self.notifier = notifier
        schedule = BreakSchedule(now: Date(), preferences: settings.preferences)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - Controls

    func pause() {
        objectWillChange.send()
        schedule.pause()
    }

    func resume() {
        objectWillChange.send()
        schedule.resume(now: Date(), preferences: preferences)
    }

    func snooze(tier: Tier? = nil) {
        schedule.snooze(tier: tier, now: Date(), preferences: preferences)
    }

    /// Open a break right now, outside the schedule.
    func fireNow(tier: Tier) {
        schedule.openedManually()
        onFire?(tier)
    }

    func reschedule() { schedule.reschedule(now: Date(), preferences: preferences) }
    func breakFinished() { schedule.breakFinished(now: Date(), preferences: preferences) }

    // MARK: - The loop

    private func tick() {
        let action = schedule.tick(now: Date(), preferences: preferences, sensors: sensors)
        onTick?()
        switch action {
        case .warn(let tier):
            notifier.announce(
                title: tier == .long ? "Pitkä tauko alkaa" : "Mikrotauko alkaa",
                body: "Nikamat avaa harjoituksen hetken kuluttua.",
                withSound: preferences.playSounds
            )
        case .fire(let tier):
            onFire?(tier)
        case nil:
            break
        }
    }
}

/// The real sensors: HID idle time and Core Audio.
struct SystemSensors: PresenceSensing {
    var secondsSinceInput: Double { IdleMonitor.secondsSinceInput }
    var microphoneInUse: Bool { MicrophoneMonitor.isInUse }
}
