import Foundation
import ModelIO
import Testing
@testable import Scan3DCore

/// Relecture minimale d'un STL binaire, pour vérifier ce qu'on a écrit.
private struct STLRelu {
    let entete: Data
    let triangles: [(normale: SIMD3<Float>, sommets: [SIMD3<Float>], attribut: UInt16)]

    init(_ data: Data) throws {
        let octets = [UInt8](data)
        func uint32(_ i: Int) -> UInt32 {
            UInt32(octets[i]) | UInt32(octets[i + 1]) << 8 | UInt32(octets[i + 2]) << 16 | UInt32(octets[i + 3]) << 24
        }
        func float(_ i: Int) -> Float { Float(bitPattern: uint32(i)) }
        func vecteur(_ i: Int) -> SIMD3<Float> { SIMD3(float(i), float(i + 4), float(i + 8)) }

        entete = data.prefix(80)
        let nombre = Int(uint32(80))
        try #require(octets.count == 84 + 50 * nombre)
        triangles = (0..<nombre).map { t in
            let base = 84 + 50 * t
            return (vecteur(base), [vecteur(base + 12), vecteur(base + 24), vecteur(base + 36)],
                    UInt16(octets[base + 48]) | UInt16(octets[base + 49]) << 8)
        }
    }
}

@Suite("Export STL")
struct STLWriterTests {

    @Test("Le facteur de calibrage passe dans le fichier exporté")
    func echelleDeCalibrage() throws {
        let asset = MDLAsset()
        asset.add(MDLMesh(boxWithExtent: [0.05, 0.05, 0.05], segments: [1, 1, 1],
                          inwardNormals: false, geometryType: .triangles, allocator: nil))
        let maillage = try MeshLoader.load(asset: asset)

        let calibre = try STLRelu(try STLWriter.binaryData(for: maillage, scale: 1.02))
        let sommets = calibre.triangles.flatMap(\.sommets)
        // Cube de 50 mm × 1,02 = 51 mm, soit ±25,5 mm autour du centre.
        #expect(abs((sommets.map(\.x).max() ?? 0) - 25.5) < 1e-3)
        #expect(abs((sommets.map(\.y).min() ?? 0) + 25.5) < 1e-3)

        // Sans facteur, le fichier est identique à celui de la tranche 1.
        #expect(try STLWriter.binaryData(for: maillage) == (try STLWriter.binaryData(for: maillage, scale: 1)))
    }

    @Test("Refuse un facteur nul, négatif ou non fini", arguments: [0.0, -1.0, .nan, .infinity])
    func facteurInvalide(echelle: Double) throws {
        let asset = MDLAsset()
        asset.add(MDLMesh(boxWithExtent: [0.05, 0.05, 0.05], segments: [1, 1, 1],
                          inwardNormals: false, geometryType: .triangles, allocator: nil))
        let maillage = try MeshLoader.load(asset: asset)
        #expect(throws: STLError.invalidScale) {
            _ = try STLWriter.binaryData(for: maillage, scale: echelle)
        }
    }

    @Test("Un cube de 0,05 m exporté mesure 50 mm (test obligatoire de la spec)")
    func cubeCinquanteMillimetres() throws {
        let asset = MDLAsset()
        asset.add(MDLMesh(boxWithExtent: [0.05, 0.05, 0.05], segments: [1, 1, 1],
                          inwardNormals: false, geometryType: .triangles, allocator: nil))
        let maillage = try MeshLoader.load(asset: asset)

        let data = try STLWriter.binaryData(for: maillage)
        let stl = try STLRelu(data)

        #expect(data.count == STLWriter.fileSize(triangleCount: 12))
        #expect(data.count == 684)
        #expect(stl.triangles.count == 12)
        let sommets = stl.triangles.flatMap(\.sommets)
        let mini = sommets.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { pointwiseMin($0, $1) }
        let maxi = sommets.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { pointwiseMax($0, $1) }
        // Sommets à ±25 mm : si l'échelle était oubliée, on lirait ±0,025.
        #expect(abs(mini.x + 25) < 1e-3 && abs(maxi.x - 25) < 1e-3)
        #expect(abs((maxi - mini).y - 50) < 1e-3)
        #expect(abs((maxi - mini).z - 50) < 1e-3)
    }

    @Test("Normale selon la règle de la main droite, sommets mis à l'échelle")
    func normaleEtEchelle() throws {
        let maillage = try Mesh(positions: [[0, 0, 0], [0.01, 0, 0], [0, 0.01, 0]], indices: [0, 1, 2])
        let stl = try STLRelu(try STLWriter.binaryData(for: maillage))
        let triangle = try #require(stl.triangles.first)

        #expect(triangle.normale == SIMD3<Float>(0, 0, 1))
        #expect(triangle.sommets == [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0)])
        #expect(triangle.attribut == 0)
    }

    @Test("Un triangle dégénéré reçoit une normale nulle, jamais NaN")
    func triangleDegenere() {
        let normale = STLWriter.normal([0, 0, 0], [1, 1, 1], [2, 2, 2])
        #expect(normale == .zero)
    }

    @Test("Le nombre de triangles est écrit en little-endian juste après l'en-tête")
    func nombreLittleEndian() throws {
        let data = try STLWriter.binaryData(for: try Mesh(positions: MeshTests.sommets, indices: MeshTests.faces))
        #expect([UInt8](data[80..<84]) == [4, 0, 0, 0])
    }

    @Test("En-tête de 80 octets qui ne commence pas par « solid » et annonce les mm")
    func entete() {
        #expect(STLWriter.header.count == 80)
        let texte = String(decoding: STLWriter.header.prefix { $0 != 0 }, as: UTF8.self)
        #expect(!texte.lowercased().hasPrefix("solid"))
        #expect(texte.contains("millimeters"))
    }
}

@Suite("Nom du fichier exporté")
struct ExportFilenameTests {

    @Test("Date et heure lisibles, triables, sans caractère problématique")
    func nomDate() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var composants = DateComponents(year: 2026, month: 9, day: 5, hour: 8, minute: 3, second: 59)
        composants.timeZone = utc
        let date = try #require(Calendar(identifier: .gregorian).date(from: composants))

        let nom = ExportFilename.stl(date: date, timeZone: utc)
        #expect(nom == "Scan3D-2026-09-05-08h03.stl")
        #expect(!nom.contains(":") && !nom.contains("/") && !nom.contains(" "))
    }
}
