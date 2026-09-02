import SwiftUI

/// Settings, grouped by the question each group answers: how often, how long,
/// and when to keep quiet.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    /// Called when a change affects the timing, so the schedule is recomputed
    /// immediately rather than at the next boundary of the old interval.
    let onRhythmChanged: () -> Void

    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Rytmi") {
                Stepper(value: $settings.microInterval, in: 10...120, step: 5) {
                    LabeledContent("Mikrotauko", value: "\(settings.microInterval) min välein")
                }
                Stepper(value: $settings.longInterval, in: 20...240, step: 10) {
                    LabeledContent("Pitkä tauko", value: "\(settings.longInterval) min välein")
                }
                Text("Kun molemmat osuvat samaan hetkeen, pidetään pitkä tauko.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .onChange(of: settings.microInterval) { onRhythmChanged() }
            .onChange(of: settings.longInterval) { onRhythmChanged() }

            Section("Pituus") {
                Stepper(value: $settings.microTarget, in: 30...240, step: 15) {
                    LabeledContent("Mikrotauon tavoite", value: "\(settings.microTarget) s")
                }
                Stepper(value: $settings.longTarget, in: 60...600, step: 15) {
                    LabeledContent("Pitkän tauon tavoite", value: "\(settings.longTarget) s")
                }
                Toggle("Sisällytä seisten tehtävät liikkeet pitkiin taukoihin",
                       isOn: $settings.includeStanding)
                Text("Liikkeiden kestot skaalataan näihin tavoitteisiin.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section("Milloin olla hiljaa") {
                HStack {
                    Text("Hiljainen aika")
                    Spacer()
                    Picker("", selection: $settings.quietStart) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)) }
                    }
                    .labelsHidden().frame(width: 64)
                    Text("–")
                    Picker("", selection: $settings.quietEnd) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)) }
                    }
                    .labelsHidden().frame(width: 64)
                }
                Toggle("Ohita tauko jos et ole koneella", isOn: $settings.respectIdle)
                if settings.respectIdle {
                    Stepper(value: $settings.idleMinutes, in: 1...30) {
                        LabeledContent("Poissaolon raja", value: "\(settings.idleMinutes) min")
                    }
                }
                Toggle("Siirrä taukoa kun mikrofoni on käytössä",
                       isOn: $settings.deferForMicrophone)
                Text("Estää tauon avautumisen kesken palaverin. Perustuu vain siihen onko jokin sovellus äänittämässä.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section("Muut") {
                Stepper(value: $settings.warningSeconds, in: 0...60, step: 5) {
                    LabeledContent(
                        "Ennakkovaroitus",
                        value: settings.warningSeconds == 0 ? "ei käytössä" : "\(settings.warningSeconds) s"
                    )
                }
                Stepper(value: $settings.snoozeMinutes, in: 1...60) {
                    LabeledContent("Lykkäys", value: "\(settings.snoozeMinutes) min")
                }
                Toggle("Äänimerkit", isOn: $settings.playSounds)
                Toggle("Näytä laskuri valikkopalkissa", isOn: $settings.showCountdown)
                Toggle("Käynnistä kirjautumisen yhteydessä", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LoginItem.setEnabled(launchAtLogin) }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
    }
}
