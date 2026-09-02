import Foundation

/// User-adjustable behaviour, persisted in the standard user defaults.
///
/// Values are kept as plain properties with a `didSet` that writes through,
/// which keeps SwiftUI bindings trivial while still surviving a restart.
@MainActor
final class Settings: ObservableObject {
    private static let store = UserDefaults.standard

    /// Minutes between the short seated breaks.
    @Published var microInterval: Int { didSet { write() } }
    /// Minutes between the longer breaks. When a long break coincides with a
    /// micro break, the long one wins.
    @Published var longInterval: Int { didSet { write() } }
    /// Target length of each break in seconds. Exercise timings are scaled to
    /// land near these numbers.
    @Published var microTarget: Int { didSet { write() } }
    @Published var longTarget: Int { didSet { write() } }
    /// Allow exercises that require getting up, in long breaks.
    @Published var includeStanding: Bool { didSet { write() } }
    /// No breaks between these hours.
    @Published var quietStart: Int { didSet { write() } }
    @Published var quietEnd: Int { didSet { write() } }
    /// Skip a break when the Mac has had no input for this many minutes:
    /// you are not at the desk, so there is nothing to interrupt.
    @Published var respectIdle: Bool { didSet { write() } }
    @Published var idleMinutes: Int { didSet { write() } }
    /// Postpone a break while an audio input device is running — the cheapest
    /// available proxy for "in a meeting".
    @Published var deferForMicrophone: Bool { didSet { write() } }
    /// Seconds of advance warning before the window appears. 0 disables it.
    @Published var warningSeconds: Int { didSet { write() } }
    @Published var playSounds: Bool { didSet { write() } }
    @Published var showCountdown: Bool { didSet { write() } }
    @Published var snoozeMinutes: Int { didSet { write() } }

    init() {
        let d = Self.store
        func int(_ key: String, _ fallback: Int) -> Int {
            d.object(forKey: key) as? Int ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) as? Bool ?? fallback
        }
        microInterval = int("microInterval", 30)
        longInterval = int("longInterval", 60)
        microTarget = int("microTarget", 60)
        longTarget = int("longTarget", 190)
        includeStanding = bool("includeStanding", true)
        quietStart = int("quietStart", 22)
        quietEnd = int("quietEnd", 7)
        respectIdle = bool("respectIdle", true)
        idleMinutes = int("idleMinutes", 4)
        deferForMicrophone = bool("deferForMicrophone", true)
        warningSeconds = int("warningSeconds", 15)
        playSounds = bool("playSounds", true)
        showCountdown = bool("showCountdown", true)
        snoozeMinutes = int("snoozeMinutes", 10)
    }

    private func write() {
        let d = Self.store
        d.set(microInterval, forKey: "microInterval")
        d.set(longInterval, forKey: "longInterval")
        d.set(microTarget, forKey: "microTarget")
        d.set(longTarget, forKey: "longTarget")
        d.set(includeStanding, forKey: "includeStanding")
        d.set(quietStart, forKey: "quietStart")
        d.set(quietEnd, forKey: "quietEnd")
        d.set(respectIdle, forKey: "respectIdle")
        d.set(idleMinutes, forKey: "idleMinutes")
        d.set(deferForMicrophone, forKey: "deferForMicrophone")
        d.set(warningSeconds, forKey: "warningSeconds")
        d.set(playSounds, forKey: "playSounds")
        d.set(showCountdown, forKey: "showCountdown")
        d.set(snoozeMinutes, forKey: "snoozeMinutes")
    }

    /// True when `date` falls inside the quiet window, handling the usual case
    /// where the window wraps past midnight.
    func isQuiet(at date: Date) -> Bool {
        guard quietStart != quietEnd else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if quietStart < quietEnd {
            return hour >= quietStart && hour < quietEnd
        }
        return hour >= quietStart || hour < quietEnd
    }
}
