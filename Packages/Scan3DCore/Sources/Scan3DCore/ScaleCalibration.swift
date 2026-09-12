/// Erreurs de calibrage, exposées à l'UI pour afficher un message clair.
public enum CalibrationError: Error, Equatable, Sendable {
    /// Une des mesures est nulle, négative, infinie ou NaN.
    case invalidMeasurement
    /// Le facteur calculé sort de la plage plausible : c'est presque toujours
    /// une erreur de saisie (cm au lieu de mm, mauvaise cote) plutôt qu'un
    /// vrai défaut d'échelle du scan.
    case implausibleFactor(Double)
}

/// Facteur de correction d'échelle calculé à partir d'une cote connue.
///
/// Principe : le scan donne la *forme*, la mesure physique (pied à coulisse
/// ou objet de référence) donne la *vérité*. Si le scan mesure 84,0 mm là où
/// le pied à coulisse lit 85,6 mm, on multiplie tout le modèle par 85,6 / 84,0.
public struct ScaleCalibration: Equatable, Sendable {
    /// Écart maximal accepté par rapport à l'échelle d'origine (±20 %).
    /// Le LiDAR se trompe de quelques pourcents, jamais de 20 %.
    public static let plausibleRange: ClosedRange<Double> = 0.8...1.2

    public let factor: Double

    /// - Parameters:
    ///   - measuredMM: la cote relevée sur le modèle scanné, en mm.
    ///   - actualMM: la cote réelle, en mm.
    public init(measuredMM: Double, actualMM: Double) throws(CalibrationError) {
        // Validation stricte des entrées : ces valeurs viennent d'un champ
        // saisi par l'utilisateur, on ne leur fait jamais confiance.
        guard measuredMM.isFinite, actualMM.isFinite,
              measuredMM > 0, actualMM > 0 else {
            throw .invalidMeasurement
        }
        let candidate = actualMM / measuredMM
        guard Self.plausibleRange.contains(candidate) else {
            throw .implausibleFactor(candidate)
        }
        factor = candidate
    }

    /// Applique la correction à une longueur exprimée en mm.
    public func apply(toMM value: Double) -> Double {
        value * factor
    }
}
