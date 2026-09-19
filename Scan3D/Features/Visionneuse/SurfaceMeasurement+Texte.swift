import Scan3DCore

/// Libellés de ce que la mesure **veut dire**. Ils vivent dans l'app, comme
/// les textes des conseils de capture : `Scan3DCore` décide de la géométrie,
/// l'app décide des mots.
extension SurfaceMeasurement.Kind {
    /// Affiché sous la distance : « 50,2 mm d'épaisseur » n'est pas la même
    /// affirmation que « 50,2 mm entre deux points ».
    var titre: String {
        switch self {
        case .thickness: "Épaisseur entre deux faces"
        case .pointToFace: "D'un point à une face"
        case .pointToPoint: "Entre deux points"
        }
    }

    /// Phrase pour VoiceOver, au moment où la mesure s'affiche.
    var phrase: String {
        switch self {
        case .thickness: "Épaisseur entre deux faces"
        case .pointToFace: "Distance d'un point à une face"
        case .pointToPoint: "Distance entre deux points"
        }
    }
}

extension MeasurementTarget {
    /// « Face A posée », « Point B posé » — l'accord change, et il dit à
    /// l'utilisateur ce que l'app a reconnu sous son doigt.
    func poseAnnoncee(repere: String) -> String {
        switch self {
        case .point: "Point \(repere) posé"
        case .face: "Face \(repere) posée"
        }
    }
}
