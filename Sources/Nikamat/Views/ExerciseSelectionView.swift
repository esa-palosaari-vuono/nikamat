import SwiftUI

/// Settings tab for choosing which exercises breaks may include, grouped by
/// body region, each with a drawing of its end pose.
struct ExerciseSelectionView: View {
    @ObservedObject var settings: Settings

    private var disabled: Set<String> { settings.preferences.disabledExercises }

    var body: some View {
        Form {
            Section {
                Text("Valitse, mitkä liikkeet voivat tulla tauoille. Uudet liikkeet ovat oletuksena mukana.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let warning = coverageWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                if !disabled.isEmpty {
                    Button("Ota kaikki mukaan") { settings.preferences.disabledExercises = [] }
                }
            }

            ForEach(Region.allCases, id: \.self) { region in
                let exercises = ExerciseLibrary.all.filter { $0.region == region }
                if !exercises.isEmpty {
                    Section(region.label) {
                        ForEach(exercises) { row(for: $0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(for exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            FigureView(
                pose: exercise.keyframes.last ?? .neutral,
                orientation: exercise.orientation,
                highlight: exercise.highlight,
                prop: exercise.prop
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.system(size: 13, weight: .medium))
                Text(caption(for: exercise))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding(for: exercise))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isLastForMicroBreaks(exercise))
                .help(isLastForMicroBreaks(exercise)
                      ? "Mikrotauoille tarvitaan vähintään yksi liike."
                      : "")
        }
        .opacity(disabled.contains(exercise.id) ? 0.55 : 1)
    }

    private func caption(for exercise: Exercise) -> String {
        let tiers = exercise.tiers.contains(.micro) ? "mikro- ja pitkät tauot" : "vain pitkät tauot"
        return "\(exercise.posture.label) · \(Int(exercise.duration())) s · \(tiers)"
    }

    private func binding(for exercise: Exercise) -> Binding<Bool> {
        Binding(
            get: { !disabled.contains(exercise.id) },
            set: { enabled in
                if enabled {
                    settings.preferences.disabledExercises.remove(exercise.id)
                } else {
                    settings.preferences.disabledExercises.insert(exercise.id)
                }
            }
        )
    }

    /// Switching this one off would leave micro breaks with nothing to show,
    /// and they would stop opening without any explanation.
    private func isLastForMicroBreaks(_ exercise: Exercise) -> Bool {
        guard !disabled.contains(exercise.id), exercise.tiers.contains(.micro) else { return false }
        return ExerciseLibrary.pool(for: .micro, allowStanding: false, excluding: disabled).count == 1
    }

    /// Breaks draw one exercise per region: two for a micro break, five for a
    /// long one. Fewer regions left means shorter, less varied breaks.
    private var coverageWarning: String? {
        let preferences = settings.preferences
        let long = ExerciseLibrary.pool(
            for: .long, allowStanding: preferences.includeStanding, excluding: disabled
        )
        let micro = ExerciseLibrary.pool(for: .micro, allowStanding: false, excluding: disabled)
        let longRegions = Set(long.map(\.region)).count
        let microRegions = Set(micro.map(\.region)).count
        if microRegions < 2 {
            return "Mikrotauot jäävät yhden liikkeen mittaisiksi: valittuna on liikkeitä vain yhdeltä alueelta."
        }
        if longRegions < 5 {
            return "Pitkät tauot kootaan \(longRegions) alueesta viiden sijaan, joten ne jäävät lyhyemmiksi."
        }
        return nil
    }
}
