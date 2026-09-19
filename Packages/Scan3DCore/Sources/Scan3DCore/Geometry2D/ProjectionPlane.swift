import simd

/// Direction vers laquelle « regarde » la projection : la face de l'objet qui
/// s'appuiera contre le mur est celle qui lui tourne le dos.
public enum ProjectionDirection: String, CaseIterable, Identifiable, Sendable {
    case plusX, minusX, plusY, minusY, plusZ, minusZ

    public var id: String { rawValue }

    /// Normale sortante du plan de projection, dans le repère du maillage.
    public var normal: SIMD3<Float> {
        switch self {
        case .plusX: [1, 0, 0]
        case .minusX: [-1, 0, 0]
        case .plusY: [0, 1, 0]
        case .minusY: [0, -1, 0]
        case .plusZ: [0, 0, 1]
        case .minusZ: [0, 0, -1]
        }
    }
}

/// Passage entre l'espace du maillage (mètres, Y vertical) et le plan 2D dans
/// lequel on calcule la silhouette.
///
/// Les deux axes du plan sont choisis pour que le repère (u, v, normale) reste
/// **direct** : sans cette précaution, une silhouette serait le miroir de
/// l'objet, et la pièce générée ne s'emboîterait que dans son reflet.
public struct ProjectionPlane: Equatable, Sendable {
    public let direction: ProjectionDirection
    public let u: SIMD3<Float>
    public let v: SIMD3<Float>

    public var normal: SIMD3<Float> { direction.normal }

    public init(_ direction: ProjectionDirection) {
        self.direction = direction
        switch direction {
        case .plusZ: (u, v) = ([1, 0, 0], [0, 1, 0])
        case .minusZ: (u, v) = ([-1, 0, 0], [0, 1, 0])
        case .plusY: (u, v) = ([0, 0, 1], [1, 0, 0])
        case .minusY: (u, v) = ([1, 0, 0], [0, 0, 1])
        case .plusX: (u, v) = ([0, 1, 0], [0, 0, 1])
        case .minusX: (u, v) = ([0, 0, 1], [0, 1, 0])
        }
    }

    /// Coordonnées dans le plan.
    public func project(_ point: SIMD3<Float>) -> SIMD2<Float> {
        SIMD2(simd_dot(point, u), simd_dot(point, v))
    }

    /// Profondeur le long de la normale : positive du côté de l'observateur.
    public func depth(of point: SIMD3<Float>) -> Float {
        simd_dot(point, normal)
    }

    /// Retour dans l'espace du maillage, à la profondeur demandée.
    public func unproject(_ point: SIMD2<Float>, depth: Float) -> SIMD3<Float> {
        u * point.x + v * point.y + normal * depth
    }
}
