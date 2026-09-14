import Foundation
import ModelIO
import Testing
@testable import Scan3DCore

@Suite("Maillage")
struct MeshTests {
    /// Tétraèdre de 10 × 20 × 30 cm.
    static let sommets: [SIMD3<Float>] = [[0, 0, 0], [0.1, 0, 0], [0, 0.2, 0], [0, 0, 0.3]]
    static let faces: [UInt32] = [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]

    @Test("Un maillage valide expose ses triangles et sa boîte englobante")
    func valide() throws {
        let maillage = try Mesh(positions: Self.sommets, indices: Self.faces)
        #expect(maillage.triangleCount == 4)
        #expect(maillage.boundingBox.min == SIMD3<Float>(0, 0, 0))
        #expect(maillage.boundingBox.size == SIMD3<Float>(0.1, 0.2, 0.3))
    }

    @Test("Refuse un maillage vide")
    func vide() {
        #expect(throws: MeshError.empty) { _ = try Mesh(positions: [], indices: Self.faces) }
        #expect(throws: MeshError.empty) { _ = try Mesh(positions: Self.sommets, indices: []) }
    }

    @Test("Refuse des indices qui ne forment pas des triangles")
    func pasDesTriangles() {
        #expect(throws: MeshError.indicesNotTriangles) {
            _ = try Mesh(positions: Self.sommets, indices: [0, 1, 2, 3])
        }
    }

    @Test("Refuse un indice qui désigne un sommet inexistant")
    func indiceHorsBornes() {
        #expect(throws: MeshError.indexOutOfBounds) {
            _ = try Mesh(positions: Self.sommets, indices: [0, 1, 4])
        }
    }

    @Test("Refuse une coordonnée non finie")
    func coordonneeNonFinie() {
        #expect(throws: MeshError.nonFinitePosition) {
            _ = try Mesh(positions: [[0, 0, 0], [.nan, 0, 0], [0, 1, 0]], indices: [0, 1, 2])
        }
    }

    @Test("Refuse un maillage au-delà du plafond de triangles")
    func plafond() {
        #expect(throws: MeshError.tooManyTriangles(4)) {
            _ = try Mesh(positions: Self.sommets, indices: Self.faces, maximumTriangleCount: 3)
        }
    }
}

@Suite("Lecture de fichiers 3D")
struct MeshLoaderTests {
    /// Cube de 5 cm fabriqué par Model I/O, comme celui qu'on imprimerait pour étalonner.
    static func cube(cote: Float = 0.05) -> MDLMesh {
        MDLMesh(boxWithExtent: [cote, cote, cote], segments: [1, 1, 1],
                inwardNormals: false, geometryType: .triangles, allocator: nil)
    }

    @Test("Un cube de 0,05 m mesure 50 mm sur les trois axes")
    func cubeEnMemoire() throws {
        let asset = MDLAsset()
        asset.add(Self.cube())
        let maillage = try MeshLoader.load(asset: asset)
        let dimensions = Dimensions(boundingBox: maillage.boundingBox)

        #expect(maillage.triangleCount == 12)
        #expect(abs(dimensions.lengthMM - 50) < 1e-3)
        #expect(abs(dimensions.widthMM - 50) < 1e-3)
        #expect(abs(dimensions.heightMM - 50) < 1e-3)
    }

    @Test("Les transformations des nœuds parents sont appliquées aux sommets")
    func transformationParente() throws {
        let parent = MDLObject()
        parent.transform = MDLTransform(matrix: simd_float4x4(diagonal: [2, 2, 2, 1]))
        parent.addChild(Self.cube())
        let asset = MDLAsset()
        asset.add(parent)

        let dimensions = Dimensions(boundingBox: try MeshLoader.load(asset: asset).boundingBox)
        #expect(abs(dimensions.heightMM - 100) < 1e-3)
    }

    @Test("Plusieurs maillages sont fusionnés sans mélanger leurs indices")
    func fusion() throws {
        let asset = MDLAsset()
        asset.add(Self.cube())
        let decale = MDLObject()
        decale.transform = MDLTransform(matrix: simd_float4x4(
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0.2, 0, 0, 1]
        ))
        decale.addChild(Self.cube())
        asset.add(decale)

        let maillage = try MeshLoader.load(asset: asset)
        #expect(maillage.triangleCount == 24)
        // De -0,025 à 0,225 m sur X : 250 mm.
        #expect(abs(Dimensions(boundingBox: maillage.boundingBox).lengthMM - 250) < 1e-3)
    }

    @Test("Aller-retour par un vrai fichier USD : les cotes sont conservées")
    func allerRetourUSD() throws {
        let asset = MDLAsset()
        asset.add(Self.cube())
        let fichier = FileManager.default.temporaryDirectory
            .appending(path: "scan3d-test-\(UUID().uuidString).usda")
        defer { try? FileManager.default.removeItem(at: fichier) }
        try asset.export(to: fichier)

        let maillage = try MeshLoader.load(contentsOf: fichier)
        #expect(abs(Dimensions(boundingBox: maillage.boundingBox).heightMM - 50) < 1e-3)
    }

    @Test("Refuse un fichier absent")
    func fichierAbsent() {
        let absent = FileManager.default.temporaryDirectory.appending(path: "absent-\(UUID().uuidString).usdz")
        #expect(throws: MeshError.unreadableFile) { _ = try MeshLoader.load(contentsOf: absent) }
    }

    @Test("Refuse un format que Model I/O ne sait pas lire")
    func formatInconnu() {
        #expect(throws: MeshError.unsupportedFormat) {
            _ = try MeshLoader.load(contentsOf: URL(filePath: "/tmp/modele.docx"))
        }
    }
}
