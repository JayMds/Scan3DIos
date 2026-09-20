import Foundation
import Testing
import simd
@testable import Scan3DCore

/// Maillage plat (z = 0) à partir de polygones **convexes** décrits en 2D :
/// chacun est triangulé en éventail. De quoi fabriquer des silhouettes connues
/// d'avance, sans dépendre d'un fichier.
private func plaque(_ polygones: [[SIMD2<Float>]]) throws -> Mesh {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    for polygone in polygones {
        let base = UInt32(positions.count)
        positions += polygone.map { SIMD3($0.x, $0.y, 0) }
        for sommet in 1..<(polygone.count - 1) {
            indices += [base, base + UInt32(sommet), base + UInt32(sommet + 1)]
        }
    }
    return try Mesh(positions: positions, indices: indices)
}

private func rectangle(x: Float, y: Float, largeur: Float, hauteur: Float) -> [SIMD2<Float>] {
    [[x, y], [x + largeur, y], [x + largeur, y + hauteur], [x, y + hauteur]]
}

private func disque(rayon: Float, segments: Int = 64, centre: SIMD2<Float> = .zero) -> [SIMD2<Float>] {
    (0..<segments).map { index in
        let angle = 2 * Float.pi * Float(index) / Float(segments)
        return centre + SIMD2(cos(angle), sin(angle)) * rayon
    }
}

@Suite("Polygone")
struct PolygonTests {

    @Test("Aire signée, orientation et périmètre d'un carré de 40 mm")
    func mesuresDeBase() throws {
        let carre = try #require(Polygon(points: rectangle(x: 0, y: 0, largeur: 0.04, hauteur: 0.04)))
        #expect(abs(carre.signedArea - 0.0016) < 1e-9)
        #expect(carre.isCounterClockwise)
        #expect(abs(carre.perimeter - 0.16) < 1e-6)
        #expect(!carre.reversed().isCounterClockwise)
        #expect(carre.oriented(counterClockwise: false).signedArea < 0)
    }

    @Test("Refuse ce qui n'est pas un contour")
    func contourInvalide() {
        #expect(Polygon(points: [[0, 0], [1, 0]]) == nil)
        #expect(Polygon(points: [[0, 0], [1, 0], [.nan, 1]]) == nil)
    }

    @Test("Dedans, dehors")
    func appartenance() throws {
        let carre = try #require(Polygon(points: rectangle(x: -0.02, y: -0.02, largeur: 0.04, hauteur: 0.04)))
        #expect(carre.contains([0, 0]))
        #expect(carre.contains([0.019, -0.019]))
        #expect(!carre.contains([0.021, 0]))
        #expect(!carre.contains([0, 0.5]))
    }

    @Test("La simplification enlève les points alignés, garde la forme")
    func simplification() throws {
        // Un carré dont chaque côté est découpé en dix : la forme ne change pas,
        // mais il a 40 points au lieu de 4.
        var points: [SIMD2<Float>] = []
        for cote in 0..<4 {
            for pas in 0..<10 {
                let t = Float(pas) / 10
                let coins: [SIMD2<Float>] = [[0, 0], [0.04, 0], [0.04, 0.04], [0, 0.04]]
                let a = coins[cote], b = coins[(cote + 1) % 4]
                points.append(a + (b - a) * t)
            }
        }
        let dense = try #require(Polygon(points: points))
        let simple = dense.simplified(tolerance: 0.0002)

        #expect(simple.points.count <= 6)
        #expect(abs(simple.area - dense.area) < 1e-7)
    }
}

@Suite("Plan de projection")
struct ProjectionPlaneTests {

    @Test("Les six directions donnent un repère direct", arguments: ProjectionDirection.allCases)
    func repereDirect(direction: ProjectionDirection) {
        let plan = ProjectionPlane(direction)
        #expect(simd_length(simd_cross(plan.u, plan.v) - plan.normal) < 1e-6)
    }

    @Test("Projeter puis revenir redonne le point de départ")
    func allerRetour() {
        let plan = ProjectionPlane(.minusY)
        let point = SIMD3<Float>(0.03, -0.01, 0.02)
        let plat = plan.project(point)
        #expect(simd_distance(plan.unproject(plat, depth: plan.depth(of: point)), point) < 1e-6)
    }
}

@Suite("Silhouette")
struct SilhouetteTests {
    static let plan = ProjectionPlane(.plusZ)

    /// Le contour est extrait d'un champ échantillonné au centre des cellules :
    /// il porte donc un biais d'environ une demi-cellule, qui se paie sur l'aire
    /// proportionnellement au périmètre. La tolérance dit cette limite au lieu
    /// de la cacher.
    static func toleranceAire(perimetre: Float, pas: Float) -> Float {
        perimetre * pas * 0.8
    }

    @Test("Un disque de 10 mm dilaté de 1 mm devient un disque de 11 mm")
    func disqueDilate() throws {
        let maillage = try plaque([disque(rayon: 0.010)])
        let silhouette = try Silhouette.outline(of: maillage, onto: Self.plan,
                                                clearance: 0.001, step: 0.0002)

        for point in silhouette.outer.points {
            #expect(abs(simd_length(point) - 0.011) < 0.0004)
        }
        #expect(abs(silhouette.outer.area - Float.pi * 0.011 * 0.011)
                < Self.toleranceAire(perimetre: 2 * Float.pi * 0.011, pas: 0.0002))
        #expect(silhouette.holes.isEmpty)
        #expect(silhouette.outer.isCounterClockwise)
    }

    @Test("Un carré dilaté prend des coins arrondis du rayon du jeu")
    func carreDilate() throws {
        let cote: Float = 0.04, jeu: Float = 0.002
        let maillage = try plaque([rectangle(x: -cote / 2, y: -cote / 2, largeur: cote, hauteur: cote)])
        let silhouette = try Silhouette.outline(of: maillage, onto: Self.plan,
                                                clearance: jeu, step: 0.0002)

        let boite = silhouette.outer.boundingBox
        #expect(abs((boite.max.x - boite.min.x) - (cote + 2 * jeu)) < 0.0006)
        #expect(abs((boite.max.y - boite.min.y) - (cote + 2 * jeu)) < 0.0006)

        // Carré + quatre bandes + quatre quarts de disque.
        let attendue = cote * cote + 4 * cote * jeu + Float.pi * jeu * jeu
        #expect(abs(silhouette.outer.area - attendue)
                < Self.toleranceAire(perimetre: 4 * cote + 2 * Float.pi * jeu, pas: 0.0002))
    }

    @Test("Une entaille plus étroite que deux fois le jeu se referme")
    func entailleRefermee() throws {
        // Rectangle de 40 × 30 mm entaillé de 3 mm de large sur 10 mm de haut.
        let maillage = try plaque([
            rectangle(x: -0.02, y: -0.015, largeur: 0.0185, hauteur: 0.03),
            rectangle(x: 0.0015, y: -0.015, largeur: 0.0185, hauteur: 0.03),
            rectangle(x: -0.0185, y: -0.015, largeur: 0.037, hauteur: 0.02),
        ])

        // Jeu de 2 mm : l'entaille de 3 mm disparaît.
        let refermee = try Silhouette.outline(of: maillage, onto: Self.plan,
                                              clearance: 0.002, step: 0.0002)
        let pleine = 0.04 * 0.03 + 2 * 0.002 * (0.04 + 0.03) + Float.pi * 0.002 * 0.002
        #expect(abs(refermee.outer.area - pleine)
                < Self.toleranceAire(perimetre: 2 * (0.04 + 0.03) + 2 * Float.pi * 0.002, pas: 0.0002))

        // Jeu de 0,3 mm : elle reste, et l'aire en pâtit.
        let ouverte = try Silhouette.outline(of: maillage, onto: Self.plan,
                                             clearance: 0.0003, step: 0.0002)
        #expect(ouverte.outer.area < pleine - 2e-5)
    }

    @Test("Seule la plus grande composante survit : les miettes disparaissent")
    func miettesIgnorees() throws {
        let maillage = try plaque([
            rectangle(x: -0.01, y: -0.01, largeur: 0.02, hauteur: 0.02),   // l'objet
            rectangle(x: 0.05, y: 0.05, largeur: 0.005, hauteur: 0.005),   // une miette
        ])
        let silhouette = try Silhouette.outline(of: maillage, onto: Self.plan,
                                                clearance: 0.001, step: 0.0002)

        let boite = silhouette.outer.boundingBox
        #expect(boite.max.x < 0.02)   // la miette n'est pas dans le contour
        #expect(abs(silhouette.outer.area - (0.0004 + 4 * 0.02 * 0.001 + Float.pi * 1e-6))
                < Self.toleranceAire(perimetre: 4 * 0.02 + 2 * Float.pi * 0.001, pas: 0.0002))
    }

    @Test("Un objet percé garde son trou, rétréci du jeu")
    func trouTraversant() throws {
        // Anneau : une couronne de quadrilatères entre deux cercles.
        let exterieur = disque(rayon: 0.02, segments: 48)
        let interieur = disque(rayon: 0.008, segments: 48)
        var morceaux: [[SIMD2<Float>]] = []
        for index in 0..<48 {
            let suivant = (index + 1) % 48
            morceaux.append([interieur[index], exterieur[index], exterieur[suivant], interieur[suivant]])
        }
        let silhouette = try Silhouette.outline(of: try plaque(morceaux), onto: Self.plan,
                                                clearance: 0.001, step: 0.0002)

        #expect(silhouette.holes.count == 1)
        let trou = try #require(silhouette.holes.first)
        #expect(!trou.isCounterClockwise)     // un trou tourne à l'envers
        for point in trou.points {
            #expect(abs(simd_length(point) - 0.007) < 0.0005)
        }
    }

    @Test("Deux appels identiques donnent exactement le même contour")
    func deterministe() throws {
        let maillage = try plaque([rectangle(x: -0.02, y: -0.015, largeur: 0.04, hauteur: 0.03)])
        let premier = try Silhouette.outline(of: maillage, onto: Self.plan, clearance: 0.001, step: 0.0003)
        let second = try Silhouette.outline(of: maillage, onto: Self.plan, clearance: 0.001, step: 0.0003)
        // Sans tri du recollage, l'ordre d'un dictionnaire ferait varier le
        // point de départ du contour, donc sa simplification.
        #expect(premier.outer == second.outer)
        #expect(premier.holes == second.holes)
    }

    @Test("Le pas s'élargit plutôt que de faire exploser la mémoire")
    func plafondMemoire() throws {
        let maillage = try plaque([rectangle(x: -0.05, y: -0.05, largeur: 0.1, hauteur: 0.1)])
        // Plafond réduit pour que le test reste instantané : c'est le mécanisme
        // qu'on vérifie, pas la valeur de production.
        let silhouette = try Silhouette.outline(of: maillage, onto: Self.plan,
                                                clearance: 0.001, step: 0.000001,
                                                maximumCells: 40_000)
        #expect(silhouette.step > 0.000001)
        let boite = silhouette.outer.boundingBox
        #expect(abs((boite.max.x - boite.min.x) - 0.102) < 0.002)
    }
}
