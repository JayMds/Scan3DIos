import simd

/// Triangles d'un contour, en 2D : les points, puis trois indices par triangle.
public struct Triangulation: Equatable, Sendable {
    public let points: [SIMD2<Float>]
    public let indices: [UInt32]

    public var triangleCount: Int { indices.count / 3 }

    /// Somme des aires : elle doit valoir celle du contour, trous déduits.
    /// C'est l'invariant qui attrape les recouvrements comme les manques.
    public var area: Float {
        var somme: Float = 0
        for debut in stride(from: 0, to: indices.count, by: 3) {
            let a = points[Int(indices[debut])]
            let b = points[Int(indices[debut + 1])]
            let c = points[Int(indices[debut + 2])]
            somme += ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
        }
        return somme
    }
}

public enum TriangulationError: Error, Equatable, Sendable {
    /// Moins de trois points exploitables.
    case degenerate
    /// Un trou n'est pas à l'intérieur du contour.
    case holeOutside
    /// Aucune oreille trouvée : contour auto-intersecté.
    case failed
}

/// Découpe un contour — avec ses trous — en triangles.
///
/// Méthode des **oreilles** : on coupe une à une les pointes convexes qui ne
/// contiennent aucun autre sommet. Les trous sont d'abord reliés au contour
/// extérieur par un « pont » : deux sommets dupliqués qui transforment un
/// contour troué en contour simple. C'est la brique qui permet la face avant
/// d'une pièce — un rectangle moins la poche, moins les trous de vis.
public enum PolygonTriangulator {
    /// En dessous, un triangle est plat : on le supprime sans l'émettre.
    private static let aireNegligeable: Float = 1e-11

    public static func triangulate(
        _ outer: Polygon, holes: [Polygon] = []
    ) throws(TriangulationError) -> Triangulation {
        var points = outer.oriented(counterClockwise: true).points
        var boucle = Array(points.indices)

        // Les trous les plus à droite en premier : leur pont ne traversera pas
        // un trou encore à relier.
        let tries = holes.sorted { ($0.boundingBox.max.x) > ($1.boundingBox.max.x) }
        for trou in tries {
            let sommets = trou.oriented(counterClockwise: false).points
            guard sommets.count >= 3 else { throw .degenerate }
            let base = points.count
            points += sommets
            boucle = try relier(boucle, Array(base..<(base + sommets.count)), points)
        }

        guard boucle.count >= 3 else { throw .degenerate }
        return Triangulation(points: points, indices: try couper(boucle, points))
    }

    // MARK: Ponts vers les trous

    /// Reliure d'un trou au contour : on part de son sommet le plus à droite,
    /// on tire un rayon horizontal, et on rejoint le sommet visible du contour.
    private static func relier(
        _ contour: [Int], _ trou: [Int], _ points: [SIMD2<Float>]
    ) throws(TriangulationError) -> [Int] {
        guard let indexM = trou.max(by: { points[$0].x < points[$1].x }) else { throw .degenerate }
        let m = points[indexM]

        var meilleureAbscisse = Float.greatestFiniteMagnitude
        var candidat: Int?
        for position in contour.indices {
            let a = points[contour[position]]
            let b = points[contour[(position + 1) % contour.count]]
            guard (a.y > m.y) != (b.y > m.y) else { continue }
            let abscisse = a.x + (m.y - a.y) / (b.y - a.y) * (b.x - a.x)
            guard abscisse >= m.x, abscisse < meilleureAbscisse else { continue }
            meilleureAbscisse = abscisse
            candidat = a.x > b.x ? contour[position] : contour[(position + 1) % contour.count]
        }
        guard var pont = candidat else { throw .holeOutside }

        // Affinage : si un sommet rentrant du contour se trouve dans le triangle
        // (M, point d'impact, pont), c'est lui qu'il faut viser — sinon le pont
        // traverserait la matière.
        let impact = SIMD2(meilleureAbscisse, m.y)
        var meilleurCosinus = -Float.greatestFiniteMagnitude
        for index in contour where index != pont {
            let p = points[index]
            guard p.x > m.x, dansTriangle(p, m, impact, points[pont]) else { continue }
            let direction = p - m
            let cosinus = direction.x / max(simd_length(direction), 1e-12)
            if cosinus > meilleurCosinus {
                meilleurCosinus = cosinus
                pont = index
            }
        }

        guard let positionPont = contour.firstIndex(of: pont),
              let positionM = trou.firstIndex(of: indexM) else { throw .failed }

        var reliee = Array(contour[0...positionPont])
        reliee += trou[positionM...]
        reliee += trou[..<positionM]
        reliee.append(indexM)
        reliee.append(pont)
        reliee += contour[(positionPont + 1)...]
        return reliee
    }

    // MARK: Oreilles

    private static func couper(
        _ boucle: [Int], _ points: [SIMD2<Float>]
    ) throws(TriangulationError) -> [UInt32] {
        var restants = boucle
        var triangles: [UInt32] = []

        while restants.count > 3 {
            var coupee = false
            for position in restants.indices {
                let nombre = restants.count
                let ia = restants[(position + nombre - 1) % nombre]
                let ib = restants[position]
                let ic = restants[(position + 1) % nombre]
                let aire = croise(points[ia], points[ib], points[ic])

                if abs(aire) <= aireNegligeable {
                    // Sommet plat ou en épingle : on l'enlève sans produire de
                    // triangle dégénéré, qui ferait échouer l'impression.
                    restants.remove(at: position)
                    coupee = true
                    break
                }
                guard aire > 0, estOreille(ia, ib, ic, restants, points) else { continue }

                triangles += [UInt32(ia), UInt32(ib), UInt32(ic)]
                restants.remove(at: position)
                coupee = true
                break
            }
            guard coupee else { throw .failed }
        }

        guard restants.count == 3 else { throw .degenerate }
        if abs(croise(points[restants[0]], points[restants[1]], points[restants[2]])) > aireNegligeable {
            triangles += restants.map(UInt32.init)
        }
        guard !triangles.isEmpty else { throw .degenerate }
        return triangles
    }

    /// Une oreille : une pointe convexe dont le triangle ne contient aucun
    /// autre sommet du contour.
    private static func estOreille(
        _ ia: Int, _ ib: Int, _ ic: Int, _ restants: [Int], _ points: [SIMD2<Float>]
    ) -> Bool {
        let a = points[ia], b = points[ib], c = points[ic]
        for index in restants where index != ia && index != ib && index != ic {
            if dansTriangle(points[index], a, b, c) { return false }
        }
        return true
    }

    private static func croise(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
        (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
    }

    /// Strictement à l'intérieur (les sommets partagés ne comptent pas).
    private static func dansTriangle(
        _ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>
    ) -> Bool {
        let d1 = croise(a, b, p), d2 = croise(b, c, p), d3 = croise(c, a, p)
        let negatif = d1 < 0 || d2 < 0 || d3 < 0
        let positif = d1 > 0 || d2 > 0 || d3 > 0
        return !(negatif && positif)
    }
}
