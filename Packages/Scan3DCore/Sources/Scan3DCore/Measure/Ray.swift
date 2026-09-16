import simd

/// Demi-droite dans l'espace du modèle (mètres) : un œil et une direction.
///
/// C'est le pont entre le doigt de l'utilisateur et la géométrie : la caméra
/// transforme un point de l'écran en rayon (`OrbitCamera.ray(throughViewPoint:)`),
/// le maillage dit où ce rayon touche l'objet (`Mesh.firstIntersection(with:)`).
public struct Ray: Equatable, Sendable {
    public let origin: SIMD3<Float>
    /// Toujours de longueur 1 : les distances renvoyées sont donc des mètres.
    public let direction: SIMD3<Float>

    /// `init?` : une direction nulle ou non finie ne décrit aucun rayon. Plutôt
    /// que de propager des NaN dans toute la géométrie, on refuse à l'entrée.
    public init?(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let longueur = simd_length(direction)
        guard longueur.isFinite, longueur > 0,
              origin.x.isFinite, origin.y.isFinite, origin.z.isFinite else { return nil }
        self.origin = origin
        self.direction = direction / longueur
    }

    /// Point situé à `distance` mètres de l'œil, le long du rayon.
    public func point(at distance: Float) -> SIMD3<Float> {
        origin + direction * distance
    }
}
