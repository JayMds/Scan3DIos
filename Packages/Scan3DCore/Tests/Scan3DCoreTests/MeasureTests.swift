import Foundation
import ModelIO
import Testing
import simd
@testable import Scan3DCore

/// Cube de 5 cm centré sur l'origine, comme l'étalon qui sera imprimé.
private func cube(cote: Float = 0.05) throws -> Mesh {
    let asset = MDLAsset()
    asset.add(MDLMesh(boxWithExtent: [cote, cote, cote], segments: [1, 1, 1],
                      inwardNormals: false, geometryType: .triangles, allocator: nil))
    return try MeshLoader.load(asset: asset)
}

@Suite("Rayon")
struct RayTests {

    @Test("La direction est ramenée à une longueur de 1, donc t est en mètres")
    func normalisation() throws {
        let rayon = try #require(Ray(origin: [0, 0, 1], direction: [0, 0, -3]))
        #expect(rayon.direction == SIMD3<Float>(0, 0, -1))
        #expect(rayon.point(at: 0.25) == SIMD3<Float>(0, 0, 0.75))
    }

    @Test("Refuse ce qui ne décrit aucune droite")
    func directionInvalide() {
        #expect(Ray(origin: .zero, direction: .zero) == nil)
        #expect(Ray(origin: .zero, direction: [.nan, 0, 0]) == nil)
        #expect(Ray(origin: .zero, direction: [0, .infinity, 0]) == nil)
        #expect(Ray(origin: [.nan, 0, 0], direction: [0, 0, -1]) == nil)
    }
}

@Suite("Intersection rayon-maillage")
struct MeshPickingTests {

    @Test("Un rayon de face touche la face avant, à 25 mm du centre")
    func faceAvant() throws {
        let maillage = try cube()
        let rayon = try #require(Ray(origin: [0, 0, 1], direction: [0, 0, -1]))
        let touche = try #require(maillage.firstIntersection(with: rayon))

        #expect(abs(touche.point.z - 0.025) < 1e-5)
        #expect(abs(touche.point.x) < 1e-5 && abs(touche.point.y) < 1e-5)
        // 1 m - 25 mm : la face avant, pas celle de derrière (1,025 m).
        #expect(abs(touche.distance - 0.975) < 1e-5)
    }

    @Test("Un rayon qui passe à côté ne touche rien")
    func aCote() throws {
        let maillage = try cube()
        let rayon = try #require(Ray(origin: [0.2, 0, 1], direction: [0, 0, -1]))
        #expect(maillage.firstIntersection(with: rayon) == nil)
    }

    @Test("Un rayon qui s'éloigne de l'objet ne touche rien (pas de contact derrière l'œil)")
    func versLArriere() throws {
        let maillage = try cube()
        let rayon = try #require(Ray(origin: [0, 0, 1], direction: [0, 0, 1]))
        #expect(maillage.firstIntersection(with: rayon) == nil)
    }

    @Test("Depuis l'intérieur, la face opposée est touchée : les deux côtés comptent")
    func depuisLInterieur() throws {
        let maillage = try cube()
        let rayon = try #require(Ray(origin: .zero, direction: [0, 0, -1]))
        let touche = try #require(maillage.firstIntersection(with: rayon))
        #expect(abs(touche.point.z + 0.025) < 1e-5)
        #expect(abs(touche.distance - 0.025) < 1e-5)
    }

    @Test("Un rayon parallèle au triangle glisse dessus sans le toucher")
    func parallele() throws {
        let triangle = try Mesh(positions: [[0, 0, 0], [1, 0, 0], [0, 1, 0]], indices: [0, 1, 2])
        let dansLePlan = try #require(Ray(origin: [-1, 0.2, 0], direction: [1, 0, 0]))
        #expect(triangle.firstIntersection(with: dansLePlan) == nil)

        let deFace = try #require(Ray(origin: [0.2, 0.2, 1], direction: [0, 0, -1]))
        #expect(triangle.firstIntersection(with: deFace) != nil)
    }

    @Test("Un triangle dégénéré est ignoré, sans division par zéro")
    func triangleDegenere() throws {
        let plat = try Mesh(positions: [[0, 0, 0], [0, 0, 0], [0, 0, 0]], indices: [0, 1, 2])
        let rayon = try #require(Ray(origin: [0, 0, 1], direction: [0, 0, -1]))
        #expect(plat.firstIntersection(with: rayon) == nil)
    }

    @Test("Le triangle touché est identifié")
    func rangDuTriangle() throws {
        let maillage = try cube()
        let rayon = try #require(Ray(origin: [0, 1, 0], direction: [0, -1, 0]))
        let touche = try #require(maillage.firstIntersection(with: rayon))
        #expect((0..<maillage.triangleCount).contains(touche.triangleIndex))
        #expect(abs(touche.point.y - 0.025) < 1e-5)
    }

    @Test("50 000 triangles se parcourent en quelques millisecondes")
    func performance() throws {
        // Grille de 160 × 160 cases = 51 200 triangles, l'ordre de grandeur
        // d'un scan d'iPhone (niveau de détail `.reduced`).
        let cotes = 160
        var sommets: [SIMD3<Float>] = []
        for z in 0...cotes {
            for x in 0...cotes {
                sommets.append([Float(x) / Float(cotes), 0, Float(z) / Float(cotes)])
            }
        }
        var faces: [UInt32] = []
        for z in 0..<cotes {
            for x in 0..<cotes {
                let coin = UInt32(z * (cotes + 1) + x)
                let suivant = coin + UInt32(cotes + 1)
                faces.append(contentsOf: [coin, suivant, coin + 1, coin + 1, suivant, suivant + 1])
            }
        }
        let grille = try Mesh(positions: sommets, indices: faces)
        #expect(grille.triangleCount == 51_200)

        // Le pire cas : un rayon qui ne touche rien, donc tous les triangles testés.
        let rayon = try #require(Ray(origin: [0.5, 1, 0.5], direction: [0, 1, 0]))
        let debut = ContinuousClock.now
        for _ in 0..<5 { _ = grille.firstIntersection(with: rayon) }
        let parAppel = (ContinuousClock.now - debut) / 5

        // Mesuré à 6,8 ms le 16/09/2026 sur Mac, **sans optimisation** (`swift test`
        // compile en debug) ; l'app, compilée en release, est plusieurs fois plus
        // rapide. Le seuil laisse de la marge à une machine chargée.
        #expect(parAppel < .milliseconds(50), "Intersection : \(parAppel) par appel")
    }
}

@Suite("Caméra d'orbite")
struct OrbitCameraTests {
    static let ecran = SIMD2<Float>(390, 700)
    static let boite = BoundingBox(min: [-0.025, -0.025, -0.025], max: [0.025, 0.025, 0.025])

    static func face(distance: Float = 0.3) -> OrbitCamera {
        OrbitCamera(target: .zero, distance: distance, distanceRange: 0.05...2)
    }

    @Test("Azimut et élévation nuls : l'œil est sur +Z, face à l'objet")
    func poseDeDepart() {
        let camera = Self.face()
        #expect(simd_distance(camera.position, SIMD3<Float>(0, 0, 0.3)) < 1e-5)
        #expect(simd_distance(camera.basis.forward, SIMD3<Float>(0, 0, -1)) < 1e-5)
        #expect(simd_distance(camera.basis.up, SIMD3<Float>(0, 1, 0)) < 1e-5)
    }

    @Test("Le cadrage fait tenir tout l'objet dans l'écran")
    func cadrage() throws {
        var camera = OrbitCamera(framing: Self.boite)
        camera.frame(radius: simd_length(Self.boite.size) / 2, aspectRatio: Self.ecran.x / Self.ecran.y)

        var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = -minimum
        for coin in Self.coins(de: Self.boite) {
            let ecran = try #require(camera.project(coin, viewSize: Self.ecran))
            minimum = simd_min(minimum, ecran)
            maximum = simd_max(maximum, ecran)
        }
        #expect(minimum.x > 0 && minimum.y > 0)
        #expect(maximum.x < Self.ecran.x && maximum.y < Self.ecran.y)
        // Et l'objet occupe vraiment l'écran : au moins la moitié de la largeur.
        #expect(maximum.x - minimum.x > Self.ecran.x / 2)
    }

    @Test("Le rayon du centre de l'écran vise la cible")
    func rayonCentral() throws {
        let camera = Self.face()
        let rayon = try #require(camera.ray(throughViewPoint: Self.ecran / 2, viewSize: Self.ecran))
        #expect(simd_distance(rayon.direction, camera.basis.forward) < 1e-5)
        #expect(simd_length(rayon.point(at: camera.distance) - camera.target) < 1e-5)
    }

    @Test("Le bord haut de l'écran correspond à la moitié du champ de vision")
    func ouvertureVerticale() throws {
        let camera = Self.face()
        let rayon = try #require(camera.ray(throughViewPoint: [Self.ecran.x / 2, 0], viewSize: Self.ecran))
        let angle = acos(min(1, simd_dot(rayon.direction, camera.basis.forward)))
        #expect(abs(angle - camera.fieldOfViewDegrees * .pi / 180 / 2) < 1e-4)
    }

    @Test("Aller-retour : un point projeté à l'écran, puis visé, se retrouve sur le rayon")
    func allerRetour() throws {
        var camera = Self.face()
        camera.turn(azimuth: 0.7, elevation: 0.3)
        let point = SIMD3<Float>(0.01, -0.02, 0.005)

        let ecran = try #require(camera.project(point, viewSize: Self.ecran))
        let rayon = try #require(camera.ray(throughViewPoint: ecran, viewSize: Self.ecran))
        // Distance du point à la droite du rayon : nulle à la précision des Float.
        let versPoint = point - rayon.origin
        let ecart = simd_length(versPoint - rayon.direction * simd_dot(versPoint, rayon.direction))
        #expect(ecart < 1e-5)
    }

    @Test("Un point derrière l'œil ne se projette pas")
    func derriereLOeil() {
        let camera = Self.face()
        #expect(camera.project([0, 0, 1], viewSize: Self.ecran) == nil)
    }

    @Test("L'élévation s'arrête avant la verticale, la distance reste dans ses bornes")
    func bornes() {
        var camera = Self.face()
        camera.turn(azimuth: 0, elevation: 10)
        #expect(camera.elevation == OrbitCamera.elevationLimit)
        camera.turn(azimuth: 0, elevation: -20)
        #expect(camera.elevation == -OrbitCamera.elevationLimit)

        camera.zoom(by: 1_000)
        #expect(camera.distance == camera.distanceRange.lowerBound)
        camera.zoom(by: 0.0001)
        #expect(camera.distance == camera.distanceRange.upperBound)
    }

    @Test("Une valeur non finie ne casse pas la pose")
    func valeurNonFinie() {
        var camera = Self.face()
        camera.turn(azimuth: .nan, elevation: 0)
        camera.zoom(by: .infinity)
        camera.zoom(by: -1)
        #expect(camera.azimuth == 0)
        #expect(camera.distance == 0.3)
    }

    /// Les 8 coins d'une boîte englobante.
    static func coins(de boite: BoundingBox) -> [SIMD3<Float>] {
        [boite.min.x, boite.max.x].flatMap { x in
            [boite.min.y, boite.max.y].flatMap { y in
                [boite.min.z, boite.max.z].map { z in SIMD3<Float>(x, y, z) }
            }
        }
    }
}

@Suite("Mesure point à point")
struct SegmentMeasurementTests {

    @Test("Deux coins opposés d'une face du cube de 50 mm : 70,7 mm")
    func diagonaleDeFace() {
        let mesure = SegmentMeasurement(start: [-0.025, -0.025, 0.025], end: [0.025, 0.025, 0.025])
        #expect(abs(mesure.lengthMM - 70.71) < 0.01)
        #expect(mesure.midpoint == SIMD3<Float>(0, 0, 0.025))
    }

    @Test("Deux faces opposées : 50 mm, l'arête du cube")
    func arete() {
        let mesure = SegmentMeasurement(start: [0, 0, 0.025], end: [0, 0, -0.025])
        #expect(abs(mesure.lengthMM - 50) < 1e-3)
        #expect(abs(mesure.lengthMeters - 0.05) < 1e-6)
    }

    @Test("Deux points confondus mesurent zéro")
    func memePoint() {
        let mesure = SegmentMeasurement(start: [0.1, 0.2, 0.3], end: [0.1, 0.2, 0.3])
        #expect(mesure.lengthMM == 0)
    }

    @Test("De face puis de dos : l'épaisseur mesurée du cube vaut bien 50 mm")
    func deBoutEnBout() throws {
        let maillage = try cube()
        let ecran = SIMD2<Float>(390, 700)
        // Pile de face (azimut et élévation nuls) : le rayon central traverse le
        // cube perpendiculairement, donc d'une face à la face opposée.
        var camera = OrbitCamera(target: .zero, distance: 0.2, distanceRange: 0.05...2)

        let rayonDeFace = try #require(camera.ray(throughViewPoint: ecran / 2, viewSize: ecran))
        let devant = try #require(maillage.firstIntersection(with: rayonDeFace))

        camera.turn(azimuth: .pi, elevation: 0)
        let rayonDeDos = try #require(camera.ray(throughViewPoint: ecran / 2, viewSize: ecran))
        let derriere = try #require(maillage.firstIntersection(with: rayonDeDos))

        let mesure = SegmentMeasurement(start: devant.point, end: derriere.point)
        #expect(abs(mesure.lengthMM - 50) < 0.05)
    }
}
