import Foundation

/// Which of the two break lengths an exercise is eligible for.
enum Tier: String, Codable, CaseIterable {
    case micro
    case long

    var title: String {
        switch self {
        case .micro: return "Mikrotauko"
        case .long: return "Pitkä tauko"
        }
    }
}

/// Whether the exercise can be done without leaving the chair. Standing
/// exercises are kept out of micro breaks: the point of a 60-second break is
/// that the threshold to actually do it stays near zero.
enum Posture: String, Codable {
    case seated
    case standing

    var label: String {
        switch self {
        case .seated: return "istuen"
        case .standing: return "seisten"
        }
    }
}

/// The body area an exercise targets. Used to compose a varied break rather
/// than four neck stretches in a row.
enum Region: String, Codable, CaseIterable {
    case neck
    case traps
    case shoulders
    case scapulae
    case chest
    case thoracic

    var label: String {
        switch self {
        case .neck: return "Niska"
        case .traps: return "Ylätrapetsi"
        case .shoulders: return "Hartiat"
        case .scapulae: return "Lapaluut"
        case .chest: return "Rintakehä"
        case .thoracic: return "Rintaranka"
        }
    }
}

/// The viewpoint the figure is drawn from. Chosen per exercise for whichever
/// angle actually shows the movement: chin tucks are invisible from the front,
/// scapular retraction is invisible from anywhere but behind.
enum Orientation: Codable {
    case front
    case side
    case back
}

/// A prop drawn alongside the figure so a standing exercise reads correctly.
enum Prop: Codable {
    case wall
    case doorway
}

/// Which region to accent in the drawing, drawing the eye to the part that
/// should be working.
enum Highlight: Codable {
    case none
    case neck
    case traps
    case shoulders
    case scapulae
    case chest
    case thoracic
}

/// How an exercise is timed, and by extension how its keyframes are traversed.
///
/// The same value drives the countdown and the animation, so what the figure is
/// doing always matches what the timer says — a held stretch eases in and
/// stays, isometric repetitions pulse, and rolls loop continuously.
enum MovementPattern: Equatable {
    /// A sustained stretch: ease into the end pose, hold, ease out.
    case hold(seconds: Double)
    /// Isometric repetitions: contract, hold, release, repeat.
    case reps(count: Int, hold: Double, release: Double)
    /// Continuous cycling through all keyframes, e.g. shoulder rolls.
    case cycle(count: Int, period: Double)

    var duration: Double {
        switch self {
        case .hold(let s): return s
        case .reps(let n, let h, let r): return Double(n) * (h + r)
        case .cycle(let n, let p): return Double(n) * p
        }
    }

    /// Shortened or lengthened while keeping the pattern sensible: repetition
    /// and cycle counts stay whole numbers and never drop below one, and holds
    /// never fall under four seconds, which is about the shortest stretch that
    /// does anything.
    func scaled(by factor: Double) -> MovementPattern {
        switch self {
        case .hold(let s):
            return .hold(seconds: max(4, (s * factor).rounded()))
        case .reps(let n, let h, let r):
            return .reps(count: max(1, Int((Double(n) * factor).rounded())), hold: h, release: r)
        case .cycle(let n, let p):
            return .cycle(count: max(1, Int((Double(n) * factor).rounded())), period: p)
        }
    }
}

/// What the figure should look like right now, plus the words that go with it.
struct MovementFrame {
    var pose: Pose
    /// Short imperative shown inside the countdown ring: "pidä", "rentouta".
    var phase: String
    /// 1-based repetition or cycle number, when the pattern has them.
    var repetition: Int?
    var repetitionCount: Int?
}

/// One exercise: what it is called, what it targets, how it is timed, and the
/// keyframes the figure moves through.
struct Exercise: Identifiable {
    let id: String
    let name: String
    let region: Region
    let posture: Posture
    let tiers: Set<Tier>
    let orientation: Orientation
    let highlight: Highlight
    let prop: Prop?
    /// One line telling the user what to do, read at a glance mid-stretch.
    let cue: String
    /// Optional second line: refinement, safety note, or what should be felt.
    let note: String?
    /// Labels for the two repetitions of a bilateral exercise. `nil` means the
    /// exercise is performed once, symmetrically.
    let sides: [String]?
    let pattern: MovementPattern
    /// Keyframes for the *first* side. The second side uses `Pose.mirrored`.
    /// `hold` and `reps` read the first and last entries; `cycle` loops all.
    let keyframes: [Pose]

    /// Total planned seconds including both sides.
    func duration(scale: Double = 1) -> Double {
        pattern.scaled(by: scale).duration * Double(sides?.count ?? 1)
    }
}
