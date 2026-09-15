import Foundation
import simd

public enum STLError: Error, Equatable, Sendable {
    /// Le nombre de triangles ne tient pas sur 32 bits (limite du format).
    case tooManyTriangles
}

/// Écrit un maillage au format STL **binaire**, en **millimètres**.
///
/// - Binaire : ~6 fois plus compact que l'ASCII (2,5 Mo au lieu de ~14 Mo pour
///   50 k triangles) et lu par tous les slicers.
/// - Millimètres : le STL ne porte aucune unité, les slicers supposent le mm.
///   Les positions de `Mesh` sont en mètres → × `Units.metersToMillimeters`.
///   Oublier cette ligne donne la pièce 1000 fois trop petite.
///
/// Structure, en little-endian :
/// ```
/// 80 octets   en-tête libre — ne doit PAS commencer par « solid » (marque de l'ASCII)
/// UInt32      nombre de triangles
/// × n         normale (3 Float32) · 3 sommets (9 Float32) · attribut UInt16 = 0
/// ```
public enum STLWriter {
    public static let headerSize = 80
    public static let triangleRecordSize = 50

    public static func fileSize(triangleCount: Int) -> Int {
        headerSize + MemoryLayout<UInt32>.size + triangleRecordSize * triangleCount
    }

    public static func binaryData(for mesh: Mesh) throws(STLError) -> Data {
        guard let nombre = UInt32(exactly: mesh.triangleCount) else { throw .tooManyTriangles }

        var data = Data(capacity: fileSize(triangleCount: mesh.triangleCount))
        data.append(header)
        append(nombre, to: &data)

        let echelle = Float(Units.metersToMillimeters)
        for debut in stride(from: 0, to: mesh.indices.count, by: 3) {
            // Indices garantis valides par `Mesh` : pas de vérification à refaire ici.
            let a = mesh.positions[Int(mesh.indices[debut])] * echelle
            let b = mesh.positions[Int(mesh.indices[debut + 1])] * echelle
            let c = mesh.positions[Int(mesh.indices[debut + 2])] * echelle
            append(normal(a, b, c), to: &data)
            append(a, to: &data)
            append(b, to: &data)
            append(c, to: &data)
            append(UInt16(0), to: &data)
        }
        return data
    }

    /// Normale unitaire selon la règle de la main droite (sommets dans le sens
    /// trigonométrique vus de l'extérieur). Triangle dégénéré → vecteur nul :
    /// les slicers recalculent alors la normale, alors qu'un NaN les ferait échouer.
    static func normal(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let produit = cross(b - a, c - a)
        let longueur = length(produit)
        guard longueur > 0, longueur.isFinite else { return .zero }
        return produit / longueur
    }

    /// En-tête lisible dans un éditeur hexadécimal, sans aucune donnée personnelle.
    static let header: Data = {
        var octets = Array("Scan3D binary STL - units: millimeters".utf8.prefix(headerSize))
        octets += Array(repeating: 0, count: headerSize - octets.count)
        return Data(octets)
    }()

    private static func append(_ valeur: UInt32, to data: inout Data) {
        withUnsafeBytes(of: valeur.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ valeur: UInt16, to data: inout Data) {
        withUnsafeBytes(of: valeur.littleEndian) { data.append(contentsOf: $0) }
    }

    /// Composante par composante : un `SIMD3<Float>` occupe 16 octets en
    /// mémoire (alignement), le format en attend 12.
    private static func append(_ vecteur: SIMD3<Float>, to data: inout Data) {
        append(vecteur.x.bitPattern, to: &data)
        append(vecteur.y.bitPattern, to: &data)
        append(vecteur.z.bitPattern, to: &data)
    }
}
