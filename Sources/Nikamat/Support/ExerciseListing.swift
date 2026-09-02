import Foundation

/// `Nikamat --exercises` prints the library as an Org table.
///
/// The exercise reference in `docs/liikkeet.org` is generated from this rather
/// than written by hand, so the documentation cannot drift away from the code
/// that it documents.
@MainActor
enum ExerciseListing {
    static func printOrgTable() {
        print("| Liike | Alue | Asento | Kesto | Puolet | Tauko | Kuvakulma |")
        print("|-------+------+--------+-------+--------+-------+-----------|")
        for exercise in ExerciseLibrary.all {
            let tiers = Tier.allCases
                .filter { exercise.tiers.contains($0) }
                .map { $0 == .micro ? "mikro" : "pitkä" }
                .joined(separator: ", ")
            let orientation: String
            switch exercise.orientation {
            case .front: orientation = "edestä"
            case .side: orientation = "sivulta"
            case .back: orientation = "takaa"
            }
            let sides = exercise.sides?.joined(separator: " / ") ?? "–"
            print("""
                | \(exercise.name) | \(exercise.region.label) | \(exercise.posture.label) \
                | \(Int(exercise.duration())) s | \(sides) | \(tiers) | \(orientation) |
                """)
        }
        print("\n")
        for exercise in ExerciseLibrary.all {
            print("** \(exercise.name)")
            print("   :PROPERTIES:")
            print("   :ID: \(exercise.id)")
            print("   :ALUE: \(exercise.region.label)")
            print("   :END:")
            print("   \(exercise.cue).")
            if let note = exercise.note { print("\n   \(note)") }
            print()
        }
    }
}
