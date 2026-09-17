import Foundation
import os
import Scan3DCore

/// Erreurs des actions sur un scan, affichées par l'écran qui les a déclenchées.
enum BibliothequeErreur: LocalizedError {
    case nomInvalide
    case enregistrement
    case suppression

    var errorDescription: String? {
        switch self {
        case .nomInvalide:
            "Le nom doit contenir entre 1 et \(ScanRecord.maximumNameLength) caractères."
        case .enregistrement:
            "Le nouveau nom n'a pas pu être enregistré. Réessayez."
        case .suppression:
            "Le scan n'a pas pu être supprimé. Réessayez."
        }
    }
}

/// Source de vérité de la bibliothèque : la liste des scans et les actions
/// qui les modifient. Partagée par la liste et l'écran de détail, comme un
/// store Zustand lu par deux composants.
///
/// Détient aussi l'unique `ScanStore` de l'app, transmis au parcours de scan
/// et au détail.
@MainActor @Observable
final class BibliothequeModel {
    struct Element: Identifiable, Equatable {
        let layout: ScanLayout
        /// Nil si la fiche n'a pu être ni lue ni recréée (modèle illisible) :
        /// le scan reste listé pour qu'on puisse le supprimer.
        let fiche: ScanRecord?

        var id: UUID { layout.id }
    }

    enum Etat: Equatable {
        case chargement
        case pret
        case echec
    }

    static let messageSuppression = "Le modèle 3D sera effacé de cet iPhone. Les fichiers STL déjà exportés ne sont pas concernés."

    let store: ScanStore
    private(set) var elements: [Element] = []
    private(set) var etat: Etat = .chargement
    /// Le nettoyage (purge, photos restées) n'a lieu qu'au premier inventaire.
    private var nettoyageFait = false

    init(store: ScanStore = ScanStore()) {
        self.store = store
    }

    func element(_ id: UUID) -> Element? {
        elements.first { $0.id == id }
    }

    // MARK: Chargement

    /// Relit `Scans/` : au lancement, puis à chaque fin de parcours de scan.
    ///
    /// Le nettoyage est réservé au **premier** inventaire de la session : à ce
    /// moment, aucun scan ne peut être en cours, donc un dossier sans modèle
    /// est forcément le reste d'une session interrompue. Plus tard, le même
    /// constat pourrait viser un scan en train d'être capturé.
    func charger() async {
        let dossiers: [ScanLibrary.Folder]
        do {
            dossiers = try await store.inventaire()
        } catch {
            Logger.stockage.error("Inventaire des scans impossible : \(error.localizedDescription, privacy: .private)")
            if elements.isEmpty { etat = .echec }
            return
        }
        let nettoyer = !nettoyageFait
        nettoyageFait = true

        var charges: [Element] = []
        for dossier in dossiers {
            if dossier.shouldPurge {
                if nettoyer { await purger(dossier.layout) }
                continue
            }
            if nettoyer, dossier.shouldRemoveCaptureData {
                await retirerDonneesDeCapture(dossier.layout)
            }
            switch dossier.state {
            case .complete(let fiche):
                charges.append(Element(layout: dossier.layout, fiche: fiche))
            case .missingRecord, .invalidRecord:
                charges.append(Element(layout: dossier.layout, fiche: await recuperer(dossier)))
            case .unreadableRecord:
                // Peut-être valide mais momentanément inaccessible : on ne l'écrase pas.
                charges.append(Element(layout: dossier.layout, fiche: nil))
            case .newerRecord(let version):
                Logger.stockage.notice("Scan \(dossier.id.uuidString, privacy: .public) ignoré : fiche en version \(version, privacy: .public)")
            case .incomplete:
                break // traité par `shouldPurge`
            }
        }
        elements = Self.trier(charges)
        etat = .pret
    }

    // MARK: Actions

    /// `throws(BibliothequeErreur)` : l'appelant sait exactement quelles
    /// erreurs attendre, comme un type d'erreur dans une union TypeScript.
    func renommer(_ id: UUID, en nom: String) async throws(BibliothequeErreur) {
        guard let element = element(id), var fiche = element.fiche else { throw .enregistrement }
        do throws(ScanRecordError) {
            try fiche.rename(to: nom)
        } catch {
            throw .nomInvalide
        }
        try await enregistrer(fiche, pour: element)
    }

    /// Applique le calibrage d'un scan, ou le retire avec `nil` (décision E2).
    /// Les cotes brutes restent dans la fiche : l'opération est réversible.
    func calibrer(_ id: UUID, _ calibration: ScaleCalibration?) async throws(BibliothequeErreur) {
        guard let element = element(id), var fiche = element.fiche else { throw .enregistrement }
        fiche.calibration = calibration
        try await enregistrer(fiche, pour: element)
        Logger.stockage.info("Scan \(id.uuidString, privacy: .public) : facteur de calibrage \(calibration?.factor ?? 1, privacy: .public)")
    }

    private func enregistrer(_ fiche: ScanRecord, pour element: Element) async throws(BibliothequeErreur) {
        guard fiche != element.fiche else { return }
        do {
            try await store.ecrireFiche(fiche, dans: element.layout)
        } catch {
            Logger.stockage.error("Fiche non enregistrée : \(error.localizedDescription, privacy: .private)")
            throw .enregistrement
        }
        // Réentrance : pendant l'`await`, la liste a pu changer (rechargement,
        // suppression). On recherche l'élément au lieu de réutiliser un index.
        if let index = elements.firstIndex(where: { $0.id == fiche.id }) {
            elements[index] = Element(layout: element.layout, fiche: fiche)
        }
    }

    func supprimer(_ id: UUID) async throws(BibliothequeErreur) {
        guard let element = element(id) else { return }
        do {
            try await store.supprimer(element.layout)
        } catch {
            Logger.stockage.error("Suppression impossible : \(error.localizedDescription, privacy: .private)")
            throw .suppression
        }
        elements.removeAll { $0.id == id }
    }

    // MARK: Interne

    /// Scans de la tranche 1 (ou app tuée avant l'écriture de la fiche) : la
    /// fiche est recréée à partir du modèle. Leur vraie date est inconnue.
    private func recuperer(_ dossier: ScanLibrary.Folder) async -> ScanRecord? {
        do {
            let fiche = try await store.creerFiche(pour: dossier.layout, nom: ScanRecord.recoveredName, date: .now)
            Logger.stockage.notice("Scan \(dossier.id.uuidString, privacy: .public) récupéré (\(String(describing: dossier.state), privacy: .public))")
            return fiche
        } catch {
            Logger.stockage.error("Scan \(dossier.id.uuidString, privacy: .public) non récupérable : \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    private func purger(_ layout: ScanLayout) async {
        do {
            try await store.purger(layout)
        } catch {
            Logger.stockage.error("Purge impossible : \(error.localizedDescription, privacy: .private)")
        }
    }

    private func retirerDonneesDeCapture(_ layout: ScanLayout) async {
        do {
            try await store.nettoyerApresReconstruction(layout)
        } catch {
            Logger.stockage.error("Photos restées non supprimées : \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Plus récent en tête (`ScanLibrary.sortedNewestFirst`), scans illisibles à la fin.
    private static func trier(_ elements: [Element]) -> [Element] {
        // `uniquingKeysWith` plutôt que `uniqueKeysWithValues`, qui arrête l'app
        // sur un doublon : aucune donnée lue sur le disque ne doit pouvoir le faire.
        let parId = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { premier, _ in premier })
        let lisibles = ScanLibrary.sortedNewestFirst(elements.compactMap(\.fiche)).compactMap { parId[$0.id] }
        return lisibles + elements.filter { $0.fiche == nil }
    }
}
