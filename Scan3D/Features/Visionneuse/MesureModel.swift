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
    /// Ce que l'utilisateur a désigné : une face quand la surface est plane
    /// sous son doigt, un point sinon. Il n'a aucun mode à choisir.
    private(set) var cibleA: MeasurementTarget?
    private(set) var cibleB: MeasurementTarget?
    private(set) var mesure: SurfaceMeasurement?
    private(set) var annonce: Annonce?
    /// Calibrage du scan : la distance affichée en tient compte (décision E2).
    private(set) var calibration: ScaleCalibration?

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

    init(maillage: Mesh, modele: URL, calibration: ScaleCalibration? = nil) {
        self.maillage = maillage
        self.modele = modele
        self.calibration = calibration
        self.orbite = OrbitCamera(framing: maillage.boundingBox)
    }

    /// Distance à afficher : corrigée du calibrage s'il y en a un.
    var distanceMM: Double? {
        mesure?.lengthMM(calibratedBy: calibration)
    }

    /// Distance brute, telle que mesurée sur le maillage : c'est elle qui sert
    /// de point de départ au calibrage.
    var distanceBruteMM: Double? {
        mesure?.lengthMM
    }

    /// Cotes brutes du modèle, pour l'aperçu de l'écran de calibrage.
    var dimensionsBrutes: Dimensions {
        Dimensions(boundingBox: maillage.boundingBox)
    }

    func appliquerCalibrage(_ nouveau: ScaleCalibration?) {
        calibration = nouveau
        guard let distance = distanceMM else { return }
        annoncer(nouveau == nil
                 ? "Calibrage réinitialisé. Distance : \(DimensionsFormatter.spokenCentimeters(distance))"
                 : "Calibrage appliqué. Distance : \(DimensionsFormatter.spokenCentimeters(distance))")
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
        // Surface plane sous le doigt → on désigne la **face** : la mesure ne
        // dépend alors plus du millimètre près où l'on a visé.
        if let plan = maillage.fitPlane(around: touche.point) {
            poser(.face(plan, anchor: plan.projection(of: touche.point)))
        } else {
            poser(.point(touche.point))
        }
    }

    func effacer() {
        cibleA = nil
        cibleB = nil
        mesure = nil
        rafraichirMarqueurs()
        annoncer("Mesure effacée")
    }

    private func poser(_ cible: MeasurementTarget) {
        switch (cibleA, cibleB) {
        case (nil, _):
            cibleA = cible
            annoncer(cible.poseAnnoncee(repere: "A"))
        case (let a?, nil):
            cibleB = cible
            let nouvelle = SurfaceMeasurement(from: a, to: cible)
            mesure = nouvelle
            let distance = nouvelle.lengthMM(calibratedBy: calibration)
            annoncer("\(cible.poseAnnoncee(repere: "B")). \(nouvelle.kind.phrase) : \(DimensionsFormatter.spokenCentimeters(distance))")
            // Une distance mesurée n'est pas une donnée personnelle : publique,
            // c'est elle que le test terrain compare au pied à coulisse. La cote
            // brute est journalisée à côté de la cote calibrée.
            Logger.mesure.info("\(nouvelle.kind.phrase, privacy: .public) : \(DimensionsFormatter.millimeters(distance), privacy: .public) (brute : \(DimensionsFormatter.millimeters(nouvelle.lengthMM), privacy: .public))")
        default:
            // Troisième toucher : on recommence une mesure là où l'on a touché.
            cibleA = cible
            cibleB = nil
            mesure = nil
            annoncer("Nouvelle mesure. \(cible.poseAnnoncee(repere: "A"))")
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
        if let cibleA {
            marqueurs.addChild(repere(cibleA, couleur: .systemYellow, rayon: rayon))
        }
        if let cibleB {
            marqueurs.addChild(repere(cibleB, couleur: .systemTeal, rayon: rayon))
        }
        // Le trait d'une épaisseur traverse l'objet : il est souvent caché, et
        // c'est normal — ce sont les deux disques qui portent l'information.
        if let mesure, let trait = trait(de: mesure.segment, rayon: rayon * 0.3) {
            marqueurs.addChild(trait)
        }
    }

    /// Un disque posé à plat sur la face reconnue, une bille pour un simple point.
    private func repere(_ cible: MeasurementTarget, couleur: UIColor, rayon: Float) -> ModelEntity {
        switch cible {
        case .point(let position):
            return bille(position, couleur: couleur, rayon: rayon)
        case .face(let plan, let ancre):
            let disque = ModelEntity(
                mesh: .generateCylinder(height: rayon * 0.4, radius: plan.radius * 0.75),
                materials: [UnlitMaterial(color: couleur)]
            )
            // Légèrement décollé, sinon il clignote contre la surface.
            disque.position = ancre + plan.normal * (rayon * 0.25)
            disque.orientation = rotation(de: [0, 1, 0], vers: plan.normal)
            return disque
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
        trait.orientation = rotation(de: [0, 1, 0], vers: ecart / longueur)
        return trait
    }

    /// Rotation qui amène un axe sur un autre. Le cas « exactement à l'opposé »
    /// n'a pas de rotation unique, d'où le demi-tour explicite : sans lui, le
    /// quaternion renvoie des NaN.
    private func rotation(de axe: SIMD3<Float>, vers cible: SIMD3<Float>) -> simd_quatf {
        let alignement = simd_dot(axe, cible)
        if alignement > 0.9999 { return simd_quatf(angle: 0, axis: [1, 0, 0]) }
        if alignement < -0.9999 { return simd_quatf(angle: .pi, axis: [1, 0, 0]) }
        return simd_quatf(from: axe, to: cible)
    }
}
