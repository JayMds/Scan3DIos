import Foundation

/// Emplacements des fichiers d'un scan, tous dérivés d'un seul dossier racine.
///
/// ```
/// <scansDirectory>/<id>/
///   Images/        photos de capture (plusieurs centaines de Mo)
///   Checkpoint/    état intermédiaire — doit être VIDE au démarrage d'une session
///   modele.usdz    résultat de la reconstruction
///   scan.json      fiche du scan : nom, date, cotes, calibrage (tranche 2)
/// ```
///
/// Logique pure : aucun accès disque ici, donc testable sur Mac. La création
/// des dossiers, leur protection et leur suppression sont du ressort de l'app
/// (`ScanStore`), qui dépend du matériel.
///
/// `Hashable` : sert de valeur de navigation vers l'écran de détail.
public struct ScanLayout: Identifiable, Hashable, Sendable {
    public static let scansDirectoryName = "Scans"
    public static let imagesDirectoryName = "Images"
    public static let checkpointDirectoryName = "Checkpoint"
    public static let modelFileName = "modele.usdz"
    public static let recordFileName = "scan.json"

    public let id: UUID
    /// Dossier propre à ce scan : `<scansDirectory>/<id>/`.
    public let root: URL

    public init(id: UUID = UUID(), scansDirectory: URL) {
        self.id = id
        self.root = scansDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    public var imagesDirectory: URL {
        root.appending(path: Self.imagesDirectoryName, directoryHint: .isDirectory)
    }

    public var checkpointDirectory: URL {
        root.appending(path: Self.checkpointDirectoryName, directoryHint: .isDirectory)
    }

    public var modelFile: URL {
        root.appending(path: Self.modelFileName, directoryHint: .notDirectory)
    }

    /// Fiche du scan, lue et écrite par `ScanLibrary`.
    public var recordFile: URL {
        root.appending(path: Self.recordFileName, directoryHint: .notDirectory)
    }
}
