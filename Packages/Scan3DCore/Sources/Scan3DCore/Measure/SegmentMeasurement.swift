import simd

/// Distance entre deux points posés sur le modèle.
///
/// La boîte englobante donne l'encombrement ; cette mesure-ci donne la cote
/// utile : l'épaisseur d'un bord, l'entraxe de deux trous de fixation. Les
/// points viennent du même maillage que les cotes et l'export (décision E3).
public struct SegmentMeasurement: Equatable, Sendable {
    public let start: SIMD3<Float>
    public let end: SIMD3<Float>

    public init(start: SIMD3<Float>, end: SIMD3<Float>) {
        self.start = start
        self.end = end
    }

    /// En mètres (l'unité du maillage).
    public var lengthMeters: Double {
        Double(simd_distance(start, end))
    }

    /// En millimètres, l'unité affichée et exportée. Le calibrage du scan
    /// s'appliquera ici à l'étape 3.
    public var lengthMM: Double {
        Units.millimeters(fromMeters: lengthMeters)
    }

    /// Milieu du segment : où poser l'étiquette ou le trait dans la scène 3D.
    public var midpoint: SIMD3<Float> {
        (start + end) / 2
    }
}
