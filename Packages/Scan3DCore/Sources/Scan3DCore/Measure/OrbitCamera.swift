import simd

/// Caméra qui tourne autour d'un objet, comme une main qui fait pivoter une
/// pièce devant soi : une cible, un angle horizontal (azimut), un angle
/// vertical (élévation), une distance.
///
/// Pourquoi ici, et pas dans RealityKit ? Parce que le **rayon** de mesure en
/// dépend : c'est la même caméra qui affiche le modèle et qui transforme le
/// toucher en droite dans l'espace. En la gardant dans `Scan3DCore`, cette
/// transformation se teste sur Mac, sans iPhone ni écran — et l'app se
/// contente de recopier la pose dans un `PerspectiveCamera`.
///
/// Convention : Y est la verticale (celle de RealityKit). Azimut 0 et
/// élévation 0 placent l'œil sur l'axe +Z, face à l'objet.
public struct OrbitCamera: Equatable, Sendable {
    /// On s'arrête avant la verticale exacte : au pôle, la notion de « haut »
    /// de l'image n'existe plus et l'image tournerait sur elle-même.
    public static let elevationLimit: Float = .pi / 2 - 0.08

    /// Centre de l'orbite (centre de la boîte englobante du modèle).
    public let target: SIMD3<Float>
    /// Champ de vision **vertical**, comme celui réglé sur la caméra RealityKit.
    public let fieldOfViewDegrees: Float
    public let distanceRange: ClosedRange<Float>
    public private(set) var azimuth: Float
    public private(set) var elevation: Float
    public private(set) var distance: Float

    public init(
        target: SIMD3<Float>,
        distance: Float,
        distanceRange: ClosedRange<Float>,
        azimuth: Float = 0,
        elevation: Float = 0,
        fieldOfViewDegrees: Float = 60
    ) {
        self.target = target
        self.distanceRange = distanceRange
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.azimuth = azimuth
        self.elevation = min(max(elevation, -Self.elevationLimit), Self.elevationLimit)
        self.distance = min(max(distance, distanceRange.lowerBound), distanceRange.upperBound)
    }

    /// Cadre un objet : cible au centre de sa boîte englobante, distance
    /// choisie pour qu'il tienne en entier à l'écran. Vue de trois quarts
    /// légèrement en plongée, qui donne tout de suite le relief.
    public init(framing box: BoundingBox, aspectRatio: Float = 0.5, fieldOfViewDegrees: Float = 60) {
        let rayon = max(simd_length(box.size) / 2, 0.001)
        let cadrage = Self.framingDistance(
            radius: rayon, aspectRatio: aspectRatio, fieldOfViewDegrees: fieldOfViewDegrees
        )
        self.init(
            target: (box.min + box.max) / 2,
            distance: cadrage,
            distanceRange: max(0.02, rayon * 0.5)...(cadrage * 8),
            azimuth: .pi / 5,
            elevation: .pi / 9,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }

    /// Distance à laquelle une sphère de rayon `radius` tient dans l'image.
    ///
    /// En portrait, c'est la **largeur** qui limite : le champ horizontal se
    /// déduit du vertical par le rapport d'aspect, et on garde le plus étroit
    /// des deux. 8 % de marge pour ne pas coller aux bords.
    public static func framingDistance(radius: Float, aspectRatio: Float, fieldOfViewDegrees: Float) -> Float {
        let vertical = fieldOfViewDegrees * .pi / 180
        let horizontal = 2 * atan(tan(vertical / 2) * max(aspectRatio, 0.05))
        return radius / sin(min(vertical, horizontal) / 2) * 1.08
    }

    /// Position de l'œil.
    public var position: SIMD3<Float> {
        let cosElevation = cos(elevation)
        return target + distance * SIMD3(
            cosElevation * sin(azimuth),
            sin(elevation),
            cosElevation * cos(azimuth)
        )
    }

    /// Repère de l'image : vers où l'on regarde, la droite de l'écran, le haut.
    public var basis: (forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>) {
        let forward = simd_normalize(target - position)
        // L'élévation étant bornée, `forward` n'est jamais colinéaire à la
        // verticale : le produit vectoriel ne peut pas s'annuler.
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        return (forward, right, simd_cross(right, forward))
    }

    // MARK: Manipulation

    /// Fait tourner la caméra autour de la cible (angles en radians, relatifs).
    public mutating func turn(azimuth deltaAzimut: Float, elevation deltaElevation: Float) {
        guard deltaAzimut.isFinite, deltaElevation.isFinite else { return }
        azimuth = (azimuth + deltaAzimut).truncatingRemainder(dividingBy: 2 * .pi)
        elevation = min(max(elevation + deltaElevation, -Self.elevationLimit), Self.elevationLimit)
    }

    /// `facteur` > 1 rapproche (pincement d'écartement), < 1 éloigne.
    public mutating func zoom(by facteur: Float) {
        guard facteur.isFinite, facteur > 0 else { return }
        distance = min(max(distance / facteur, distanceRange.lowerBound), distanceRange.upperBound)
    }

    /// Recadre l'objet pour la forme réelle de l'écran, une fois connue.
    public mutating func frame(radius: Float, aspectRatio: Float) {
        let cadrage = Self.framingDistance(
            radius: radius, aspectRatio: aspectRatio, fieldOfViewDegrees: fieldOfViewDegrees
        )
        distance = min(max(cadrage, distanceRange.lowerBound), distanceRange.upperBound)
    }

    // MARK: Écran ↔ espace 3D

    /// Rayon partant de l'œil et passant par un point de l'écran.
    /// Origine du repère écran : coin haut-gauche, en points (comme SwiftUI).
    public func ray(throughViewPoint point: SIMD2<Float>, viewSize: SIMD2<Float>) -> Ray? {
        guard viewSize.x > 0, viewSize.y > 0, point.x.isFinite, point.y.isFinite else { return nil }
        // Coordonnées normalisées : -1 à gauche/en bas, +1 à droite/en haut.
        let ndc = SIMD2(2 * point.x / viewSize.x - 1, 1 - 2 * point.y / viewSize.y)
        let tangente = tan(fieldOfViewDegrees * .pi / 180 / 2)
        let repere = basis
        let direction = repere.forward
            + repere.right * (ndc.x * tangente * viewSize.x / viewSize.y)
            + repere.up * (ndc.y * tangente)
        return Ray(origin: position, direction: direction)
    }

    /// L'inverse : où se projette un point de l'espace sur l'écran. `nil` s'il
    /// est derrière l'œil. Sert surtout à vérifier le cadrage dans les tests.
    public func project(_ point: SIMD3<Float>, viewSize: SIMD2<Float>) -> SIMD2<Float>? {
        guard viewSize.x > 0, viewSize.y > 0 else { return nil }
        let repere = basis
        let versPoint = point - position
        let profondeur = simd_dot(versPoint, repere.forward)
        guard profondeur > 1e-6 else { return nil }
        let tangente = tan(fieldOfViewDegrees * .pi / 180 / 2)
        let ndc = SIMD2(
            simd_dot(versPoint, repere.right) / (profondeur * tangente * viewSize.x / viewSize.y),
            simd_dot(versPoint, repere.up) / (profondeur * tangente)
        )
        return SIMD2((ndc.x + 1) / 2 * viewSize.x, (1 - ndc.y) / 2 * viewSize.y)
    }
}
