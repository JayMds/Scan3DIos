import Foundation
import os
import Scan3DCore

/// Erreurs de stockage présentées telles quelles à l'utilisateur.
enum ScanStoreError: LocalizedError {
    case espaceInconnu

    var errorDescription: String? {
        switch self {
        case .espaceInconnu: "Impossible de connaître l'espace disponible sur l'iPhone."
        }
    }
}

/// Gère `Application Support/Scans/` : création protégée d'un scan, espace
/// disque disponible, suppression.
///
/// `actor` : ses méthodes s'exécutent en série, hors du fil principal.
/// Supprimer un scan de 1 Go ne bloque donc jamais l'interface. Analogie : un
/// worker à qui on envoie des messages et dont on attend la réponse
/// (`await store.creerScan()`).
actor ScanStore {
    private let dossierScans: URL
    private var dossierPrepare = false

    init(dossierScans: URL = URL.applicationSupportDirectory
        .appending(path: ScanLayout.scansDirectoryName, directoryHint: .isDirectory)) {
        self.dossierScans = dossierScans
    }

    /// Octets disponibles pour un usage « important » (demandé explicitement
    /// par l'utilisateur). API à raison requise, déclarée E174.1 dans
    /// `PrivacyInfo.xcprivacy` : l'app refuse de démarrer si l'espace manque.
    func espaceDisponible() throws -> Int64 {
        try preparerDossierScans()
        let valeurs = try dossierScans.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let disponible = valeurs.volumeAvailableCapacityForImportantUsage else {
            throw ScanStoreError.espaceInconnu
        }
        return disponible
    }

    /// Crée `<Scans>/<UUID>/{Images,Checkpoint}` avec la protection `.complete`
    /// (décision D2, `docs/SECURITY.md`) : les fichiers créés dedans héritent
    /// de la classe de protection de leur dossier.
    func creerScan() throws -> ScanLayout {
        try preparerDossierScans()
        let layout = ScanLayout(scansDirectory: dossierScans)
        for dossier in [layout.root, layout.imagesDirectory, layout.checkpointDirectory] {
            try FileManager.default.createDirectory(
                at: dossier,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try exclureDeLaSauvegarde(layout.root)
        Logger.stockage.info(
            "Scan \(layout.id.uuidString, privacy: .public) créé, protection \(Self.protection(de: layout.imagesDirectory), privacy: .public)"
        )
        return layout
    }

    /// Nombre de fichiers et poids du dossier `Images/`, pour calibrer le seuil
    /// de `DiskSpacePolicy`. `fileSize` n'est pas une API « à raison requise »
    /// (seuls les horodatages de fichiers le sont).
    func tailleImages(_ layout: ScanLayout) -> (fichiers: Int, octets: Int64) {
        let cles: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerateur = FileManager.default.enumerator(
            at: layout.imagesDirectory,
            includingPropertiesForKeys: Array(cles),
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var fichiers = 0
        var octets: Int64 = 0
        for case let url as URL in enumerateur {
            guard let valeurs = try? url.resourceValues(forKeys: cles), valeurs.isRegularFile == true else { continue }
            fichiers += 1
            octets += Int64(valeurs.fileSize ?? 0)
        }
        return (fichiers, octets)
    }

    /// Supprime tout le dossier du scan, photos comprises. Sans effet s'il n'existe plus.
    func supprimer(_ layout: ScanLayout) throws {
        guard FileManager.default.fileExists(atPath: layout.root.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: layout.root)
        Logger.stockage.info("Scan \(layout.id.uuidString, privacy: .public) supprimé")
    }

    /// `Application Support` n'existe pas sur une installation neuve : on crée
    /// toute la chaîne, protégée et exclue de la sauvegarde iCloud (données
    /// volumineuses, régénérables, et potentiellement sensibles).
    private func preparerDossierScans() throws {
        guard !dossierPrepare else { return }
        try FileManager.default.createDirectory(
            at: dossierScans,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try exclureDeLaSauvegarde(dossierScans)
        dossierPrepare = true
    }

    private func exclureDeLaSauvegarde(_ url: URL) throws {
        var url = url
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try url.setResourceValues(valeurs)
    }

    /// Classe de protection réellement posée, pour le journal (le test manuel
    /// de l'étape 1 vérifie « NSFileProtectionComplete » dans Console).
    private static func protection(de url: URL) -> String {
        let attributs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        switch attributs?[.protectionKey] {
        case let type as FileProtectionType: return type.rawValue
        case let brut as String: return brut
        default: return "inconnue"
        }
    }
}
