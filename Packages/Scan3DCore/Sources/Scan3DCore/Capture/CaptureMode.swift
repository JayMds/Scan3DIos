/// Comment les photos sont prises.
///
/// - `orbit` : l'iPhone tourne autour de l'objet ; RealityKit déclenche les
///   photos tout seul quand l'appareil change de position.
/// - `turntable` : l'objet tourne sur un plateau, l'iPhone est fixe. RealityKit
///   ne verrait jamais l'appareil bouger, donc c'est l'utilisateur qui
///   déclenche chaque photo. Géométriquement, un objet qui tourne devant une
///   caméra fixe équivaut à une caméra qui orbite — à condition que le fond
///   soit uni (il est fixe, lui) et que la lumière soit diffuse.
///
/// Cas non documenté par Apple : à valider par la qualité des reconstructions.
public enum CaptureMode: String, CaseIterable, Sendable, Identifiable {
    case orbit
    case turntable

    public var id: String { rawValue }

    /// La capture automatique de RealityKit se base sur le mouvement de
    /// l'iPhone : inutile s'il est posé.
    public var usesAutomaticCapture: Bool {
        switch self {
        case .orbit: true
        case .turntable: false
        }
    }

    /// Le checkpoint contient les poses ARKit de chaque photo. Avec un iPhone
    /// immobile elles sont toutes identiques : la reconstruction doit repartir
    /// des images seules.
    public var usesCheckpoint: Bool {
        switch self {
        case .orbit: true
        case .turntable: false
        }
    }

    // MARK: Plateau tournant

    /// Objectif par tour complet : une photo tous les 10°, assez de
    /// recouvrement entre deux vues consécutives pour la photogrammétrie.
    public static let turntableShotsPerTurn = 36
    public static let turntableDegreesPerShot = 360 / turntableShotsPerTurn
    /// En dessous, un tour n'apporte presque rien : le bouton « Tour terminé »
    /// reste désactivé.
    public static let turntableMinimumShotsPerTurn = 12

    /// Remplissage du tour courant, borné à 1 (on peut dépasser l'objectif).
    public static func turntableTurnProgress(shotsThisTurn: Int) -> Double {
        min(1, max(0, Double(shotsThisTurn) / Double(turntableShotsPerTurn)))
    }
}
