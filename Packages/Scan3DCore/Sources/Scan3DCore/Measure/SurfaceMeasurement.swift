import simd

/// Ce que l'utilisateur a désigné d'un toucher : un point, ou une face.
public enum MeasurementTarget: Equatable, Sendable {
    /// Un point visé sur la surface (la surface n'était pas plane ici).
    case point(SIMD3<Float>)
    /// Une face ajustée, et le point visé **projeté sur son plan**.
    case face(PlaneFit, anchor: SIMD3<Float>)

    /// Le point à afficher et à relier.
    public var position: SIMD3<Float> {
        switch self {
        case .point(let position): position
        case .face(_, let anchor): anchor
        }
    }

    public var plane: PlaneFit? {
        switch self {
        case .point: nil
        case .face(let plan, _): plan
        }
    }
}

/// Une mesure entre deux désignations, avec **ce qu'elle veut dire**.
///
/// Trois cas bien définis, choisis par la géométrie et jamais par un réglage :
/// une épaisseur n'a de sens qu'entre deux faces parallèles, une distance
/// point-plan est toujours définie, et deux points donnent une simple distance.
/// L'écran affiche le libellé correspondant : « 50,2 mm d'épaisseur » n'est pas
/// la même affirmation que « 50,2 mm entre deux points ».
public struct SurfaceMeasurement: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Entre deux faces parallèles : la mesure du pied à coulisse.
        case thickness
        /// D'un point à une face.
        case pointToFace
        /// Entre deux points (dernier recours, ou faces non parallèles).
        case pointToPoint
    }

    /// En deçà, deux plans parallèles sont **le même plan** : toucher deux fois
    /// la même face doit mesurer la distance entre les deux touchers, pas
    /// annoncer une épaisseur nulle.
    public static let coplanarEpsilon: Float = 0.0002

    public let kind: Kind
    /// Le segment effectivement mesuré (extrémités affichables).
    public let segment: SegmentMeasurement

    public init(from a: MeasurementTarget, to b: MeasurementTarget, parallelToleranceDegrees: Float = 10) {
        switch (a, b) {
        case (.face(let planA, let ancreA), .face(let planB, _))
            where planA.isParallel(to: planB, toleranceDegrees: parallelToleranceDegrees)
                && abs(planB.distance(to: ancreA))
                    > max(Self.coplanarEpsilon, planA.residual + planB.residual):
            // Épaisseur : la perpendiculaire entre les deux plans, tracée depuis
            // le point touché sur la première face. Sa longueur ne dépend **pas**
            // de l'endroit touché sur l'une ou l'autre face — c'est tout l'intérêt.
            kind = .thickness
            segment = SegmentMeasurement(start: ancreA, end: planB.projection(of: ancreA))

        case (.face(let plan, _), .point(let position)), (.point(let position), .face(let plan, _)):
            // Distance d'un point à un plan : toujours définie, perpendiculaire.
            kind = .pointToFace
            segment = SegmentMeasurement(start: position, end: plan.projection(of: position))

        default:
            // Deux points, ou deux faces qui ne sont pas parallèles : entre
            // elles, « épaisseur » ne voudrait rien dire.
            kind = .pointToPoint
            segment = SegmentMeasurement(start: a.position, end: b.position)
        }
    }

    /// Longueur brute, en millimètres.
    public var lengthMM: Double { segment.lengthMM }

    /// Longueur corrigée par le calibrage du scan.
    public func lengthMM(calibratedBy calibration: ScaleCalibration?) -> Double {
        segment.lengthMM(calibratedBy: calibration)
    }
}
