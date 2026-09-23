import Foundation

/// User-adjustable behaviour, as a plain value.
///
/// Everything that decides *what* happens takes this struct rather than the
/// persisted `Settings` object, so the planner and the schedule can be run
/// against any configuration without touching user defaults. The defaults
/// below are the defaults of a fresh install.
struct Preferences: Equatable {
    /// Minutes between the short seated breaks.
    var microInterval = 30
    /// Minutes between the longer breaks. When a long break coincides with a
    /// micro break, the long one wins.
    var longInterval = 60
    /// Target length of each break in seconds. Exercise timings are scaled to
    /// land near these numbers.
    var microTarget = 60
    var longTarget = 190
    /// Allow exercises that require getting up, in long breaks.
    var includeStanding = true
    /// No breaks between these hours.
    var quietStart = 22
    var quietEnd = 7
    /// Skip a break when the Mac has had no input for this many minutes:
    /// you are not at the desk, so there is nothing to interrupt.
    var respectIdle = true
    var idleMinutes = 4
    /// Postpone a break while an audio input device is running — the cheapest
    /// available proxy for "in a meeting".
    var deferForMicrophone = true
    /// Seconds of advance warning before the window appears. 0 disables it.
    var warningSeconds = 15
    var playSounds = true
    var showCountdown = true
    var snoozeMinutes = 10
    /// Exercises the user has switched off. Stored as the ones left out
    /// rather than the ones kept, so exercises added in later versions are
    /// included by default.
    var disabledExercises: Set<String> = []

    /// True when `date` falls inside the quiet window, handling the usual case
    /// where the window wraps past midnight.
    func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietStart != quietEnd else { return false }
        let hour = calendar.component(.hour, from: date)
        if quietStart < quietEnd {
            return hour >= quietStart && hour < quietEnd
        }
        return hour >= quietStart || hour < quietEnd
    }
}

/// `Preferences` persisted in user defaults and published to SwiftUI.
///
/// Each value is stored under its own key, so the defaults domain stays
/// readable with `defaults read fi.esapalosaari.nikamat`.
@MainActor
final class Settings: ObservableObject {
    @Published var preferences: Preferences {
        didSet { if preferences != oldValue { save() } }
    }

    private let store: UserDefaults

    /// The one list of stored keys. Adding a preference means adding it to
    /// `Preferences` and to one of these.
    private static let intKeys: [(String, WritableKeyPath<Preferences, Int>)] = [
        ("microInterval", \.microInterval),
        ("longInterval", \.longInterval),
        ("microTarget", \.microTarget),
        ("longTarget", \.longTarget),
        ("quietStart", \.quietStart),
        ("quietEnd", \.quietEnd),
        ("idleMinutes", \.idleMinutes),
        ("warningSeconds", \.warningSeconds),
        ("snoozeMinutes", \.snoozeMinutes),
    ]
    private static let boolKeys: [(String, WritableKeyPath<Preferences, Bool>)] = [
        ("includeStanding", \.includeStanding),
        ("respectIdle", \.respectIdle),
        ("deferForMicrophone", \.deferForMicrophone),
        ("playSounds", \.playSounds),
        ("showCountdown", \.showCountdown),
    ]
    /// The one preference that is not a scalar, stored as a sorted array.
    private static let disabledExercisesKey = "disabledExercises"

    init(store: UserDefaults = .standard) {
        self.store = store
        var loaded = Preferences()
        for (key, path) in Self.intKeys {
            if let value = store.object(forKey: key) as? Int { loaded[keyPath: path] = value }
        }
        for (key, path) in Self.boolKeys {
            if let value = store.object(forKey: key) as? Bool { loaded[keyPath: path] = value }
        }
        if let ids = store.stringArray(forKey: Self.disabledExercisesKey) {
            loaded.disabledExercises = Set(ids)
        }
        preferences = loaded
    }

    private func save() {
        for (key, path) in Self.intKeys { store.set(preferences[keyPath: path], forKey: key) }
        for (key, path) in Self.boolKeys { store.set(preferences[keyPath: path], forKey: key) }
        store.set(preferences.disabledExercises.sorted(), forKey: Self.disabledExercisesKey)
    }
}
