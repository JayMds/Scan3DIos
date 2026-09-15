import Foundation

/// Inventaire du dossier `Scans/` : quels scans afficher, lesquels récupérer,
/// lesquels purger. Lecture et écriture des fiches `scan.json`.
///
/// La décision (afficher, récupérer, purger) est prise ici, testée sur Mac
/// avec de vrais dossiers temporaires. L'app (`ScanStore`) exécute ensuite
/// les suppressions : ce paquet ne supprime jamais rien lui-même.
public enum ScanLibrary {
    /// Une fiche fait moins de 1 Ko. 64 Ko laisse de la marge aux versions
    /// futures, tout en empêchant un fichier géant de saturer la mémoire.
    public static let maximumRecordBytes = 64 * 1024

    /// État d'un dossier `Scans/<UUID>/`.
    public enum FolderState: Equatable, Sendable {
        /// Modèle et fiche valide : affiché tel quel.
        case complete(ScanRecord)
        /// Modèle sans fiche (scans de la tranche 1, ou app tuée juste après
        /// la reconstruction) : fiche à recréer d'après le modèle.
        case missingRecord
        /// Modèle et fiche corrompue ou incohérente : fiche à recréer.
        case invalidRecord(ScanRecordError)
        /// Modèle et fiche impossible à lire (accès refusé) : on l'affiche sans
        /// fiche, mais on ne la réécrit pas — elle est peut-être valide.
        case unreadableRecord
        /// Fiche d'une version plus récente de l'app : on n'y touche pas.
        case newerRecord(version: Int)
        /// Pas de modèle : capture ou reconstruction interrompue. Les photos
        /// ne servent plus à rien → à purger (`SECURITY.md`).
        case incomplete
    }

    public struct Folder: Identifiable, Equatable, Sendable {
        public let layout: ScanLayout
        public let state: FolderState
        /// `Images/` ou `Checkpoint/` encore présent.
        public let hasCaptureData: Bool

        public var id: UUID { layout.id }

        /// Dossier entier à supprimer, photos comprises.
        public var shouldPurge: Bool { state == .incomplete }

        /// Photos et checkpoint d'un scan terminé (app tuée avant le nettoyage
        /// de la décision D1) : à supprimer, le modèle reste.
        public var shouldRemoveCaptureData: Bool { !shouldPurge && hasCaptureData }
    }

    // MARK: Inventaire

    /// Classe chaque dossier de scan. Les entrées dont le nom n'est pas un
    /// UUID écrit exactement comme l'app l'écrit (majuscules) sont ignorées :
    /// on ne décide jamais du sort de ce que l'app n'a pas créé. Dossier
    /// `Scans/` absent → bibliothèque vide.
    public static func inspect(scansDirectory: URL) throws -> [Folder] {
        let gestionnaire = FileManager.default
        guard gestionnaire.fileExists(atPath: scansDirectory.path(percentEncoded: false)) else { return [] }

        let entrees = try gestionnaire.contentsOfDirectory(
            at: scansDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return entrees.compactMap { entree -> Folder? in
            // `UUID(uuidString:)` accepte aussi les minuscules : « abc… » et
            // « ABC… » donneraient le même scan, alors que le chemin reconstruit
            // par `ScanLayout` ne désigne que le second.
            guard let id = UUID(uuidString: entree.lastPathComponent),
                  id.uuidString == entree.lastPathComponent,
                  estDossier(entree) else { return nil }
            let layout = ScanLayout(id: id, scansDirectory: scansDirectory)
            return Folder(
                layout: layout,
                state: etat(de: layout),
                hasCaptureData: estDossier(layout.imagesDirectory) || estDossier(layout.checkpointDirectory)
            )
        }
    }

    /// Plus récent en tête ; à date égale, ordre stable par identifiant (sinon
    /// deux scans récupérés au même instant échangeraient leur place à chaque
    /// chargement).
    public static func sortedNewestFirst(_ fiches: [ScanRecord]) -> [ScanRecord] {
        fiches.sorted { a, b in
            a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id.uuidString < b.id.uuidString
        }
    }

    // MARK: Fiches

    /// Lit une fiche sans jamais charger plus de `maximumRecordBytes` + 1
    /// octets, quelle que soit la taille annoncée du fichier.
    public static func readRecord(at fichier: URL, expectedID: UUID) throws(ScanRecordError) -> ScanRecord {
        let donnees: Data
        do {
            let lecteur = try FileHandle(forReadingFrom: fichier)
            defer { try? lecteur.close() }
            donnees = try lecteur.read(upToCount: maximumRecordBytes + 1) ?? Data()
        } catch {
            throw .unreadableFile
        }
        guard donnees.count <= maximumRecordBytes else { throw .tooLarge }

        let fiche = try ScanRecord.decode(from: donnees)
        // Un dossier copié ou renommé à la main : la fiche ne décrit pas ce modèle.
        guard fiche.id == expectedID else { throw .idMismatch }
        return fiche
    }

    /// Écriture atomique (fichier temporaire puis renommage) : une coupure en
    /// plein milieu laisse l'ancienne fiche intacte, jamais un JSON tronqué.
    ///
    /// Par défaut, protection `.complete` comme le reste du scan (décision
    /// D2). Sur Mac, hors du conteneur d'une app, macOS refuse de poser une
    /// classe de protection (erreur EPERM) : les tests passent `[.atomic]`.
    public static func write(
        _ fiche: ScanRecord,
        to layout: ScanLayout,
        options: Data.WritingOptions = [.atomic, .completeFileProtection]
    ) throws {
        guard fiche.id == layout.id else { throw ScanRecordError.idMismatch }
        let donnees = try fiche.jsonData()
        guard donnees.count <= maximumRecordBytes else { throw ScanRecordError.tooLarge }
        try donnees.write(to: layout.recordFile, options: options)
    }

    // MARK: Interne

    private static func etat(de layout: ScanLayout) -> FolderState {
        guard estFichier(layout.modelFile) else { return .incomplete }
        guard FileManager.default.fileExists(atPath: layout.recordFile.path(percentEncoded: false)) else {
            return .missingRecord
        }
        // `do throws(…)` : le `catch` reçoit un `ScanRecordError`, pas un
        // `any Error`, et le `switch` sur ses cas est vérifié à la compilation.
        do throws(ScanRecordError) {
            return .complete(try readRecord(at: layout.recordFile, expectedID: layout.id))
        } catch {
            switch error {
            case .unreadableFile: return .unreadableRecord
            case .unsupportedVersion(let version): return .newerRecord(version: version)
            default: return .invalidRecord(error)
            }
        }
    }

    private static func estDossier(_ url: URL) -> Bool {
        var dossier: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &dossier)
            && dossier.boolValue
    }

    private static func estFichier(_ url: URL) -> Bool {
        var dossier: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &dossier)
            && !dossier.boolValue
    }
}
