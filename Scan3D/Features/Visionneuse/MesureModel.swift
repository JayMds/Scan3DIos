import Foundation
import RealityKit
import UIKit
import os
import simd
import Scan3DCore

/// Source de vérité de la visionneuse : la pose de la caméra, les deux points
/// posés, la distance — et la scène RealityKit qui les montre.
///
/// Le modèle possède les entités 3D (caméra, lumière, marqueurs) et les
/// modifie directement : une entité est un objet vivant, pas une valeur
/// recalculée à chaque rendu comme une vue SwiftUI. La vue, elle, se contente
/// d'afficher la scène et de transmettre les gestes.
@MainActor @Observable
final class MesureModel {
    /// Message pour VoiceOver. L'identifiant force l'annonce même si le texte
    /// est identique au précédent (deux « Point A posé » de suite).
    struct Annonce: Equatable {
        let id = UUID()
        let texte: String
    }

    enum Etat: Equatable {
        case chargement
        case pret
        case echec(String)
    }

    private(set) var etat: Etat = .chargement
    private(set) var orbite: OrbitCamera
    private(set) var pointA: SIMD3<Float>?
    private(set) var pointB: SIMD3<Float>?
    private(set) var mesure: SegmentMeasurement?
    private(set) var annonce: Annonce?

    /// Le maillage mesuré : le même que celui des cotes et de l'export STL.
    let maillage: Mesh
    /// Racine ajoutée à la `RealityView` : le modèle et les marqueurs.
    let scene = Entity()
    /// Ajoutée séparément, au premier niveau : RealityKit doit la reconnaître
    /// comme la caméra de rendu.
    let camera = PerspectiveCamera()

    private let modele: URL
    private let marqueurs = Entity()
    /// Taille de la zone 3D, retenue pour pouvoir recadrer à tout moment.
    private var ecran: SIMD2<Float>?

    /// Sensibilité du glissement : un balayage sur toute la largeur d'un
    /// iPhone (≈ 390 pt) fait faire un peu plus d'un demi-tour à l'objet.
    private static let radiansParPoint: Float = 0.008

    init(maillage: Mesh, modele: URL) {
        self.maillage = maillage
        self.modele = modele
        self.orbite = OrbitCamera(framing: maillage.boundingBox)
    }

    // MARK: Chargement

    func charger() async {
        guard etat == .chargement else { return }
        do {
            let objet = try await Entity(contentsOf: modele)
            recaler(objet)
            scene.addChild(objet)
            installerCameraEtLumiere()
            scene.addChild(marqueurs)
            etat = .pret
        } catch {
            etat = .echec("Le modèle 3D n'a pas pu être affiché.")
            Logger.reconstruction.error("Visionneuse : chargement impossible : \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Fait coïncider l'objet affiché avec le maillage mesuré.
    ///
    /// Model I/O ignore l'échelle déclarée dans le fichier USD, RealityKit
    /// l'applique (piège connu, `CLAUDE.md`). Sans ce recalage, un modèle
    /// exporté dans une autre unité s'afficherait à une taille et se
    /// mesurerait à une autre. Après, le repère de la scène **est** celui du
    /// maillage : un point touché à l'écran est directement une coordonnée du
    /// maillage. Le facteur est journalisé : c'est la réponse chiffrée à
    /// l'incertitude n° 2 du plan.
    private func recaler(_ objet: Entity) {
        let affiche = objet.visualBounds(relativeTo: nil).extents.max()
        let attendue = maillage.boundingBox.size.max()
        guard affiche > 1e-6, attendue > 1e-6 else { return }

        let facteur = attendue / affiche
        objet.scale = SIMD3(repeating: facteur)
        // Le centre doit être recalculé : la mise à l'échelle l'a déplacé.
        let centreAffiche = objet.visualBounds(relativeTo: nil).center
        let centreMaillage = (maillage.boundingBox.min + maillage.boundingBox.max) / 2
        objet.position += centreMaillage - centreAffiche
        Logger.reconstruction.info("Visionneuse : échelle RealityKit / maillage = \(facteur, privacy: .public)")
    }

    private func installerCameraEtLumiere() {
        camera.camera = PerspectiveCameraComponent(
            near: 0.01,
            far: 100,
            fieldOfViewInDegrees: orbite.fieldOfViewDegrees,
            fieldOfViewOrientation: .vertical
        )
        appliquerCamera()

        // Lumière solidaire de la caméra : la face regardée est toujours
        // éclairée, quel que soit l'angle — c'est ce qui rend les arêtes
        // lisibles, donc pointables.
        let lampe = DirectionalLight()
        lampe.light = DirectionalLightComponent(color: .white, intensity: 3_000)
        camera.addChild(lampe)
    }

    // MARK: Caméra

    /// Le modèle suit le doigt : glisser vers la droite fait tourner l'objet
    /// vers la droite, donc la caméra part vers la gauche.
    func pivoter(dx: Float, dy: Float) {
        orbite.turn(azimuth: -dx * Self.radiansParPoint, elevation: dy * Self.radiansParPoint)
        appliquerCamera()
    }

    /// `facteur` > 1 rapproche (pincement d'écartement).
    func zoomer(_ facteur: Float) {
        orbite.zoom(by: facteur)
        appliquerCamera()
    }

    /// Recadre une fois la taille réelle de l'écran connue (portrait, panneau
    /// du bas compris) : la distance de départ dépend de sa forme.
    func cadrer(pour taille: SIMD2<Float>) {
        guard ecran == nil, taille.x > 0, taille.y > 0 else { return }
        ecran = taille
        orbite.frame(radius: simd_length(maillage.boundingBox.size) / 2, aspectRatio: taille.x / taille.y)
        appliquerCamera()
    }

    /// Retour à la vue de départ : l'objet entier, de trois quarts.
    func recadrer() {
        orbite = OrbitCamera(framing: maillage.boundingBox)
        if let ecran {
            orbite.frame(radius: simd_length(maillage.boundingBox.size) / 2, aspectRatio: ecran.x / ecran.y)
        }
        appliquerCamera()
        annoncer("Vue recadrée")
    }

    private func appliquerCamera() {
        camera.look(at: orbite.target, from: orbite.position, upVector: [0, 1, 0], relativeTo: nil)
    }

    // MARK: Mesure

    /// Un point de l'écran devient un rayon, le rayon touche (ou non) la
    /// surface. Rien n'est posé au hasard : si le rayon passe à côté, on le dit.
    func toucher(_ point: SIMD2<Float>, taille: SIMD2<Float>) {
        guard etat == .pret,
              let rayon = orbite.ray(throughViewPoint: point, viewSize: taille) else { return }
        guard let touche = maillage.firstIntersection(with: rayon) else {
            annoncer("Aucun point du modèle à cet endroit")
            return
        }
        poser(touche.point)
    }

    func effacer() {
        pointA = nil
        pointB = nil
        mesure = nil
        rafraichirMarqueurs()
        annoncer("Points effacés")
    }

    private func poser(_ point: SIMD3<Float>) {
        switch (pointA, pointB) {
        case (nil, _):
            pointA = point
            annoncer("Point A posé")
        case (let a?, nil):
            pointB = point
            let segment = SegmentMeasurement(start: a, end: point)
            mesure = segment
            annoncer("Point B posé. Distance : \(DimensionsFormatter.spokenCentimeters(segment.lengthMM))")
            // Une distance mesurée n'est pas une donnée personnelle : publique,
            // c'est elle que le test terrain compare au pied à coulisse.
            Logger.mesure.info("Mesure A-B : \(DimensionsFormatter.millimeters(segment.lengthMM), privacy: .public)")
        default:
            // Troisième toucher : on recommence une mesure là où l'on a touché.
            pointA = point
            pointB = nil
            mesure = nil
            annoncer("Nouvelle mesure. Point A posé")
        }
        rafraichirMarqueurs()
    }

    private func annoncer(_ texte: String) {
        annonce = Annonce(texte: texte)
    }

    // MARK: Marqueurs 3D

    /// Repères en matériau **non éclairé** : leur couleur ne dépend pas de
    /// l'orientation de la surface, ils restent visibles partout.
    private func rafraichirMarqueurs() {
        marqueurs.children.removeAll()
        let rayon = max(0.002, maillage.boundingBox.size.max() * 0.015)
        if let pointA {
            marqueurs.addChild(bille(pointA, couleur: .systemYellow, rayon: rayon))
        }
        if let pointB {
            marqueurs.addChild(bille(pointB, couleur: .systemTeal, rayon: rayon))
        }
        if let mesure, let trait = trait(de: mesure, rayon: rayon * 0.3) {
            marqueurs.addChild(trait)
        }
    }

    private func bille(_ position: SIMD3<Float>, couleur: UIColor, rayon: Float) -> ModelEntity {
        let bille = ModelEntity(mesh: .generateSphere(radius: rayon),
                                materials: [UnlitMaterial(color: couleur)])
        bille.position = position
        return bille
    }

    private func trait(de mesure: SegmentMeasurement, rayon: Float) -> ModelEntity? {
        let ecart = mesure.end - mesure.start
        let longueur = simd_length(ecart)
        guard longueur > 1e-6 else { return nil }

        let trait = ModelEntity(mesh: .generateCylinder(height: longueur, radius: rayon),
                                materials: [UnlitMaterial(color: .white)])
        trait.position = mesure.midpoint
        // Le cylindre est aligné sur Y : on le bascule vers la direction du
        // segment. Le cas « exactement à l'opposé » n'a pas de rotation unique,
        // d'où le demi-tour explicite (sinon le quaternion renvoie des NaN).
        let direction = ecart / longueur
        let alignement = simd_dot(SIMD3<Float>(0, 1, 0), direction)
        if alignement > 0.9999 {
            trait.orientation = simd_quatf(angle: 0, axis: [1, 0, 0])
        } else if alignement < -0.9999 {
            trait.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        } else {
            trait.orientation = simd_quatf(from: [0, 1, 0], to: direction)
        }
        return trait
    }
}
