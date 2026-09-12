import Foundation
import Testing
@testable import Scan3DCore

@Suite("Emplacement des fichiers d'un scan")
struct ScanLayoutTests {
    private let scans = URL(filePath: "/base/Scans", directoryHint: .isDirectory)

    @Test("Tout vit sous <Scans>/<UUID>/ avec les noms attendus")
    func arborescence() {
        let id = UUID()
        let layout = ScanLayout(id: id, scansDirectory: scans)

        // `pathComponents` ignore le « / » final : on compare la structure, pas
        // une chaîne dont le format dépend du type de l'URL (dossier ou fichier).
        #expect(layout.root.pathComponents == ["/", "base", "Scans", id.uuidString])
        #expect(layout.imagesDirectory.pathComponents == layout.root.pathComponents + ["Images"])
        #expect(layout.checkpointDirectory.pathComponents == layout.root.pathComponents + ["Checkpoint"])
        #expect(layout.modelFile.pathComponents == layout.root.pathComponents + ["modele.usdz"])
        #expect(layout.modelFile.pathExtension == "usdz")
    }

    @Test("Les dossiers sont des dossiers, le modèle est un fichier")
    func typesDURL() {
        let layout = ScanLayout(scansDirectory: scans)
        #expect(layout.root.hasDirectoryPath)
        #expect(layout.imagesDirectory.hasDirectoryPath)
        #expect(layout.checkpointDirectory.hasDirectoryPath)
        #expect(!layout.modelFile.hasDirectoryPath)
    }

    @Test("Deux scans ne partagent aucun dossier")
    func isolation() {
        let a = ScanLayout(scansDirectory: scans)
        let b = ScanLayout(scansDirectory: scans)
        #expect(a.id != b.id)
        #expect(a.root != b.root)
        #expect(a.imagesDirectory != b.imagesDirectory)
    }
}

@Suite("Espace disque")
struct DiskSpacePolicyTests {
    @Test("Le seuil est inclusif")
    func seuil() {
        let seuil = DiskSpacePolicy.requiredFreeBytes
        #expect(DiskSpacePolicy.isSufficient(available: seuil))
        #expect(!DiskSpacePolicy.isSufficient(available: seuil - 1))
    }

    @Test("Les octets manquants ne sont jamais négatifs")
    func manquant() {
        let seuil = DiskSpacePolicy.requiredFreeBytes
        #expect(DiskSpacePolicy.missingBytes(available: 0) == seuil)
        #expect(DiskSpacePolicy.missingBytes(available: seuil - 10) == 10)
        #expect(DiskSpacePolicy.missingBytes(available: seuil + 1) == 0)
    }
}
