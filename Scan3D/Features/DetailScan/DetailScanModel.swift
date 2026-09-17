import Foundation
import os
import Scan3DCore

/// État de l'écran de détail d'un scan : le maillage en mémoire et l'export
/// STL. Nom, cotes et suppression viennent de `BibliothequeModel`, seule
/// source de vérité de la liste (sinon la liste et le détail pourraient
/// afficher deux noms différents).
///
/// Repris de `ScanFlowModel` (tranche 1) : la mesure point à point (étape 2)
/// et le calibrage (étape 3) viendront s'ajouter ici.
@MainActor @Observable
final class DetailScanModel {
    let layout: ScanLayout
    /// Le maillage lu, gardé pour l'export (≈ 1 Mo pour 50 k triangles).
    private(set) var maillage: Mesh?
    private(set) var lectureEchouee = false
    /// « 9,8 Mo ».
    private(set) var tailleModele: String?
    private(set) var exportEnCours = false
    /// Non nil → l'écran présente une alerte.
    private(set) var erreurExport: String?

    private let store: ScanStore
    private let exporteur: STLExporter

    init(layout: ScanLayout, store: ScanStore, exporteur: STLExporter = STLExporter()) {
        self.layout = layout
        self.store = store
        self.exporteur = exporteur
    }

    /// Lecture du modèle à l'ouverture de l'écran. Les cotes, elles, sont déjà
    /// dans la fiche : l'écran les affiche sans attendre cette lecture.
    func charger() async {
        guard maillage == nil else { return }
        lectureEchouee = false
        let octets = await store.tailleFichier(layout.modelFile)
        tailleModele = ByteCountFormatter.string(fromByteCount: octets, countStyle: .file)
        do {
            maillage = try await store.lireMaillage(layout)
        } catch {
            lectureEchouee = true
            Logger.reconstruction.error("Lecture du modèle impossible : \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Export

    var exportPossible: Bool { maillage != nil }

    /// Écrit le STL en millimètres et renvoie son emplacement ; nil en cas
    /// d'échec (message dans `erreurExport`).
    ///
    /// - Parameter echelle: facteur de calibrage du scan. Le fichier exporté
    ///   porte ainsi exactement les cotes affichées à l'écran.
    func preparerExportSTL(echelle: Double) async -> URL? {
        guard let maillage, !exportEnCours else { return nil }
        exportEnCours = true
        defer { exportEnCours = false }
        do {
            return try await exporteur.ecrire(maillage, echelle: echelle, nom: ExportFilename.stl(date: .now))
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
}
