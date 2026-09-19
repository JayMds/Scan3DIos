import Foundation
import ModelIO
import Testing
import simd
@testable import Scan3DCore

/// Cube de 50 mm centré sur l'origine, **subdivisé** : un scan réel n'a pas
/// deux triangles par face, il en a des centaines.
private func cubeFin(cote: Float = 0.05, divisions: UInt32 = 8) throws -> Mesh {
    let asset = MDLAsset()
    asset.add(MDLMesh(boxWithExtent: [cote, cote, cote],
                      segments: [divisions, divisions, divisions],
                      inwardNormals: false, geometryType: .triangles, allocator: nil))
    return try MeshLoader.load(asset: asset)
}

@Suite("Ajustement de plan")
struct PlaneFitTests {

    @Test("Au centre d'une face : normale exacte, surface parfaitement plane")
    func faceDuCube() throws {
        let cube = try cubeFin()
        let ajustement = try #require(cube.fitPlane(around: [0, 0, 0.025], radius: 0.008))

        #expect(simd_distance(ajustement.normal, SIMD3<Float>(0, 0, 1)) < 1e-5)
        #expect(ajustement.residual < 1e-6)
        #expect(abs(ajustement.point.z - 0.025) < 1e-6)
        #expect(ajustement.triangleCount >= Mesh.minimumPlaneTriangles)
    }

    @Test("Sur une arête ou un coin, l'ajustement est refusé")
    func pliRefuse() throws {
        let cube = try cubeFin()
        // Arête : deux faces à 90°, les normales s'annulent à moitié.
        #expect(cube.fitPlane(around: [0, 0.025, 0.025], radius: 0.008) == nil)
        // Coin : trois faces.
        #expect(cube.fitPlane(around: [0.025, 0.025, 0.025], radius: 0.008) == nil)
    }

    @Test("Loin de toute surface, rien à ajuster")
    func dansLeVide() throws {
        let cube = try cubeFin()
        #expect(cube.fitPlane(around: [0.2, 0.2, 0.2], radius: 0.008) == nil)
    }

    @Test("Une surface courbe est refusée dès que le plan mentirait")
    func surfaceCourbe() throws {
        let asset = MDLAsset()
        asset.add(MDLMesh(sphereWithExtent: [0.04, 0.04, 0.04], segments: [48, 48],
                          inwardNormals: false, geometryType: .triangles, allocator: nil))
        let sphere = try MeshLoader.load(asset: asset)

        // Rayon 8 mm sur une sphère de 20 mm de rayon : la flèche atteint
        // ~1,6 mm, bien au-delà de la platitude tolérée.
        #expect(sphere.fitPlane(around: [0, 0, 0.02], radius: 0.008) == nil)
    }

    @Test("Près d'une arête, un rayon plus court sauve la mesure")
    func rayonDegressif() throws {
        let cube = try cubeFin()
        // À 4 mm de l'arête : le rayon large déborde sur la face voisine…
        let pres: SIMD3<Float> = [0.021, 0, 0.025]
        #expect(cube.fitPlane(around: pres, radius: 0.008) == nil)
        // …mais la recherche dégressive trouve un plan plus modeste.
        let trouve = try #require(cube.fitPlane(around: pres, searchingRadii: [0.008, 0.004, 0.002]))
        #expect(simd_distance(trouve.normal, SIMD3<Float>(0, 0, 1)) < 1e-5)
        #expect(trouve.radius < 0.008)
    }

    @Test("Le rayon d'ajustement suit la taille de l'objet")
    func rayonProportionne() throws {
        let petit = try cubeFin(cote: 0.05)
        let grand = try cubeFin(cote: 0.5)
        #expect(abs(petit.planeFitRadius - 0.003) < 1e-6)   // plancher de 3 mm
        #expect(abs(grand.planeFitRadius - 0.02) < 1e-6)    // 4 % de 50 cm
    }

    @Test("Les points du plan sont à distance nulle, les autres à leur distance signée")
    func distancesSignees() throws {
        let cube = try cubeFin()
        let ajustement = try #require(cube.fitPlane(around: [0, 0, 0.025], radius: 0.008))

        #expect(abs(ajustement.distance(to: ajustement.point)) < 1e-6)
        #expect(abs(ajustement.distance(to: [0.01, -0.01, 0.025])) < 1e-6)
        #expect(abs(ajustement.distance(to: [0, 0, 0.035]) - 0.01) < 1e-6)
        #expect(abs(ajustement.distance(to: [0, 0, 0.015]) + 0.01) < 1e-6)

        let projete = ajustement.projection(of: [0.01, 0.01, 0.04])
        #expect(abs(projete.z - 0.025) < 1e-6)
        #expect(abs(projete.x - 0.01) < 1e-6)
    }

    @Test("Deux faces opposées sont parallèles, deux faces voisines ne le sont pas")
    func parallelisme() throws {
        let cube = try cubeFin()
        let devant = try #require(cube.fitPlane(around: [0, 0, 0.025], radius: 0.008))
        let derriere = try #require(cube.fitPlane(around: [0, 0, -0.025], radius: 0.008))
        let dessus = try #require(cube.fitPlane(around: [0, 0.025, 0], radius: 0.008))

        #expect(devant.isParallel(to: derriere))
        #expect(!devant.isParallel(to: dessus))
    }
}

@Suite("Mesure de surface à surface")
struct SurfaceMeasurementTests {

    /// Ajuste une face du cube à l'endroit demandé et renvoie la cible
    /// correspondante, ancre comprise.
    private func face(_ cube: Mesh, en point: SIMD3<Float>) throws -> MeasurementTarget {
        let ajustement = try #require(cube.fitPlane(around: point, radius: 0.008))
        return .face(ajustement, anchor: ajustement.projection(of: point))
    }

    @Test("L'épaisseur du cube vaut 50 mm, quel que soit l'endroit touché")
    func epaisseurIndependanteDeLaVisee() throws {
        let cube = try cubeFin()

        // Trois couples de points très différents sur les deux faces opposées.
        // Tous à plus d'un rayon (8 mm) des arêtes : au-delà, l'ajustement
        // refuse, et c'est voulu.
        let couples: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0, 0, 0.025], [0, 0, -0.025]),
            ([0.012, -0.010, 0.025], [-0.014, 0.011, -0.025]),
            ([-0.015, 0.015, 0.025], [0.015, -0.015, -0.025]),
        ]

        for (devant, derriere) in couples {
            let mesure = SurfaceMeasurement(from: try face(cube, en: devant), to: try face(cube, en: derriere))
            #expect(mesure.kind == .thickness)
            // C'est **le** test de l'étape : la dispersion de visée a disparu.
            #expect(abs(mesure.lengthMM - 50) < 0.01)
        }
    }

    @Test("Deux touchers sur la même face mesurent la distance qui les sépare")
    func memeFace() throws {
        let cube = try cubeFin()
        let mesure = SurfaceMeasurement(
            from: try face(cube, en: [-0.015, -0.015, 0.025]),
            to: try face(cube, en: [0.015, 0.015, 0.025])
        )
        // Deux plans confondus : « épaisseur nulle » n'aurait aucun sens.
        #expect(mesure.kind == .pointToPoint)
        #expect(abs(mesure.lengthMM - 42.43) < 0.1)   // diagonale de 30 × 30 mm
    }

    @Test("Entre deux faces voisines, une épaisseur n'aurait pas de sens")
    func facesNonParalleles() throws {
        let cube = try cubeFin()
        let mesure = SurfaceMeasurement(
            from: try face(cube, en: [0, 0, 0.025]),
            to: try face(cube, en: [0, 0.025, 0])
        )
        #expect(mesure.kind == .pointToPoint)
    }

    @Test("D'un point à une face, la mesure est la perpendiculaire")
    func pointVersFace() throws {
        let cube = try cubeFin()
        let dessus = try face(cube, en: [0, 0.025, 0])
        let point = MeasurementTarget.point([0.02, -0.025, 0.02])

        let mesure = SurfaceMeasurement(from: point, to: dessus)
        #expect(mesure.kind == .pointToFace)
        #expect(abs(mesure.lengthMM - 50) < 0.01)

        // L'ordre des deux touchers ne change rien.
        #expect(SurfaceMeasurement(from: dessus, to: point).kind == .pointToFace)
    }

    @Test("Deux points restent une simple distance")
    func pointVersPoint() {
        let mesure = SurfaceMeasurement(from: .point([0, 0, 0]), to: .point([0.1, 0, 0]))
        #expect(mesure.kind == .pointToPoint)
        #expect(abs(mesure.lengthMM - 100) < 1e-3)
    }

    @Test("Le calibrage s'applique à toutes les mesures")
    func calibrage() throws {
        let cube = try cubeFin()
        let mesure = SurfaceMeasurement(
            from: try face(cube, en: [0, 0, 0.025]),
            to: try face(cube, en: [0, 0, -0.025])
        )
        let calibration = try ScaleCalibration(measuredMM: 50, actualMM: 51)
        #expect(abs(mesure.lengthMM(calibratedBy: calibration) - 51) < 0.02)
        #expect(mesure.lengthMM(calibratedBy: nil) == mesure.lengthMM)
    }
}
