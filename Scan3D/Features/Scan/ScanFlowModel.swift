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
    /// État de la mesure du modèle sur l'écran d'aperçu.
    enum MesureModele: Equatable {
        case enCours
        case reussie(Dimensions, triangles: Int)
        case echec
    }

    private(set) var phase: ScanPhase = .preparation
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
    private(set) var mesure: MesureModele = .enCours
    /// Le maillage mesuré, gardé pour l'export STL (≈ 1 Mo pour 50 k triangles).
    private(set) var maillage: Mesh?
    private(set) var exportEnCours = false
    /// Non nil → l'écran d'aperçu présente une alerte.
    private(set) var erreurExport: String?
    /// Vrai si l'échec vient de la reconstruction : les photos sont encore
    /// là, on peut relancer (le checkpoint accélère la reprise).
    private(set) var reprisePossible = false
    /// Pendant `annuler()`, les derniers événements des sessions sont ignorés
    /// (sinon un échec provoqué par l'arrêt s'afficherait avant la fermeture).
    private var annulationEnCours = false
    private(set) var demarrageEnCours = false
    /// Non nil → l'UI présente une alerte ; elle le remet à nil en la fermant.
    var erreur: ScanFlowError?

    private let store: ScanStore
    private let exporteur: STLExporter

    init(store: ScanStore = ScanStore(), exporteur: STLExporter = STLExporter()) {
        self.store = store
        self.exporteur = exporteur
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

    // MARK: Préparation (écran 2)

    /// Bouton « Commencer » : permission caméra, espace disque, dossier du
    /// scan, puis ouverture de la session de capture. Chaque refus laisse
    /// l'utilisateur sur l'écran de préparation avec une explication.
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

    /// La session reste en `.capturing` et n'émet rien : on transite nous-mêmes.
    func nouvellePasse() {
        capture?.nouvellePasse()
        transiter(vers: .capture)
    }

    func nouvellePasseApresRetournement() {
        capture?.nouvellePasseApresRetournement()
        transiter(vers: .capture)
    }

    /// La phase passera à `.reconstruction` quand la session signalera `.completed`.
    func terminerCapture() {
        capture?.terminer()
    }

    private func lancerCapture(pour layout: ScanLayout) {
        let controller = CaptureController(layout: layout) { [weak self] evenement in
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
            checkpoint: layout.checkpointDirectory,
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
            Task { await mesurerModele(modele) }
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

    /// Lecture et mesure hors du fil principal : un modèle de 50 k triangles
    /// se lit en une fraction de seconde, mais jamais au prix d'une interface figée.
    private func mesurerModele(_ modele: URL) async {
        mesure = .enCours
        do {
            let maillage = try await Task.detached(priority: .userInitiated) {
                try MeshLoader.load(contentsOf: modele)
            }.value
            let dimensions = Dimensions(boundingBox: maillage.boundingBox)
            self.maillage = maillage
            mesure = .reussie(dimensions, triangles: maillage.triangleCount)
            // Des cotes d'objet ne sont pas une donnée personnelle : publiques,
            // utiles pour comparer au test à la règle.
            Logger.reconstruction.info("Dimensions \(DimensionsFormatter.compact(dimensions), privacy: .public), \(maillage.triangleCount, privacy: .public) triangles, plausibles : \(dimensions.isPlausible, privacy: .public)")
        } catch {
            mesure = .echec
            Logger.reconstruction.error("Mesure du modèle impossible : \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Export (écran 8)

    var exportPossible: Bool { maillage != nil }

    /// Écrit le STL en millimètres et renvoie son emplacement ; nil en cas
    /// d'échec (message dans `erreurExport`).
    func preparerExportSTL() async -> URL? {
        guard let maillage, !exportEnCours else { return nil }
        exportEnCours = true
        defer { exportEnCours = false }
        do {
            return try await exporteur.ecrire(maillage, nom: ExportFilename.stl(date: .now))
        } catch {
            erreurExport = "Le fichier STL n'a pas pu être créé. Vérifiez l'espace disponible, puis réessayez."
            Logger.export.error("Écriture du STL impossible : \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Feuille de partage fermée, après un partage ou une annulation : le
    /// fichier temporaire ne doit pas rester sur l'iPhone.
    func exportTermine(_ fichier: URL, partage: Bool) async {
        Logger.export.info("Feuille de partage fermée, fichier partagé : \(partage, privacy: .public)")
        await exporteur.supprimer(fichier)
    }

    func effacerErreurExport() {
        erreurExport = nil
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
