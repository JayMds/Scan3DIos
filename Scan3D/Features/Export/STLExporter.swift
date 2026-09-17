import Foundation
import os
import Scan3DCore

/// Écrit le STL dans un dossier temporaire dédié, puis le supprime dès que la
/// feuille de partage se ferme (`TRANCHE-1.md` : « supprimé après partage »).
///
/// `actor` : écrire quelques Mo ne doit jamais figer l'interface.
actor STLExporter {
    private let dossier: URL

    init(dossier: URL = URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)) {
        self.dossier = dossier
    }

    /// Vide d'abord le dossier : si l'app a été tuée pendant un partage, un
    /// fichier orphelin y traîne encore.
    func ecrire(_ maillage: Mesh, echelle: Double = 1, nom: String) throws -> URL {
        if FileManager.default.fileExists(atPath: dossier.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: dossier)
        }
        try FileManager.default.createDirectory(
            at: dossier,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let fichier = dossier.appending(path: nom, directoryHint: .notDirectory)
        let donnees = try STLWriter.binaryData(for: maillage, scale: echelle)
        // Même protection que le scan (décision D2) : la forme d'un objet peut
        // être sensible (une clé, un badge…).
        try donnees.write(to: fichier, options: [.atomic, .completeFileProtection])
        Logger.export.info("STL écrit : \(maillage.triangleCount, privacy: .public) triangles, \(donnees.count, privacy: .public) octets, échelle \(echelle, privacy: .public)")
        return fichier
    }

    func supprimer(_ fichier: URL) {
        do {
            try FileManager.default.removeItem(at: fichier)
            Logger.export.info("Fichier d'export supprimé")
        } catch {
            Logger.export.error("Suppression du fichier d'export impossible : \(error.localizedDescription, privacy: .private)")
        }
    }
}
