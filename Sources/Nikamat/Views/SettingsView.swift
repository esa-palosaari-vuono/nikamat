import SwiftUI

/// Settings, grouped by the question each group answers: how often, how long,
/// and when to keep quiet.
///
/// Also the way into the app when macOS has hidden the menu bar item, so it
/// can start a break as well.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var scheduler: Scheduler
    /// Called when a change affects the timing, so the schedule is recomputed
    /// immediately rather than at the next boundary of the old interval.
    let onRhythmChanged: () -> Void
    /// Open a break right now, as the menu's own commands do.
    let onStartBreak: (Tier) -> Void

    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Muistutukset") {
                Toggle("Muistutukset päällä", isOn: Binding(
                    get: { !scheduler.isPaused },
                    set: { $0 ? scheduler.resume() : scheduler.pause() }
                ))
                HStack {
                    Button("Aloita mikrotauko") { onStartBreak(.micro) }
                    Button("Aloita pitkä tauko") { onStartBreak(.long) }
                }
            }

            Section("Rytmi") {
                Stepper(value: $settings.preferences.microInterval, in: 10...120, step: 5) {
                    LabeledContent("Mikrotauko", value: "\(settings.preferences.microInterval) min välein")
                }
                Stepper(value: $settings.preferences.longInterval, in: 20...240, step: 10) {
                    LabeledContent("Pitkä tauko", value: "\(settings.preferences.longInterval) min välein")
                }
                Text("Kun molemmat osuvat samaan hetkeen, pidetään pitkä tauko.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .onChange(of: settings.preferences.microInterval) { onRhythmChanged() }
            .onChange(of: settings.preferences.longInterval) { onRhythmChanged() }

            Section("Pituus") {
                Stepper(value: $settings.preferences.microTarget, in: 30...240, step: 15) {
                    LabeledContent("Mikrotauon tavoite", value: "\(settings.preferences.microTarget) s")
                }
                Stepper(value: $settings.preferences.longTarget, in: 60...600, step: 15) {
                    LabeledContent("Pitkän tauon tavoite", value: "\(settings.preferences.longTarget) s")
                }
                // Only meaningful while the library has something to stand for.
                if ExerciseLibrary.all.contains(where: { $0.posture == .standing }) {
                    Toggle("Sisällytä seisten tehtävät liikkeet pitkiin taukoihin",
                           isOn: $settings.preferences.includeStanding)
                }
                Text("Liikkeiden kestot skaalataan näihin tavoitteisiin.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section("Milloin olla hiljaa") {
                HStack {
                    Text("Hiljainen aika")
                    Spacer()
                    Picker("", selection: $settings.preferences.quietStart) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)) }
                    }
                    .labelsHidden().frame(width: 64)
                    Text("–")
                    Picker("", selection: $settings.preferences.quietEnd) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)) }
                    }
                    .labelsHidden().frame(width: 64)
                }
                Toggle("Ohita tauko jos et ole koneella", isOn: $settings.preferences.respectIdle)
                if settings.preferences.respectIdle {
                    Stepper(value: $settings.preferences.idleMinutes, in: 1...30) {
                        LabeledContent("Poissaolon raja", value: "\(settings.preferences.idleMinutes) min")
                    }
                }
                Toggle("Siirrä taukoa kun mikrofoni on käytössä",
                       isOn: $settings.preferences.deferForMicrophone)
                Text("Estää tauon avautumisen kesken palaverin. Perustuu vain siihen onko jokin sovellus äänittämässä.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section("Muut") {
                Stepper(value: $settings.preferences.warningSeconds, in: 0...60, step: 5) {
                    LabeledContent(
                        "Ennakkovaroitus",
                        value: settings.preferences.warningSeconds == 0 ? "ei käytössä" : "\(settings.preferences.warningSeconds) s"
                    )
                }
                Stepper(value: $settings.preferences.snoozeMinutes, in: 1...60) {
                    LabeledContent("Lykkäys", value: "\(settings.preferences.snoozeMinutes) min")
                }
                Toggle("Äänimerkit", isOn: $settings.preferences.playSounds)
                Toggle("Näytä laskuri valikkopalkissa", isOn: $settings.preferences.showCountdown)
                Toggle("Käynnistä kirjautumisen yhteydessä", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LoginItem.setEnabled(launchAtLogin) }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 640)
    }
}
