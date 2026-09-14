import Foundation
import ModelIO

/// Lit un fichier 3D (USDZ produit par la reconstruction, mais aussi USDA,
/// USDC, OBJ…) et le fusionne en un seul `Mesh`, en mètres.
///
/// Comportements de Model I/O vérifiés par l'expérience (14/09/2026) :
/// - les transformations des nœuds parents ne sont PAS appliquées aux
///   sommets : on les compose nous-mêmes (`globalTransform`) ;
/// - les métadonnées USD `metersPerUnit` et `upAxis` sont ignorées : les
///   valeurs sont brutes. RealityKit écrit en mètres, axe Y vertical ;
/// - le pas entre deux sommets (`stride`) varie selon le fichier (12 ou 32
///   octets constatés) : il faut toujours le lire, jamais le supposer.
public enum MeshLoader {

    public static func load(contentsOf url: URL) throws(MeshError) -> Mesh {
        guard MDLAsset.canImportFileExtension(url.pathExtension) else { throw .unsupportedFormat }
        guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
            throw .unreadableFile
        }
        // Cet initialiseur n'est pas importé en `throws` (il renvoie un objet
        // non optionnel) : l'erreur arrive par pointeur, comme en Objective-C.
        var erreur: NSError?
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: nil,
                             preserveTopology: false, error: &erreur)
        guard erreur == nil else { throw .unreadableFile }
        return try load(asset: asset)
    }

    /// Interne : les tests construisent des assets en mémoire. Garder Model I/O
    /// hors de l'API publique évite à l'app d'en dépendre.
    static func load(asset: MDLAsset) throws(MeshError) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for objet in asset.childObjects(of: MDLMesh.self) {
            guard let maillage = objet as? MDLMesh else { continue }
            // Les indices de ce maillage se décalent du nombre de sommets déjà lus.
            guard let decalage = UInt32(exactly: positions.count) else { throw .tooManyTriangles(indices.count / 3) }
            let global = MDLTransform.globalTransform(with: maillage, atTime: 0)
            try lirePositions(de: maillage, transformation: global, dans: &positions)
            try lireIndices(de: maillage, decalage: decalage, nombreSommets: maillage.vertexCount, dans: &indices)
            // Arrêt précoce : ne pas lire des millions de triangles pour les refuser ensuite.
            guard indices.count / 3 <= Mesh.maximumTriangleCount else {
                throw .tooManyTriangles(indices.count / 3)
            }
        }
        return try Mesh(positions: positions, indices: indices)
    }

    private static func lirePositions(
        de maillage: MDLMesh,
        transformation: simd_float4x4,
        dans positions: inout [SIMD3<Float>]
    ) throws(MeshError) {
        let nombre = maillage.vertexCount
        guard nombre > 0 else { return }
        guard let donnees = maillage.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else {
            throw .unreadableFile
        }
        // `donnees` garde le tampon « mappé » en mémoire : il doit vivre
        // pendant toute la lecture de `dataStart`.
        try withExtendedLifetime(donnees) { () throws(MeshError) in
            let tailleSommet = 3 * MemoryLayout<Float>.size
            // Borne de lecture : un fichier incohérent ne doit jamais nous
            // faire lire hors du tampon.
            guard donnees.stride >= tailleSommet,
                  (nombre - 1) * donnees.stride + tailleSommet <= donnees.bufferSize else {
                throw .unreadableFile
            }
            positions.reserveCapacity(positions.count + nombre)
            for i in 0..<nombre {
                let debut = i * donnees.stride
                let local = SIMD4<Float>(
                    donnees.dataStart.loadUnaligned(fromByteOffset: debut, as: Float.self),
                    donnees.dataStart.loadUnaligned(fromByteOffset: debut + 4, as: Float.self),
                    donnees.dataStart.loadUnaligned(fromByteOffset: debut + 8, as: Float.self),
                    1
                )
                let monde = transformation * local
                positions.append(SIMD3(monde.x, monde.y, monde.z))
            }
        }
    }

    private static func lireIndices(
        de maillage: MDLMesh,
        decalage: UInt32,
        nombreSommets: Int,
        dans indices: inout [UInt32]
    ) throws(MeshError) {
        for sousMaillage in maillage.submeshes as? [MDLSubmesh] ?? [] {
            guard sousMaillage.geometryType == .triangles else { throw .unsupportedGeometry }
            let nombre = sousMaillage.indexCount
            guard nombre > 0 else { continue }
            let tampon = sousMaillage.indexBuffer(asIndexType: .uInt32)
            let carte = tampon.map()
            try withExtendedLifetime(carte) { () throws(MeshError) in
                guard nombre * MemoryLayout<UInt32>.size <= tampon.length else { throw .unreadableFile }
                indices.reserveCapacity(indices.count + nombre)
                for i in 0..<nombre {
                    let local = carte.bytes.loadUnaligned(fromByteOffset: i * MemoryLayout<UInt32>.size, as: UInt32.self)
                    // Vérifié ici (et non seulement dans `Mesh`) : le décalage
                    // ne doit jamais faire déborder un indice invalide.
                    guard Int(local) < nombreSommets else { throw .indexOutOfBounds }
                    indices.append(local + decalage)
                }
            }
        }
    }
}
