import Foundation
import Testing
@testable import Nikamat

@MainActor
struct SettingsTests {
    /// A private defaults domain per test, so nothing touches the real one.
    private func scratchDefaults() -> UserDefaults {
        let name = "nikamat-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func freshInstallUsesDefaults() {
        #expect(Settings(store: scratchDefaults()).preferences == Preferences())
    }

    @Test func changesSurviveARestart() {
        let store = scratchDefaults()
        let settings = Settings(store: store)
        settings.preferences.microInterval = 45
        settings.preferences.deferForMicrophone = false
        let reloaded = Settings(store: store).preferences
        #expect(reloaded.microInterval == 45)
        #expect(reloaded.deferForMicrophone == false)
        #expect(reloaded.longInterval == Preferences().longInterval)
    }

    @Test func disabledExercisesSurviveARestart() {
        let store = scratchDefaults()
        let settings = Settings(store: store)
        settings.preferences.disabledExercises = ["chin-tuck", "wy-raise"]
        #expect(Settings(store: store).preferences.disabledExercises == ["chin-tuck", "wy-raise"])
        settings.preferences.disabledExercises = []
        #expect(Settings(store: store).preferences.disabledExercises.isEmpty)
    }

    /// Keys written by earlier versions must still be read.
    @Test func readsExistingKeys() {
        let store = scratchDefaults()
        store.set(20, forKey: "snoozeMinutes")
        store.set(false, forKey: "showCountdown")
        let preferences = Settings(store: store).preferences
        #expect(preferences.snoozeMinutes == 20)
        #expect(preferences.showCountdown == false)
    }

    private func date(hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: hour, minute: 30))!
    }

    @Test func quietHoursWrapPastMidnight() {
        let preferences = Preferences() // 22–07
        #expect(preferences.isQuiet(at: date(hour: 23)))
        #expect(preferences.isQuiet(at: date(hour: 3)))
        #expect(!preferences.isQuiet(at: date(hour: 7)))
        #expect(!preferences.isQuiet(at: date(hour: 12)))
    }

    @Test func quietHoursWithinOneDay() {
        var preferences = Preferences()
        preferences.quietStart = 12
        preferences.quietEnd = 13
        #expect(preferences.isQuiet(at: date(hour: 12)))
        #expect(!preferences.isQuiet(at: date(hour: 13)))
    }

    @Test func equalBoundsMeanNoQuietHours() {
        var preferences = Preferences()
        preferences.quietStart = 9
        preferences.quietEnd = 9
        #expect(!preferences.isQuiet(at: date(hour: 9)))
    }
}
