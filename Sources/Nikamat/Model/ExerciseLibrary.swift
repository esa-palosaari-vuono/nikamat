import CoreGraphics
import Foundation

/// The exercise catalogue: neck, upper trapezius, shoulders, scapulae, chest
/// and thoracic spine — the chain that stiffens when you sit at a keyboard.
///
/// Each entry authors only the *first* side; the mirrored side is derived, so a
/// pose tweak can never leave the two directions asymmetrical. Poses are
/// written in the units of `Body`: degrees for joints, head units for
/// positions.
enum ExerciseLibrary {

    /// Both arms in the same configuration, the left one mirrored so that
    /// sided anchors land on the correct temple, shoulder or doorframe.
    private static func both(_ arm: ArmPose) -> (left: ArmPose, right: ArmPose) {
        (left: arm.mirrored, right: arm)
    }

    static let all: [Exercise] = [

        // MARK: - Neck

        Exercise(
            id: "neck-side-bend",
            name: "Niskan sivutaivutus",
            region: .neck,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .front,
            highlight: .traps,
            prop: nil,
            cue: "Taivuta päätä hitaasti sivulle, korva kohti olkapäätä",
            note: "Vastakkainen olkapää pysyy alhaalla. Älä auta käsin — pään oma paino riittää.",
            sides: ["oikealle", "vasemmalle"],
            pattern: .hold(seconds: 22),
            keyframes: [
                Pose(),
                Pose(headTilt: 32, left: ArmPose(shoulderLift: -0.35))
            ]
        ),

        Exercise(
            id: "neck-rotation",
            name: "Niskan kierto",
            region: .neck,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .front,
            highlight: .neck,
            prop: nil,
            cue: "Käännä katse rauhassa olkapään yli",
            note: "Hartiat pysyvät paikallaan. Pysähdy siihen mihin liike luonnollisesti loppuu.",
            sides: ["oikealle", "vasemmalle"],
            pattern: .hold(seconds: 16),
            keyframes: [
                Pose(),
                Pose(headTurn: 58)
            ]
        ),

        Exercise(
            id: "chin-tuck",
            name: "Leuan sisäänveto",
            region: .neck,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .side,
            highlight: .neck,
            prop: nil,
            cue: "Vedä leukaa suoraan taaksepäin, kuin tekisit kaksoisleuan",
            note: "Katse pysyy vaakatasossa ja liike on pieni. Tunne se kaulan syvissä koukistajissa.",
            sides: nil,
            pattern: .reps(count: 6, hold: 5, release: 3),
            keyframes: [
                // Rest is deliberately the slouched desk posture, so the
                // correction reads as a correction.
                Pose(headNod: 3, headSlide: 0.15, thoracic: -0.15),
                Pose(headNod: 4, headSlide: -0.17, thoracic: 0.20)
            ]
        ),

        Exercise(
            id: "neck-extension",
            name: "Niskan ojennus",
            region: .neck,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .side,
            highlight: .neck,
            prop: nil,
            cue: "Nosta rintakehää ja katso rauhassa ylöspäin",
            note: "Liike lähtee rintarangasta, ei niskan taittamisesta. Lopeta heti jos huimaa tai säteilee käteen.",
            sides: nil,
            pattern: .hold(seconds: 14),
            keyframes: [
                Pose(),
                Pose(headNod: -26, headSlide: -0.04, thoracic: 0.55)
            ]
        ),

        // MARK: - Upper trapezius and levator scapulae

        Exercise(
            id: "trap-stretch-assisted",
            name: "Ylätrapetsin venytys",
            region: .traps,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .front,
            highlight: .traps,
            prop: nil,
            cue: "Taivuta pää sivulle ja vedä kädellä varovasti lisää",
            note: "Vedä vain venytyksen tuntumaan, ei kipuun. Vapaa käsi roikkuu raskaana alhaalla.",
            sides: ["oikealle", "vasemmalle"],
            pattern: .hold(seconds: 26),
            keyframes: [
                // The hand is already on the temple in both keyframes: the
                // anchor case has to stay constant through an exercise.
                Pose(
                    headTilt: 8,
                    left: ArmPose(shoulderLift: -0.10),
                    right: ArmPose(anchor: .headPoint(CGPoint(x: -0.20, y: -0.30)))
                ),
                Pose(
                    headTilt: 33,
                    left: ArmPose(shoulderLift: -0.28),
                    right: ArmPose(anchor: .headPoint(CGPoint(x: -0.20, y: -0.30)))
                )
            ]
        ),

        Exercise(
            id: "levator-stretch",
            name: "Levator scapulae -venytys",
            region: .traps,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .front,
            highlight: .traps,
            prop: nil,
            cue: "Käännä katse sivulle ja laske nenä kohti kainaloa",
            note: "Venytys tuntuu vastakkaisen lapaluun yläkulmassa. Pidä se hartia painettuna alas.",
            sides: ["oikealle", "vasemmalle"],
            pattern: .hold(seconds: 24),
            keyframes: [
                Pose(),
                Pose(headTilt: 8, headTurn: 44, headNod: 30, left: ArmPose(shoulderLift: -0.26))
            ]
        ),

        // MARK: - Shoulders

        Exercise(
            id: "shoulder-rolls",
            name: "Hartioiden pyöritys",
            region: .shoulders,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .front,
            highlight: .shoulders,
            prop: nil,
            cue: "Pyöritä hartioita isolla kaarella taaksepäin",
            note: "Ylös, taakse, alas. Hengitä sisään noston aikana ja ulos kun hartiat laskeutuvat.",
            sides: nil,
            pattern: .cycle(count: 7, period: 3.4),
            keyframes: [
                Pose(),
                Pose(left: ArmPose(shoulderLift: 0.85), right: ArmPose(shoulderLift: 0.85)),
                Pose(
                    scapulaSqueeze: 0.85, chestOpen: 0.35,
                    left: ArmPose(shoulderLift: 0.45), right: ArmPose(shoulderLift: 0.45)
                ),
                Pose(
                    scapulaSqueeze: 0.40,
                    left: ArmPose(shoulderLift: -0.50), right: ArmPose(shoulderLift: -0.50)
                )
            ]
        ),

        Exercise(
            id: "shoulder-shrug-release",
            name: "Hartioiden nosto ja päästö",
            region: .shoulders,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .front,
            highlight: .traps,
            prop: nil,
            cue: "Nosta hartiat korviin, pidä, ja päästä kerralla alas",
            note: "Päästövaihe on tärkein: anna hartioiden pudota omalla painollaan.",
            sides: nil,
            pattern: .reps(count: 5, hold: 5, release: 4),
            keyframes: [
                Pose(),
                Pose(left: ArmPose(shoulderLift: 1.0), right: ArmPose(shoulderLift: 1.0))
            ]
        ),

        // MARK: - Scapulae

        Exercise(
            id: "scapular-squeeze",
            name: "Lapaluiden vetäisy",
            region: .scapulae,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .back,
            highlight: .scapulae,
            prop: nil,
            cue: "Vedä lapaluita yhteen ja alas",
            note: "Kuin puristaisit kynää lapaluiden väliin. Hartiat eivät nouse korviin.",
            sides: nil,
            pattern: .reps(count: 6, hold: 5, release: 3),
            keyframes: [
                Pose(),
                Pose(
                    scapulaSqueeze: 1.0, chestOpen: 0.55,
                    left: ArmPose(abduction: 14, shoulderLift: -0.30),
                    right: ArmPose(abduction: 14, shoulderLift: -0.30)
                )
            ]
        ),

        Exercise(
            id: "wall-angels",
            name: "Seinäliuku",
            region: .scapulae,
            posture: .standing,
            tiers: [.long],
            orientation: .front,
            highlight: .scapulae,
            prop: .wall,
            cue: "Liu'uta käsiä seinää vasten ylös ja alas",
            note: "Ranteet, kyynärpäät ja takaraivo pysyvät kiinni seinässä. Alaselkä ei kaareudu irti.",
            sides: nil,
            pattern: .cycle(count: 6, period: 5.0),
            keyframes: [
                {
                    let goalpost = ArmPose(anchor: .world(CGPoint(x: 1.55, y: -0.62)))
                    let a = both(goalpost)
                    return Pose(scapulaSqueeze: 0.60, chestOpen: 0.45, left: a.left, right: a.right)
                }(),
                {
                    let overhead = ArmPose(anchor: .world(CGPoint(x: 1.28, y: -1.34)))
                    let a = both(overhead)
                    return Pose(scapulaSqueeze: 0.45, chestOpen: 0.35, left: a.left, right: a.right)
                }()
            ]
        ),

        Exercise(
            id: "wy-raise",
            name: "W- ja Y-nostot",
            region: .scapulae,
            posture: .standing,
            tiers: [.long],
            orientation: .back,
            highlight: .scapulae,
            prop: nil,
            cue: "Vuorottele W- ja Y-asentoa",
            note: "W: kyynärpäät alas ja taakse, lapaluut yhteen. Y: kädet ylös vinoon, peukalot taaksepäin.",
            sides: nil,
            pattern: .cycle(count: 6, period: 4.4),
            keyframes: [
                {
                    let w = ArmPose(abduction: 22, elbow: -132, shoulderLift: -0.25)
                    let a = both(w)
                    return Pose(scapulaSqueeze: 1.0, left: a.left, right: a.right)
                }(),
                {
                    let y = ArmPose(abduction: 152, elbow: -14, shoulderLift: -0.10)
                    let a = both(y)
                    return Pose(scapulaSqueeze: 0.55, left: a.left, right: a.right)
                }()
            ]
        ),

        // MARK: - Chest

        Exercise(
            id: "chest-open-seated",
            name: "Rintakehän avaus istuen",
            region: .chest,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .front,
            highlight: .chest,
            prop: nil,
            cue: "Kädet niskan takana, avaa kyynärpäät sivulle",
            note: "Hengitä syvään ja anna rintakehän nousta. Älä vedä päätä käsillä eteen.",
            sides: nil,
            pattern: .hold(seconds: 22),
            keyframes: [
                {
                    // elbowOut low: the elbows point toward the viewer and are
                    // therefore drawn foreshortened.
                    let a = both(ArmPose(anchor: .headBack, elbowOut: 0.30))
                    return Pose(chestOpen: 0.25, thoracic: 0.10, left: a.left, right: a.right)
                }(),
                {
                    let a = both(ArmPose(anchor: .headBack, elbowOut: 1.0))
                    return Pose(
                        scapulaSqueeze: 0.60, chestOpen: 1.0, thoracic: 0.55,
                        left: a.left, right: a.right
                    )
                }()
            ]
        ),

        Exercise(
            id: "doorway-pec",
            name: "Rintakehän avaus ovenkarmissa",
            region: .chest,
            posture: .standing,
            tiers: [.long],
            orientation: .front,
            highlight: .chest,
            prop: .doorway,
            cue: "Kädet ovenkarmiin ja astu rauhassa askel eteen",
            note: "Kyynärpäät hartioiden korkeudella. Venytys tuntuu rintalihaksissa, ei olkanivelen edessä.",
            sides: nil,
            pattern: .hold(seconds: 30),
            keyframes: [
                {
                    let a = both(ArmPose(anchor: .world(CGPoint(x: Body.doorwayHalf, y: -0.58))))
                    return Pose(chestOpen: 0.35, thoracic: 0.15, left: a.left, right: a.right)
                }(),
                {
                    let a = both(ArmPose(anchor: .world(CGPoint(x: Body.doorwayHalf, y: -0.58))))
                    return Pose(
                        scapulaSqueeze: 0.45, chestOpen: 1.0, thoracic: 0.40,
                        left: a.left, right: a.right
                    )
                }()
            ]
        ),

        Exercise(
            id: "hands-behind-back",
            name: "Kädet ristiin selän takana",
            region: .chest,
            posture: .standing,
            tiers: [.long],
            orientation: .front,
            highlight: .chest,
            prop: nil,
            cue: "Kädet ristiin selän takana, ojenna ja laske hartioita",
            note: "Suorista kyynärpäät ja käännä rintakehä ylös. Leuka pysyy sisään vedettynä.",
            sides: nil,
            pattern: .hold(seconds: 26),
            keyframes: [
                {
                    let a = both(ArmPose(
                        abduction: 20, shoulderLift: -0.10, anchor: .lowBack, elbowOut: -1
                    ))
                    return Pose(chestOpen: 0.30, left: a.left, right: a.right)
                }(),
                {
                    let a = both(ArmPose(
                        abduction: 20, shoulderLift: -0.35, anchor: .lowBack, elbowOut: -1
                    ))
                    return Pose(
                        scapulaSqueeze: 0.75, chestOpen: 1.0, thoracic: 0.45,
                        left: a.left, right: a.right
                    )
                }()
            ]
        ),

        // MARK: - Thoracic spine

        Exercise(
            id: "cat-cow-seated",
            name: "Kissa-kameli istuen",
            region: .thoracic,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .side,
            highlight: .thoracic,
            prop: nil,
            cue: "Pyöristä ja ojenna rintarankaa vuorotellen",
            note: "Uloshengityksellä pyöristä selkä, sisäänhengityksellä avaa rintakehä.",
            sides: nil,
            pattern: .cycle(count: 5, period: 5.6),
            keyframes: [
                Pose(headNod: 26, headSlide: 0.12, thoracic: -0.90),
                Pose(headNod: -14, headSlide: -0.05, chestOpen: 0.50, thoracic: 0.90)
            ]
        ),

        Exercise(
            id: "thoracic-rotation",
            name: "Rintarangan kierto",
            region: .thoracic,
            posture: .seated,
            tiers: [.micro, .long],
            orientation: .front,
            highlight: .thoracic,
            prop: nil,
            cue: "Kädet ristiin rinnalle ja kierrä ylävartaloa",
            note: "Lantio ja polvet pysyvät eteenpäin. Kierto lähtee rintarangasta, ei alaselästä.",
            sides: ["oikealle", "vasemmalle"],
            pattern: .hold(seconds: 20),
            keyframes: [
                {
                    let folded = ArmPose(abduction: 18, elbow: 128)
                    let a = both(folded)
                    return Pose(left: a.left, right: a.right)
                }(),
                {
                    let folded = ArmPose(abduction: 18, elbow: 128)
                    let a = both(folded)
                    return Pose(headTurn: 34, torsoTurn: 44, left: a.left, right: a.right)
                }()
            ]
        )
    ]

    static func exercise(id: String) -> Exercise? {
        all.first { $0.id == id }
    }

    static func pool(for tier: Tier, allowStanding: Bool) -> [Exercise] {
        all.filter { $0.tiers.contains(tier) && (allowStanding || $0.posture == .seated) }
    }
}
