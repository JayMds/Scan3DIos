import simd

/// Géométrie élémentaire d'un triangle. Isolée ici parce qu'elle resservira :
/// l'ajustement de plan s'en sert pour décider quels triangles sont « autour »
/// du point touché, et la génération de pièces en aura besoin à son tour.
enum TriangleGeometry {
    /// Point du triangle le plus proche de `p` (algorithme de Christer Ericson,
    /// *Real-Time Collision Detection*) : on teste successivement les trois
    /// sommets, les trois arêtes, puis l'intérieur.
    ///
    /// Pourquoi pas simplement la distance au centre du triangle ? Parce qu'un
    /// maillage mélange des triangles minuscules et des triangles de plusieurs
    /// centimètres : juger par leur centre exclurait une grande face dont on
    /// touche le bord.
    static func closestPoint(
        on a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, to p: SIMD3<Float>
    ) -> SIMD3<Float> {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0, d2 <= 0 { return a }

        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0, d4 <= d3 { return b }

        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 {
            return a + ab * (d1 / (d1 - d3))
        }

        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0, d5 <= d6 { return c }

        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 {
            return a + ac * (d2 / (d2 - d6))
        }

        let va = d3 * d6 - d5 * d4
        if va <= 0, (d4 - d3) >= 0, (d5 - d6) >= 0 {
            return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
        }

        let denominateur = 1 / (va + vb + vc)
        return a + ab * (vb * denominateur) + ac * (vc * denominateur)
    }
}
