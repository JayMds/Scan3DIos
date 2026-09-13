import Scan3DCore

/// Textes du sélecteur de mode (écran de préparation).
extension CaptureMode {
    var titre: String {
        switch self {
        case .orbit: "Autour de l'objet"
        case .turntable: "Plateau tournant"
        }
    }

    var explication: String {
        switch self {
        case .orbit:
            "Vous tournez autour de l'objet, l'iPhone prend les photos tout seul."
        case .turntable:
            "L'iPhone reste posé, vous tournez le plateau d'environ \(Self.turntableDegreesPerShot)° entre deux photos (\(Self.turntableShotsPerTurn) par tour)."
        }
    }
}
