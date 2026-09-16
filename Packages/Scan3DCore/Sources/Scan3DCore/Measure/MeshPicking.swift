import simd

/// Point touché sur un maillage.
public struct MeshHit: Equatable, Sendable {
    /// En mètres, dans le repère du maillage.
    public let point: SIMD3<Float>
    /// Rang du triangle touché (utile au diagnostic et aux tests).
    public let triangleIndex: Int
    /// Distance depuis l'œil, en mètres, le long du rayon.
    public let distance: Float
}

extension Mesh {
    /// Sous le seuil, le rayon est parallèle au triangle (ou le triangle est
    /// dégénéré) : la division deviendrait un infini. Les triangles d'un scan
    /// font quelques millimètres, leur déterminant reste très au-dessus.
    private static let parallelEpsilon: Float = 1e-12
    /// 1 µm : un contact « derrière l'œil » ou pile dessus n'est pas un contact.
    private static let minimumDistance: Float = 1e-6

    /// Premier point où le rayon rencontre la surface, ou `nil` s'il passe à côté.
    ///
    /// Algorithme de **Möller-Trumbore** : pour chaque triangle, on exprime le
    /// point d'impact en coordonnées barycentriques (u, v) et en distance (t)
    /// le long du rayon, avec une seule division. On garde le t positif le plus
    /// petit : la face visible, pas celle de derrière.
    ///
    /// Les deux faces du triangle comptent (`abs(det)`) : un scan a parfois des
    /// triangles retournés ou des trous par lesquels on voit l'intérieur, et
    /// l'utilisateur, lui, voit une surface — il doit pouvoir la mesurer.
    ///
    /// Force brute sur tous les triangles : ~50 000 pour un scan d'iPhone,
    /// soit quelques millisecondes. Une structure accélératrice (BVH) ne
    /// deviendrait utile qu'avec les maillages du Mac (tranche 4).
    public func firstIntersection(with ray: Ray) -> MeshHit? {
        var meilleureDistance = Float.infinity
        var meilleurTriangle = -1

        // Accès non vérifiés : `Mesh.init` a déjà garanti que chaque indice
        // désigne un sommet existant et que leur nombre est un multiple de 3.
        positions.withUnsafeBufferPointer { sommets in
            indices.withUnsafeBufferPointer { faces in
                var position = 0
                while position < faces.count {
                    let a = sommets[Int(faces[position])]
                    let b = sommets[Int(faces[position + 1])]
                    let c = sommets[Int(faces[position + 2])]

                    let ab = b - a
                    let ac = c - a
                    let p = simd_cross(ray.direction, ac)
                    let determinant = simd_dot(ab, p)
                    if abs(determinant) > Self.parallelEpsilon {
                        let inverse = 1 / determinant
                        let versOrigine = ray.origin - a
                        let u = simd_dot(versOrigine, p) * inverse
                        if u >= 0, u <= 1 {
                            let q = simd_cross(versOrigine, ab)
                            let v = simd_dot(ray.direction, q) * inverse
                            if v >= 0, u + v <= 1 {
                                let t = simd_dot(ac, q) * inverse
                                if t > Self.minimumDistance, t < meilleureDistance {
                                    meilleureDistance = t
                                    meilleurTriangle = position / 3
                                }
                            }
                        }
                    }
                    position += 3
                }
            }
        }

        guard meilleurTriangle >= 0 else { return nil }
        return MeshHit(
            point: ray.point(at: meilleureDistance),
            triangleIndex: meilleurTriangle,
            distance: meilleureDistance
        )
    }
}
