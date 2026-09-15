import Foundation
import os

/// Journaux de l'app, un par domaine (≈ `debug("scan3d:stockage")` en JS).
///
/// Règle du projet : jamais un chemin ni un nom de fichier utilisateur sans
/// `privacy: .private` — les journaux peuvent finir dans un rapport de bug.
/// Un identifiant de scan (UUID aléatoire) peut, lui, rester public.
extension Logger {
    private static let sousSysteme = Bundle.main.bundleIdentifier ?? "fr.jinkuro.scan3d"

    static let scan = Logger(subsystem: sousSysteme, category: "scan")
    static let stockage = Logger(subsystem: sousSysteme, category: "stockage")
    static let reconstruction = Logger(subsystem: sousSysteme, category: "reconstruction")
    static let export = Logger(subsystem: sousSysteme, category: "export")
}
