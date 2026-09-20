import Foundation
import Testing
import simd
@testable import Scan3DCore

/// Boîte pleine, centrée sur l'origine : l'objet à supporter.
private func boite(_ taille: SIMD3<Float>) throws -> Mesh {
    let h = taille / 2
    var constructeur = MeshBuilder()
    constructeur.addQuad([-h.x, -h.y, h.z], [h.x, -h.y, h.z], [h.x, h.y, h.z], [-h.x, h.y, h.z])
    constructeur.addQuad([h.x, -h.y, -h.z], [-h.x, -h.y, -h.z], [-h.x, h.y, -h.z], [h.x, h.y, -h.z])
    constructeur.addQuad([h.x, -h.y, h.z], [h.x, -h.y, -h.z], [h.x, h.y, -h.z], [h.x, h.y, h.z])
    constructeur.addQuad([-h.x, -h.y, -h.z], [-h.x, -h.y, h.z], [-h.x, h.y, h.z], [-h.x, h.y, -h.z])
    constructeur.addQuad([-h.x, -h.y, -h.z], [h.x, -h.y, -h.z], [h.x, -h.y, h.z], [-h.x, -h.y, h.z])
    constructeur.addQuad([-h.x, h.y, h.z], [h.x, h.y, h.z], [h.x, h.y, -h.z], [-h.x, h.y, -h.z])
    return try constructeur.build()
}

/// Objet d'essai : 60 × 40 mm de face, 20 mm d'épaisseur — un interphone de
/// laboratoire. Pas de grille volontairement grossier : c'est la géométrie
/// qu'on vérifie, pas la finesse du contour.
private let objetEssai = { try! boite([0.06, 0.04, 0.02]) }()
private let pasEssai: Float = 0.0005

@Suite("Support mural")
struct WallMountTests {

    @Test("Toute pièce générée est étanche, orientée dehors et de volume positif",
          arguments: [
            WallMountParameters(),
            WallMountParameters(clearance: 0.0005, margin: 0.005, plateThickness: 0.003, wallHeight: 0.008),
            WallMountParameters(clearance: 0.002, margin: 0.012, plateThickness: 0.006, wallHeight: 0.02),
            WallMountParameters(clearance: 0.001, margin: 0.008, holeDiameter: 0.003, holeSpacing: 0.02),
            WallMountParameters(clearance: 0.0015, margin: 0.01, holeSegments: 48),
          ])
    func invariant(parametres: WallMountParameters) throws {
        let support = try WallMount.generate(for: objetEssai, facing: .plusZ,
                                             parameters: parametres, step: pasEssai)
        // L'invariant de l'étape : un slicer sait quoi faire de cette pièce.
        #expect(support.mesh.isWatertight)
        #expect(support.mesh.openEdgeCount == 0)
        #expect(support.mesh.signedVolume > 0)
        #expect(support.mesh.triangleCount > 100)
    }

    @Test("Le volume de la pièce se déduit des aires de ses contours")
    func volumeCoherent() throws {
        let parametres = WallMountParameters()
        let support = try WallMount.generate(for: objetEssai, facing: .plusZ,
                                             parameters: parametres, step: pasEssai)

        let rayon = parametres.holeDiameter / 2
        let attendu = support.outline.area * parametres.plateThickness
            + (support.outline.area - support.pocket.area) * parametres.wallHeight
            - 2 * Float.pi * rayon * rayon * parametres.plateThickness
        #expect(abs(support.mesh.signedVolume - attendu) / attendu < 0.02)
    }

    @Test("Les cotes suivent les réglages")
    func cotes() throws {
        let parametres = WallMountParameters(clearance: 0.001, margin: 0.008,
                                             plateThickness: 0.004, wallHeight: 0.012)
        let support = try WallMount.generate(for: objetEssai, facing: .plusZ,
                                             parameters: parametres, step: pasEssai)
        let boiteEnglobante = support.mesh.boundingBox

        // Hauteur totale = fond + parois.
        #expect(abs(boiteEnglobante.size.z - 0.016) < 0.0005)
        // Largeur = objet + 2 × (jeu + marge).
        #expect(abs(boiteEnglobante.size.x - (0.06 + 2 * 0.009)) < 0.001)
        #expect(abs(boiteEnglobante.size.y - (0.04 + 2 * 0.009)) < 0.001)
        // La poche est plus petite que l'extérieur, et plus grande que l'objet.
        #expect(support.pocket.area < support.outline.area)
        #expect(support.pocket.area > 0.06 * 0.04)
    }

    @Test("La tranche d'essai est la même pièce, en plus court")
    func trancheDEssai() throws {
        let parametres = WallMountParameters()
        let entier = try WallMount.generate(for: objetEssai, facing: .plusZ,
                                            parameters: parametres, step: pasEssai)
        let tranche = try WallMount.generate(for: objetEssai, facing: .plusZ,
                                             parameters: parametres.testSlice(height: 0.008),
                                             step: pasEssai)

        #expect(tranche.mesh.isWatertight)
        #expect(abs(tranche.height - 0.008) < 1e-6)
        #expect(tranche.mesh.signedVolume < entier.mesh.signedVolume)
        // Même empreinte : c'est bien l'emboîtement qu'on essaie.
        #expect(abs(tranche.pocket.area - entier.pocket.area) < 1e-9)
    }

    @Test("Les six orientations produisent une pièce valide",
          arguments: ProjectionDirection.allCases)
    func toutesLesFaces(direction: ProjectionDirection) throws {
        let support = try WallMount.generate(for: objetEssai, facing: direction,
                                             parameters: .init(), step: pasEssai)
        #expect(support.mesh.isWatertight)
        #expect(support.mesh.signedVolume > 0)
    }

    @Test("Des trous trop gros pour la poche sont refusés, pas rabotés")
    func trousTropGros() {
        let parametres = WallMountParameters(holeDiameter: 0.03, holeSpacing: 0.03)
        #expect(throws: WallMountError.holesDoNotFit) {
            _ = try WallMount.generate(for: objetEssai, facing: .plusZ,
                                       parameters: parametres, step: pasEssai)
        }
    }

    @Test("Des réglages absurdes sont refusés d'entrée", arguments: [
        WallMountParameters(margin: 0),
        WallMountParameters(plateThickness: -0.001),
        WallMountParameters(wallHeight: 0),
        WallMountParameters(holeDiameter: 0),
        WallMountParameters(holeSegments: 3),
    ])
    func reglagesInvalides(parametres: WallMountParameters) {
        #expect(throws: WallMountError.invalidParameters) {
            _ = try WallMount.generate(for: objetEssai, facing: .plusZ,
                                       parameters: parametres, step: pasEssai)
        }
    }

    @Test("Un maillage mis à l'échelle garde sa forme et change de taille")
    func miseALEchelle() throws {
        let grand = try objetEssai.scaled(by: 2)
        #expect(abs(grand.boundingBox.size.x - 0.12) < 1e-6)
        #expect(abs(grand.signedVolume - objetEssai.signedVolume * 8) < 1e-9)
        #expect(throws: MeshError.nonFinitePosition) { _ = try objetEssai.scaled(by: 0) }
    }
}
