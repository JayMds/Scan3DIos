import Foundation
import os
import Scan3DCore

/// Erreurs affichées dans une alerte de l'écran de préparation.
enum ScanFlowError: LocalizedError {
    case espaceInsuffisant(manquant: Int64)
    case stockage(String)

    var errorDescription: String? {
        switch self {
        case .espaceInsuffisant(let manquant):
            let taille = ByteCountFormatter.string(fromByteCount: manquant, countStyle: .file)
            return "Il manque environ \(taille) d'espace libre pour scanner sereinement. Libérez de la place, puis réessayez."
        case .stockage(let detail):
            return "Le dossier du scan n'a pas pu être préparé. \(detail)"
        }
    }
}

/// Source de vérité du parcours de scan : un store (≈ Zustand) dont les
/// changements de phase passent par la machine à états `ScanPhase`.
/// `@MainActor` : tout ce qu'il expose est lu par SwiftUI.
@MainActor @Observable
final class ScanFlowModel {
    private(set) var phase: ScanPhase = .preparation
    private(set) var autorisationCamera = CameraAuthorization.statut
    private(set) var layout: ScanLayout?
    private(set) var demarrageEnCours = false
    /// Non nil → l'UI présente une alerte ; elle le remet à nil en la fermant.
    var erreur: ScanFlowError?

    private let store: ScanStore

    init(store: ScanStore = ScanStore()) {
        self.store = store
    }

    var annulationDemandeConfirmation: Bool {
        phase.cancellationNeedsConfirmation
    }

    /// Bouton « Commencer » : permission caméra, espace disque, dossier du
    /// scan, puis passage à la détection. Chaque refus laisse l'utilisateur
    /// sur l'écran de préparation avec une explication.
    func demarrer() async {
        guard !demarrageEnCours else { return }
        demarrageEnCours = true
        defer { demarrageEnCours = false }

        if autorisationCamera == .nonDeterminee {
            autorisationCamera = await CameraAuthorization.demander()
        }
        guard autorisationCamera == .autorisee else {
            Logger.scan.notice("Permission caméra refusée")
            return
        }

        do {
            // On valide la transition AVANT tout effet de bord : pas de dossier
            // orphelin si le séquencement est faux.
            let suivante = try phase.transition(to: .detection)

            let disponible = try await store.espaceDisponible()
            guard DiskSpacePolicy.isSufficient(available: disponible) else {
                erreur = .espaceInsuffisant(manquant: DiskSpacePolicy.missingBytes(available: disponible))
                Logger.scan.notice("Espace insuffisant : \(disponible, privacy: .public) octets disponibles")
                return
            }

            layout = try await store.creerScan()
            phase = suivante
        } catch let erreurPhase as ScanPhaseError {
            Logger.scan.error("Transition refusée : \(String(describing: erreurPhase), privacy: .public)")
        } catch {
            erreur = .stockage(error.localizedDescription)
            // La description peut contenir un chemin : privée.
            Logger.scan.error("Préparation du scan impossible : \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Au retour des Réglages, l'utilisateur peut avoir changé d'avis.
    func rafraichirAutorisation() {
        autorisationCamera = CameraAuthorization.statut
    }

    /// Supprime le dossier du scan (photos comprises) avant de fermer le parcours.
    func annuler() async {
        guard let layout else { return }
        do {
            try await store.supprimer(layout)
        } catch {
            Logger.stockage.error("Suppression du scan \(layout.id.uuidString, privacy: .public) impossible : \(error.localizedDescription, privacy: .private)")
        }
        self.layout = nil
    }
}
