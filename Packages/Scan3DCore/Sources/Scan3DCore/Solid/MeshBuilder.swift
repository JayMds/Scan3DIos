import simd

/// Assemble un maillage triangle par triangle, en **soudant** les sommets
/// identiques.
///
/// La soudure n'est pas un détail d'optimisation : sans elle, chaque triangle
/// aurait ses propres sommets, aucune arête ne serait partagée, et le contrôle
/// d'étanchéité — celui qui garantit une pièce imprimable — n'aurait plus rien
/// à mesurer.
public struct MeshBuilder {
    /// Deux sommets distants de moins d'un micron sont le même sommet.
    public static let weldUnit: Float = 1_000_000

    private var positions: [SIMD3<Float>] = []
    private var indices: [UInt32] = []
    private var connus: [SIMD3<Int32>: UInt32] = [:]

    public init() {}

    public var triangleCount: Int { indices.count / 3 }

    /// Ajoute un triangle ; ignore silencieusement les triangles plats, qui
    /// n'apportent rien et gênent les slicers.
    public mutating func add(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let ia = souder(a), ib = souder(b), ic = souder(c)
        guard ia != ib, ib != ic, ic != ia else { return }
        guard simd_length(simd_cross(b - a, c - a)) > 1e-12 else { return }
        indices += [ia, ib, ic]
    }

    /// Quadrilatère plan, coupé en deux triangles (a, b, c, d dans l'ordre).
    public mutating func addQuad(
        _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>
    ) {
        add(a, b, c)
        add(a, c, d)
    }

    /// Pose une triangulation 2D à plat, à la hauteur demandée le long de la
    /// normale du plan. `flipped` retourne les triangles : une face du dessous
    /// doit regarder vers le bas.
    public mutating func add(
        _ triangulation: Triangulation, on plane: ProjectionPlane, depth: Float, flipped: Bool = false
    ) {
        for debut in stride(from: 0, to: triangulation.indices.count, by: 3) {
            let a = plane.unproject(triangulation.points[Int(triangulation.indices[debut])], depth: depth)
            let b = plane.unproject(triangulation.points[Int(triangulation.indices[debut + 1])], depth: depth)
            let c = plane.unproject(triangulation.points[Int(triangulation.indices[debut + 2])], depth: depth)
            if flipped { add(a, c, b) } else { add(a, b, c) }
        }
    }

    /// Paroi verticale le long d'un contour, entre deux hauteurs. `outward`
    /// dit de quel côté regardent les normales : vers l'extérieur du contour
    /// (une paroi extérieure) ou vers l'intérieur (une poche, un trou).
    public mutating func addWall(
        _ polygon: Polygon, on plane: ProjectionPlane,
        from bas: Float, to haut: Float, outward: Bool
    ) {
        let contour = polygon.oriented(counterClockwise: true).points
        for index in contour.indices {
            let a = contour[index]
            let b = contour[(index + 1) % contour.count]
            let basA = plane.unproject(a, depth: bas), basB = plane.unproject(b, depth: bas)
            let hautA = plane.unproject(a, depth: haut), hautB = plane.unproject(b, depth: haut)
            if outward {
                addQuad(basA, basB, hautB, hautA)
            } else {
                addQuad(basA, hautA, hautB, basB)
            }
        }
    }

    public func build() throws(MeshError) -> Mesh {
        try Mesh(positions: positions, indices: indices)
    }

    private mutating func souder(_ point: SIMD3<Float>) -> UInt32 {
        let cle = SIMD3<Int32>(
            Int32((point.x * Self.weldUnit).rounded()),
            Int32((point.y * Self.weldUnit).rounded()),
            Int32((point.z * Self.weldUnit).rounded())
        )
        if let connu = connus[cle] { return connu }
        let index = UInt32(positions.count)
        positions.append(point)
        connus[cle] = index
        return index
    }
}

extension Mesh {
    /// Volume signé, par le théorème de la divergence. Positif quand les
    /// normales sortent — donc négatif si la pièce est retournée à l'envers.
    public var signedVolume: Float {
        var somme: Float = 0
        for debut in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[debut])]
            let b = positions[Int(indices[debut + 1])]
            let c = positions[Int(indices[debut + 2])]
            somme += simd_dot(a, simd_cross(b, c))
        }
        return somme / 6
    }

    /// Arêtes qui ne sont pas partagées par exactement deux triangles en sens
    /// opposés : ce sont les trous du maillage.
    public var openEdgeCount: Int {
        var comptes: [SIMD2<UInt32>: Int] = [:]
        for debut in stride(from: 0, to: indices.count, by: 3) {
            for decalage in 0..<3 {
                let a = indices[debut + decalage]
                let b = indices[debut + (decalage + 1) % 3]
                let cle = SIMD2(min(a, b), max(a, b))
                comptes[cle, default: 0] += a < b ? 1 : -1
            }
        }
        return comptes.values.count { $0 != 0 }
    }

    /// Une pièce **étanche** : chaque arête est partagée par deux triangles
    /// orientés en sens inverse. C'est la condition qu'un slicer exige pour
    /// savoir ce qui est plein et ce qui est vide.
    public var isWatertight: Bool { openEdgeCount == 0 }
}
