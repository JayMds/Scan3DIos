/// Erreurs de lecture ou de validation d'un maillage.
public enum MeshError: Error, Equatable, Sendable {
    /// Aucun sommet ou aucun triangle.
    case empty
    /// Le nombre d'indices n'est pas un multiple de 3.
    case indicesNotTriangles
    /// Un indice désigne un sommet qui n'existe pas.
    case indexOutOfBounds
    /// Une coordonnée vaut NaN ou l'infini.
    case nonFinitePosition
    /// Plus de triangles que le plafond accepté (protection mémoire).
    case tooManyTriangles(Int)
    /// Extension de fichier que Model I/O ne sait pas lire.
    case unsupportedFormat
    /// Fichier absent ou illisible.
    case unreadableFile
    /// Le fichier contient autre chose que des triangles (lignes, points…).
    case unsupportedGeometry
}

/// Boîte englobante alignée sur les axes du modèle, en mètres.
public struct BoundingBox: Equatable, Sendable {
    public let min: SIMD3<Float>
    public let max: SIMD3<Float>

    public var size: SIMD3<Float> { max - min }
}

/// Maillage triangulaire en mètres (unité de RealityKit), validé à la création.
///
/// Toute la géométrie de l'app passe par ce type : dimensions (tranche 1),
/// export STL (tranche 1), mesure et booléens (tranches 2-3). Le valider une
/// fois ici évite de le revérifier partout — et un fichier importé en
/// tranche 3 ne pourra pas faire planter un calcul avec un indice invalide.
public struct Mesh: Equatable, Sendable {
    /// Plafond de sécurité : un scan iPhone fait < 50 k triangles, un scan
    /// Mac haute précision quelques millions au plus. Au-delà, c'est un
    /// fichier piégé ou aberrant (déni de service mémoire, `SECURITY.md`).
    public static let maximumTriangleCount = 2_000_000

    public let positions: [SIMD3<Float>]
    /// Trois indices par triangle, dans `positions`.
    public let indices: [UInt32]
    public let boundingBox: BoundingBox

    public var triangleCount: Int { indices.count / 3 }

    public init(
        positions: [SIMD3<Float>],
        indices: [UInt32],
        maximumTriangleCount: Int = Mesh.maximumTriangleCount
    ) throws(MeshError) {
        guard !positions.isEmpty, !indices.isEmpty else { throw .empty }
        guard indices.count % 3 == 0 else { throw .indicesNotTriangles }
        guard indices.count / 3 <= maximumTriangleCount else {
            throw .tooManyTriangles(indices.count / 3)
        }

        var min = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var max = -min
        for position in positions {
            guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
                throw .nonFinitePosition
            }
            min = pointwiseMin(min, position)
            max = pointwiseMax(max, position)
        }

        let nombreSommets = positions.count
        guard indices.allSatisfy({ Int($0) < nombreSommets }) else { throw .indexOutOfBounds }

        self.positions = positions
        self.indices = indices
        self.boundingBox = BoundingBox(min: min, max: max)
    }
}
