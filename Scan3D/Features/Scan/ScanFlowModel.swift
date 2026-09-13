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
    private(set) var mode: CaptureMode = .orbit
    private(set) var autorisationCamera = CameraAuthorization.statut
    private(set) var layout: ScanLayout?
    /// Présent de la détection à la fin de la capture ; nil ensuite (mémoire).
    private(set) var capture: CaptureController?
    /// « 214 photos, 830 Mo » une fois la capture terminée.
    private(set) var bilanCapture: String?
    /// Présent pendant la reconstruction ; nil ensuite (mémoire).
    private(set) var reconstructor: Reconstructor?
    private(set) var progression: Double = 0
    private(set) var tempsRestant: TimeInterval?
    private(set) var etapeReconstruction: String?
    /// « 9,8 Mo » une fois le modèle écrit.
    private(set) var tailleModele: String?
    /// Vrai si l'échec vient de la reconstruction : les photos sont encore
    /// là, on peut relancer (le checkpoint accélère la reprise).
    private(set) var reprisePossible = false
    /// Pendant `annuler()`, les derniers événements des sessions sont ignorés
    /// (sinon un échec provoqué par l'arrêt s'afficherait avant la fermeture).
    private var annulationEnCours = false
    /// Mode plateau : `numberOfShotsTaken` est cumulé sur toutes les passes,
    /// on retient le compteur au début du tour pour afficher « n / 36 ».
    private(set) var photosAuDebutDuTour = 0
    private(set) var demarrageEnCours = false
    /// Non nil → l'UI présente une alerte ; elle le remet à nil en la fermant.
    var erreur: ScanFlowError?

    private let store: ScanStore

    init(store: ScanStore = ScanStore()) {
        self.store = store
    }

    /// Vrai aussi après un échec de reconstruction : annuler effacerait les
    /// photos, donc toute possibilité de reprendre.
    var annulationDemandeConfirmation: Bool {
        phase.cancellationNeedsConfirmation || reprisePossible
    }

    /// Le scan est terminé : quitter garde le modèle au lieu de le supprimer.
    var scanTermine: Bool {
        if case .preview = phase { true } else { false }
    }

    var photosCeTour: Int {
        max(0, (capture?.nombrePhotos ?? 0) - photosAuDebutDuTour)
    }

    // MARK: Préparation (écran 2)

    /// Bouton « Commencer » : permission caméra, espace disque, dossier du
    /// scan, puis ouverture de la session de capture. Chaque refus laisse
    /// l'utilisateur sur l'écran de préparation avec une explication.
    func demarrer(mode: CaptureMode) async {
        guard !demarrageEnCours else { return }
        demarrageEnCours = true
        defer { demarrageEnCours = false }
        self.mode = mode

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

            let nouveau = try await store.creerScan()
            layout = nouveau
            phase = suivante
            lancerCapture(pour: nouveau)
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

    // MARK: Capture (écrans 3 à 5)

    /// `false` si la session ne trouve pas d'objet devant la caméra.
    func commencerDetection() -> Bool {
        capture?.commencerDetection() ?? false
    }

    func reinitialiserDetection() {
        capture?.reinitialiserDetection()
    }

    /// La phase passera à `.capture` quand la session signalera `.capturing`.
    func commencerCapture() {
        capture?.commencerCapture()
    }

    /// Mode plateau : une photo à la demande.
    func prendrePhoto() {
        capture?.prendrePhoto()
    }

    /// Mode plateau : l'iPhone ne bougeant pas, RealityKit ne saura jamais
    /// que le tour est fini — c'est l'utilisateur qui le déclare.
    func terminerTour() {
        if phase == .capture { transiter(vers: .passComplete) }
    }

    /// La session reste en `.capturing` et n'émet rien : on transite nous-mêmes.
    func nouvellePasse() {
        capture?.nouvellePasse()
        commencerUnTour()
    }

    func nouvellePasseApresRetournement() {
        capture?.nouvellePasseApresRetournement()
        commencerUnTour()
    }

    private func commencerUnTour() {
        photosAuDebutDuTour = capture?.nombrePhotos ?? 0
        transiter(vers: .capture)
    }

    /// La phase passera à `.reconstruction` quand la session signalera `.completed`.
    func terminerCapture() {
        capture?.terminer()
    }

    private func lancerCapture(pour layout: ScanLayout) {
        let controller = CaptureController(layout: layout, mode: mode) { [weak self] evenement in
            self?.traiter(evenement)
        }
        capture = controller
        VeilleEcran.empecher(true)
        controller.demarrer()
    }

    private func traiter(_ evenement: CaptureController.Evenement) {
        guard !annulationEnCours else { return }
        switch evenement {
        case .captureCommencee:
            // Seule la première entrée en .capturing change de phase ; les
            // passes suivantes sont gérées par nouvellePasse().
            if phase == .detection { transiter(vers: .capture) }
        case .passeTerminee:
            if phase == .capture { transiter(vers: .passComplete) }
        case .terminee:
            capture = nil
            transiter(vers: .reconstruction(progress: 0))
            Task { await mesurerCapture() }
            lancerReconstruction()
        case .echec(let message):
            capture = nil
            VeilleEcran.empecher(false)
            transiter(vers: .failed(message: message))
        }
    }

    /// Poids réel des photos : calibre `DiskSpacePolicy` (incertitude 6 du plan).
    private func mesurerCapture() async {
        guard let layout else { return }
        let taille = await store.tailleImages(layout)
        let octets = ByteCountFormatter.string(fromByteCount: taille.octets, countStyle: .file)
        bilanCapture = "\(taille.fichiers) photos, \(octets)"
        Logger.scan.info("Capture terminée : \(taille.fichiers, privacy: .public) fichiers, \(taille.octets, privacy: .public) octets")
    }

    // MARK: Reconstruction (écran 6)

    /// Relance après un échec de reconstruction, avec le même checkpoint.
    func reprendreReconstruction() async {
        guard case .failed = phase, reprisePossible, let layout else { return }
        reprisePossible = false
        // Un modèle partiel pourrait gêner l'écriture (comportement non
        // documenté par Apple) : on repart d'un emplacement propre.
        do {
            try await store.supprimerFichier(layout.modelFile)
        } catch {
            Logger.stockage.error("Modèle partiel non supprimé : \(error.localizedDescription, privacy: .private)")
        }
        transiter(vers: .reconstruction(progress: 0))
        lancerReconstruction()
    }

    private func lancerReconstruction() {
        guard let layout else { return }
        progression = 0
        tempsRestant = nil
        etapeReconstruction = nil
        let reconstructor = Reconstructor { [weak self] evenement in
            self?.traiterReconstruction(evenement)
        }
        self.reconstructor = reconstructor
        // La veille reste désactivée (elle l'était déjà pendant la capture).
        VeilleEcran.empecher(true)
        reconstructor.lancer(
            images: layout.imagesDirectory,
            checkpoint: mode.usesCheckpoint ? layout.checkpointDirectory : nil,
            modele: layout.modelFile
        )
    }

    private func traiterReconstruction(_ evenement: Reconstructor.Evenement) {
        guard !annulationEnCours else { return }
        switch evenement {
        case .progression(let fraction):
            progression = fraction
            transiter(vers: .reconstruction(progress: fraction))
        case .info(let tempsRestant, let etape):
            self.tempsRestant = tempsRestant
            etapeReconstruction = etape
        case .terminee(let modele):
            reconstructor = nil
            VeilleEcran.empecher(false)
            transiter(vers: .preview(model: modele))
            Task { await finaliserModele(modele) }
        case .echec(let message):
            reconstructor = nil
            VeilleEcran.empecher(false)
            reprisePossible = true
            transiter(vers: .failed(message: message))
        case .annulee:
            // Piloté par annuler(), qui libère et supprime.
            break
        }
    }

    /// D1 : le modèle est là, les photos ne servent plus sur l'iPhone.
    private func finaliserModele(_ modele: URL) async {
        guard let layout else { return }
        let octets = await store.tailleFichier(modele)
        tailleModele = ByteCountFormatter.string(fromByteCount: octets, countStyle: .file)
        Logger.reconstruction.info("Modèle écrit : \(octets, privacy: .public) octets")
        do {
            try await store.nettoyerApresReconstruction(layout)
        } catch {
            Logger.stockage.error("Nettoyage après reconstruction impossible : \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Transition journalisée : un refus est un bug de séquencement, pas une
    /// erreur utilisateur — on ne casse pas l'app pour ça.
    private func transiter(vers cible: ScanPhase) {
        do {
            phase = try phase.transition(to: cible)
        } catch {
            Logger.scan.error("Transition refusée : \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Sortie

    /// Arrête la session en cours (capture ou reconstruction), puis supprime
    /// le dossier du scan, photos comprises.
    func annuler() async {
        annulationEnCours = true
        defer { annulationEnCours = false }
        if let capture {
            await capture.annuler()
            self.capture = nil
        }
        if let reconstructor {
            await reconstructor.annuler()
            self.reconstructor = nil
        }
        VeilleEcran.empecher(false)
        guard let layout else { return }
        do {
            try await store.supprimer(layout)
        } catch {
            Logger.stockage.error("Suppression du scan \(layout.id.uuidString, privacy: .public) impossible : \(error.localizedDescription, privacy: .private)")
        }
        self.layout = nil
    }
}
