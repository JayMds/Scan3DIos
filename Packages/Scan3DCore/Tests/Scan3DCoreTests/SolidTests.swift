import Foundation
import Testing
import simd
@testable import Scan3DCore

private func rectangle(x: Float, y: Float, largeur: Float, hauteur: Float) -> Polygon {
    Polygon(points: [[x, y], [x + largeur, y], [x + largeur, y + hauteur], [x, y + hauteur]])!
}

private func cercle(rayon: Float, centre: SIMD2<Float> = .zero, segments: Int = 32) -> Polygon {
    Polygon(points: (0..<segments).map { index in
        let angle = 2 * Float.pi * Float(index) / Float(segments)
        return centre + SIMD2(cos(angle), sin(angle)) * rayon
    })!
}

@Suite("Triangulation")
struct PolygonTriangulatorTests {

    @Test("Un carré donne deux triangles, et la bonne aire")
    func carre() throws {
        let decoupe = try PolygonTriangulator.triangulate(rectangle(x: 0, y: 0, largeur: 0.04, hauteur: 0.03))
        #expect(decoupe.triangleCount == 2)
        #expect(abs(decoupe.area - 0.0012) < 1e-9)
    }

    @Test("Une forme concave ne perd ni ne double de matière")
    func formeEnL() throws {
        // L de 40 × 40 mm, branche de 15 mm.
        let forme = Polygon(points: [
            [0, 0], [0.04, 0], [0.04, 0.015], [0.015, 0.015], [0.015, 0.04], [0, 0.04],
        ])!
        let decoupe = try PolygonTriangulator.triangulate(forme)
        #expect(decoupe.triangleCount == 4)
        #expect(abs(decoupe.area - forme.area) < 1e-9)
    }

    @Test("Un trou carré est retranché, pas recouvert")
    func trouCarre() throws {
        let exterieur = rectangle(x: 0, y: 0, largeur: 0.04, hauteur: 0.04)
        let trou = rectangle(x: 0.015, y: 0.015, largeur: 0.01, hauteur: 0.01)
        let decoupe = try PolygonTriangulator.triangulate(exterieur, holes: [trou])

        #expect(abs(decoupe.area - (exterieur.area - trou.area)) < 1e-9)
        // Tous les triangles tournent dans le même sens : aucun retourné.
        for debut in stride(from: 0, to: decoupe.indices.count, by: 3) {
            let a = decoupe.points[Int(decoupe.indices[debut])]
            let b = decoupe.points[Int(decoupe.indices[debut + 1])]
            let c = decoupe.points[Int(decoupe.indices[debut + 2])]
            #expect((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y) > 0)
        }
    }

    @Test("Deux trous ronds, comme les vis d'une plaque")
    func deuxTrousRonds() throws {
        let plaque = rectangle(x: -0.05, y: -0.04, largeur: 0.1, hauteur: 0.08)
        let vis = [cercle(rayon: 0.00225, centre: [0, 0.025]), cercle(rayon: 0.00225, centre: [0, -0.025])]
        let decoupe = try PolygonTriangulator.triangulate(plaque, holes: vis)

        let attendue = plaque.area - vis.reduce(0) { $0 + $1.area }
        // Tolérance **relative** : une aire de 8000 mm² accumulée sur une
        // centaine de triangles en `Float` ne tient pas le milliardième absolu.
        #expect(abs(decoupe.area - attendue) < attendue * 1e-5)
    }

    @Test("Un trou hors du contour est refusé")
    func trouDehors() {
        let plaque = rectangle(x: 0, y: 0, largeur: 0.02, hauteur: 0.02)
        #expect(throws: TriangulationError.holeOutside) {
            _ = try PolygonTriangulator.triangulate(plaque, holes: [cercle(rayon: 0.002, centre: [0.1, 0.1])])
        }
    }

    @Test("Les points alignés en trop ne font pas de triangles plats")
    func pointsAlignes() throws {
        let forme = Polygon(points: [
            [0, 0], [0.01, 0], [0.02, 0], [0.03, 0], [0.03, 0.02], [0.015, 0.02], [0, 0.02],
        ])!
        let decoupe = try PolygonTriangulator.triangulate(forme)
        #expect(abs(decoupe.area - 0.0006) < 1e-9)
        for debut in stride(from: 0, to: decoupe.indices.count, by: 3) {
            let a = decoupe.points[Int(decoupe.indices[debut])]
            let b = decoupe.points[Int(decoupe.indices[debut + 1])]
            let c = decoupe.points[Int(decoupe.indices[debut + 2])]
            #expect(abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) > 1e-11)
        }
    }
}

@Suite("Assemblage de solides")
struct MeshBuilderTests {
    /// Cube de 20 mm construit face par face, normales vers l'extérieur.
    static func cube(cote: Float = 0.02, sansLeDessus: Bool = false) -> MeshBuilder {
        let h = cote / 2
        var constructeur = MeshBuilder()
        constructeur.addQuad([-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h])       // +Z
        constructeur.addQuad([h, -h, -h], [-h, -h, -h], [-h, h, -h], [h, h, -h])   // −Z
        constructeur.addQuad([h, -h, h], [h, -h, -h], [h, h, -h], [h, h, h])       // +X
        constructeur.addQuad([-h, -h, -h], [-h, -h, h], [-h, h, h], [-h, h, -h])   // −X
        constructeur.addQuad([-h, -h, -h], [h, -h, -h], [h, -h, h], [-h, -h, h])   // −Y
        if !sansLeDessus {
            constructeur.addQuad([-h, h, h], [h, h, h], [h, h, -h], [-h, h, -h])   // +Y
        }
        return constructeur
    }

    @Test("Un cube assemblé est étanche, orienté dehors, et fait le bon volume")
    func cubeEtanche() throws {
        let maillage = try Self.cube().build()
        #expect(maillage.isWatertight)
        #expect(maillage.openEdgeCount == 0)
        #expect(abs(maillage.signedVolume - 8e-6) < 1e-12)   // 20 mm au cube
        #expect(maillage.triangleCount == 12)                 // les sommets sont soudés
        #expect(maillage.positions.count == 8)
    }

    @Test("Une face manquante se voit : quatre arêtes ouvertes")
    func faceManquante() throws {
        let maillage = try Self.cube(sansLeDessus: true).build()
        #expect(!maillage.isWatertight)
        #expect(maillage.openEdgeCount == 4)
    }

    @Test("Un cube retourné a un volume négatif")
    func cubeRetourne() throws {
        let normal = try Self.cube().build()
        var inverse = MeshBuilder()
        for debut in stride(from: 0, to: normal.indices.count, by: 3) {
            inverse.add(normal.positions[Int(normal.indices[debut])],
                        normal.positions[Int(normal.indices[debut + 2])],
                        normal.positions[Int(normal.indices[debut + 1])])
        }
        let retourne = try inverse.build()
        #expect(retourne.isWatertight)
        #expect(retourne.signedVolume < 0)
    }

    @Test("Les triangles plats et les doublons sont écartés")
    func trianglesPlats() throws {
        var constructeur = Self.cube()
        let avant = constructeur.triangleCount
        constructeur.add([0, 0, 0], [0, 0, 0], [0.01, 0, 0])          // deux sommets confondus
        constructeur.add([0, 0, 0], [0.01, 0, 0], [0.02, 0, 0])       // alignés
        #expect(constructeur.triangleCount == avant)
    }

    @Test("Une triangulation posée à plat garde son aire, et sa normale suit le plan")
    func posePlate() throws {
        let plan = ProjectionPlane(.plusY)
        let decoupe = try PolygonTriangulator.triangulate(rectangle(x: -0.01, y: -0.01, largeur: 0.02, hauteur: 0.02))
        var constructeur = MeshBuilder()
        constructeur.add(decoupe, on: plan, depth: 0.005)
        let maillage = try constructeur.build()

        #expect(maillage.triangleCount == 2)
        // Tous les sommets à la même hauteur le long de la normale.
        for sommet in maillage.positions {
            #expect(abs(simd_dot(sommet, plan.normal) - 0.005) < 1e-6)
        }
    }
}
