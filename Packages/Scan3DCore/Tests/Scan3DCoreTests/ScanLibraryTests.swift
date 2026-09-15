import Foundation
import Testing
@testable import Scan3DCore

@Suite("Fiche de scan")
struct ScanRecordTests {
    static let boite = Dimensions(lengthMM: 189.2, widthMM: 163, heightMM: 56.8)
    /// 15/09/2026 12:32:00 UTC.
    static let date = Date(timeIntervalSince1970: 1_789_475_520)

    static func fiche(nom: String = "Boîte", calibration: ScaleCalibration? = nil) throws -> ScanRecord {
        try ScanRecord(id: UUID(), name: nom, createdAt: date, triangleCount: 42_318,
                       dimensions: boite, calibration: calibration)
    }

    /// Fiche JSON écrite à la main, pour tester ce qu'un fichier piégé contiendrait.
    static func json(version: Any = 1, nom: String = "Boîte", triangles: Any = 42_318,
                     date: String = "2026-09-15T12:32:00Z", hauteur: Any = 56.8,
                     calibration: String? = nil) -> Data {
        var champs = [
            #""schemaVersion": \#(version)"#,
            #""id": "\#(UUID().uuidString)""#,
            #""name": "\#(nom)""#,
            #""createdAt": "\#(date)""#,
            #""triangleCount": \#(triangles)"#,
            #""dimensions": {"lengthMM": 189.2, "widthMM": 163, "heightMM": \#(hauteur)}"#,
        ]
        if let calibration { champs.append(#""calibration": \#(calibration)"#) }
        return Data("{\(champs.joined(separator: ","))}".utf8)
    }

    @Test("Aller-retour JSON : la fiche relue est identique, calibrage compris")
    func allerRetour() throws {
        let calibration = try ScaleCalibration(measuredMM: 189.2, actualMM: 184)
        let fiche = try Self.fiche(calibration: calibration)
        let relue = try ScanRecord.decode(from: fiche.jsonData())
        #expect(relue == fiche)
        #expect(relue.calibration?.factor == calibration.factor)
    }

    @Test("La date est gardée à la seconde, pour que la relecture soit égale")
    func dateArrondie() throws {
        let fiche = try ScanRecord(id: UUID(), name: "A", createdAt: Self.date.addingTimeInterval(0.73),
                                   triangleCount: 1, dimensions: Self.boite)
        #expect(fiche.createdAt == Self.date)
        #expect(try ScanRecord.decode(from: fiche.jsonData()) == fiche)
    }

    @Test("Le fichier contient la version du format et une date ISO 8601")
    func formatDuFichier() throws {
        let texte = String(decoding: try Self.fiche().jsonData(), as: UTF8.self)
        #expect(texte.contains(#""schemaVersion" : 1"#))
        #expect(texte.contains(#""createdAt" : "2026-09-15T12:32:00Z""#))
        #expect(!texte.contains("calibration"))
    }

    @Test("Une fiche écrite à la main et valide est acceptée")
    func ficheManuelle() throws {
        let fiche = try ScanRecord.decode(from: Self.json())
        #expect(fiche.name == "Boîte")
        #expect(fiche.createdAt == Self.date)
        #expect(fiche.dimensions == Self.boite)
    }

    @Test("Refuse ce qui n'est pas du JSON de fiche", arguments: [
        Data(), Data("pas du json".utf8), Data("[]".utf8), Data(#"{"schemaVersion": "1"}"#.utf8),
    ])
    func pasUneFiche(donnees: Data) {
        #expect(throws: ScanRecordError.malformed) { _ = try ScanRecord.decode(from: donnees) }
    }

    @Test("Une version future est signalée à part : la fiche ne doit pas être écrasée")
    func versionFuture() {
        #expect(throws: ScanRecordError.unsupportedVersion(2)) {
            _ = try ScanRecord.decode(from: Self.json(version: 2))
        }
        #expect(throws: ScanRecordError.malformed) { _ = try ScanRecord.decode(from: Self.json(version: 0)) }
    }

    @Test("Refuse un champ hors limites", arguments: [
        json(nom: ""), json(nom: "   "), json(nom: String(repeating: "a", count: 81)),
        json(triangles: 0), json(triangles: -5), json(triangles: 2_000_001),
        json(date: "hier"), json(hauteur: -1),
        // Calibrage à ±30 % : impossible à saisir dans l'app, donc fichier modifié.
        json(calibration: #"{"measuredMM": 100, "actualMM": 130}"#),
        json(calibration: #"{"measuredMM": 0, "actualMM": 50}"#),
    ])
    func champHorsLimites(donnees: Data) {
        #expect(throws: ScanRecordError.malformed) { _ = try ScanRecord.decode(from: donnees) }
    }

    @Test("Le nom est nettoyé : une ligne, espaces fusionnés, bords retirés")
    func nettoyageDuNom() {
        #expect(ScanRecord.sanitizedName("  Interphone\n Wi-Fi\t ") == "Interphone Wi-Fi")
        #expect(ScanRecord.sanitizedName("Boîte\u{0000}\u{2028}à clés") == "Boîte à clés")
        #expect(ScanRecord.sanitizedName("\n\t ") == nil)
    }

    @Test("80 caractères visibles au plus ; un émoji compte pour un")
    func longueurDuNom() {
        #expect(ScanRecord.sanitizedName(String(repeating: "é", count: 80)) != nil)
        #expect(ScanRecord.sanitizedName(String(repeating: "é", count: 81)) == nil)
        // Famille = 7 scalaires Unicode, 1 caractère.
        #expect(ScanRecord.sanitizedName(String(repeating: "👨‍👩‍👧", count: 80)) != nil)
    }

    @Test("Renommer refuse un nom invalide sans rien modifier")
    func renommer() throws {
        var fiche = try Self.fiche()
        try fiche.rename(to: " Support mural ")
        #expect(fiche.name == "Support mural")
        #expect(throws: ScanRecordError.invalidName) { try fiche.rename(to: "") }
        #expect(fiche.name == "Support mural")
    }

    @Test("Nom par défaut daté, au format français")
    func nomParDefaut() throws {
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))
        #expect(ScanRecord.defaultName(date: Self.date, timeZone: paris) == "Scan du 15/09/2026 à 14:32")
        let matin = Date(timeIntervalSince1970: 1_767_254_700) // 01/01/2026 08:05 UTC
        #expect(ScanRecord.defaultName(date: matin, timeZone: .gmt) == "Scan du 01/01/2026 à 08:05")
    }

    @Test("Une fiche créée depuis un maillage reprend ses cotes et ses triangles")
    func depuisUnMaillage() throws {
        let cube = try Mesh(positions: [[0, 0, 0], [0.05, 0, 0], [0, 0.05, 0], [0, 0, 0.05]],
                            indices: [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3])
        let fiche = try ScanRecord(id: UUID(), name: "Cube", createdAt: Self.date, mesh: cube)
        #expect(fiche.triangleCount == 4)
        #expect(abs(fiche.dimensions.heightMM - 50) < 1e-3)
    }
}

@Suite("Bibliothèque des scans")
struct ScanLibraryTests {
    /// Vrai dossier `Scans/` temporaire, supprimé à la fin du test.
    private struct DossierTemporaire: ~Copyable {
        let scans = FileManager.default.temporaryDirectory
            .appending(path: "scan3d-bibliotheque-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: ScanLayout.scansDirectoryName, directoryHint: .isDirectory)

        init() throws {
            try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: scans.deletingLastPathComponent())
        }

        /// Crée un dossier de scan avec les éléments demandés.
        func scan(modele: Bool, photos: Bool = false, fiche: Data? = nil, id: UUID = UUID()) throws -> ScanLayout {
            let layout = ScanLayout(id: id, scansDirectory: scans)
            try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
            if modele { try Data("usdz".utf8).write(to: layout.modelFile) }
            if photos {
                try FileManager.default.createDirectory(at: layout.imagesDirectory, withIntermediateDirectories: true)
                try Data("heic".utf8).write(to: layout.imagesDirectory.appending(path: "IMG_0001.HEIC"))
            }
            if let fiche { try fiche.write(to: layout.recordFile) }
            return layout
        }
    }

    /// Sans classe de protection : macOS la refuse hors d'un conteneur d'app.
    private static let ecritureSurMac: Data.WritingOptions = [.atomic]

    private static func fiche(id: UUID, nom: String = "Boîte", date: Date = ScanRecordTests.date) throws -> ScanRecord {
        try ScanRecord(id: id, name: nom, createdAt: date, triangleCount: 1_000, dimensions: ScanRecordTests.boite)
    }

    private static func etats(_ dossiers: [ScanLibrary.Folder]) -> [UUID: ScanLibrary.FolderState] {
        Dictionary(uniqueKeysWithValues: dossiers.map { ($0.id, $0.state) })
    }

    @Test("Chaque dossier est classé : complet, sans fiche, fiche invalide, incomplet")
    func classement() throws {
        let dossier = try DossierTemporaire()
        let complet = UUID()
        let fiche = try Self.fiche(id: complet)
        _ = try dossier.scan(modele: true, fiche: fiche.jsonData(), id: complet)
        let sansFiche = try dossier.scan(modele: true)
        let ficheCorrompue = try dossier.scan(modele: true, fiche: Data("{".utf8))
        let versionFuture = try dossier.scan(modele: true, fiche: ScanRecordTests.json(version: 7))
        let interrompu = try dossier.scan(modele: false, photos: true)

        let etats = Self.etats(try ScanLibrary.inspect(scansDirectory: dossier.scans))
        #expect(etats.count == 5)
        #expect(etats[complet] == .complete(fiche))
        #expect(etats[sansFiche.id] == .missingRecord)
        #expect(etats[ficheCorrompue.id] == .invalidRecord(.malformed))
        #expect(etats[versionFuture.id] == .newerRecord(version: 7))
        #expect(etats[interrompu.id] == .incomplete)
    }

    @Test("Décisions : purger l'incomplet, retirer les photos restées, garder tout modèle")
    func decisions() throws {
        let dossier = try DossierTemporaire()
        let interrompu = try dossier.scan(modele: false, photos: true)
        let photosRestees = try dossier.scan(modele: true, photos: true)
        let corrompu = try dossier.scan(modele: true, fiche: Data("{".utf8))
        let futur = try dossier.scan(modele: true, fiche: ScanRecordTests.json(version: 2))

        let parId = Dictionary(uniqueKeysWithValues: try ScanLibrary.inspect(scansDirectory: dossier.scans).map { ($0.id, $0) })
        let a = try #require(parId[interrompu.id])
        let b = try #require(parId[photosRestees.id])
        let c = try #require(parId[corrompu.id])
        let d = try #require(parId[futur.id])

        // Pas de modèle : tout le dossier part, la question des photos ne se pose plus.
        #expect(a.shouldPurge && !a.shouldRemoveCaptureData)
        // Modèle présent + photos restées (app tuée avant le nettoyage D1) :
        // on garde le dossier, on retire les photos.
        #expect(!b.shouldPurge && b.shouldRemoveCaptureData)
        // Un modèle n'est jamais purgé, même avec une fiche corrompue ou future.
        #expect(!c.shouldPurge && !d.shouldPurge)
    }

    @Test("Un dossier vide (création puis app tuée) est incomplet")
    func dossierVide() throws {
        let dossier = try DossierTemporaire()
        let vide = try dossier.scan(modele: false)
        let resultat = try ScanLibrary.inspect(scansDirectory: dossier.scans)
        #expect(resultat.map(\.state) == [.incomplete])
        #expect(resultat.first?.hasCaptureData == false)
        #expect(resultat.first?.id == vide.id)
    }

    @Test("Ce que l'app n'a pas créé est ignoré, jamais proposé à la purge")
    func entreesInconnues() throws {
        let dossier = try DossierTemporaire()
        try FileManager.default.createDirectory(at: dossier.scans.appending(path: "PasUnUUID"),
                                                withIntermediateDirectories: true)
        try Data().write(to: dossier.scans.appending(path: UUID().uuidString)) // fichier, pas dossier
        try Data().write(to: dossier.scans.appending(path: ".DS_Store"))
        // UUID valide mais en minuscules : l'app ne l'a pas créé.
        try FileManager.default.createDirectory(at: dossier.scans.appending(path: UUID().uuidString.lowercased()),
                                                withIntermediateDirectories: true)
        #expect(try ScanLibrary.inspect(scansDirectory: dossier.scans).isEmpty)
    }

    @Test("Dossier Scans/ absent : bibliothèque vide, sans erreur")
    func dossierAbsent() throws {
        let absent = FileManager.default.temporaryDirectory.appending(path: "absent-\(UUID().uuidString)")
        #expect(try ScanLibrary.inspect(scansDirectory: absent).isEmpty)
    }

    @Test("Écriture puis lecture d'une fiche dans son dossier")
    func ecritureLecture() throws {
        let dossier = try DossierTemporaire()
        let layout = try dossier.scan(modele: true)
        var fiche = try Self.fiche(id: layout.id)
        try ScanLibrary.write(fiche, to: layout, options: Self.ecritureSurMac)
        try fiche.rename(to: "Renommée")
        // L'écriture atomique remplace la fiche existante.
        try ScanLibrary.write(fiche, to: layout, options: Self.ecritureSurMac)

        #expect(try ScanLibrary.readRecord(at: layout.recordFile, expectedID: layout.id) == fiche)
        #expect(Self.etats(try ScanLibrary.inspect(scansDirectory: dossier.scans))[layout.id] == .complete(fiche))
    }

    @Test("Refuse une fiche qui ne correspond pas à son dossier")
    func mauvaisDossier() throws {
        let dossier = try DossierTemporaire()
        let layout = try dossier.scan(modele: true, fiche: Self.fiche(id: UUID()).jsonData())
        #expect(throws: ScanRecordError.idMismatch) {
            _ = try ScanLibrary.readRecord(at: layout.recordFile, expectedID: layout.id)
        }
        #expect(throws: ScanRecordError.idMismatch) {
            try ScanLibrary.write(Self.fiche(id: UUID()), to: layout, options: Self.ecritureSurMac)
        }
    }

    @Test("Refuse une fiche trop grosse sans la charger en entier")
    func ficheTropGrosse() throws {
        let dossier = try DossierTemporaire()
        let geante = Data(repeating: 0x20, count: 10 * 1024 * 1024)
        let layout = try dossier.scan(modele: true, fiche: geante)
        #expect(throws: ScanRecordError.tooLarge) {
            _ = try ScanLibrary.readRecord(at: layout.recordFile, expectedID: layout.id)
        }
        #expect(Self.etats(try ScanLibrary.inspect(scansDirectory: dossier.scans))[layout.id]
                == .invalidRecord(.tooLarge))
    }

    @Test("Fiche absente à la lecture : illisible")
    func ficheAbsente() throws {
        let dossier = try DossierTemporaire()
        let layout = try dossier.scan(modele: true)
        #expect(throws: ScanRecordError.unreadableFile) {
            _ = try ScanLibrary.readRecord(at: layout.recordFile, expectedID: layout.id)
        }
    }

    @Test("Tri : le plus récent en tête, ordre stable à date égale")
    func tri() throws {
        let ancien = try Self.fiche(id: UUID(), date: ScanRecordTests.date.addingTimeInterval(-3_600))
        let recent = try Self.fiche(id: UUID(), date: ScanRecordTests.date.addingTimeInterval(3_600))
        let jumeauA = try Self.fiche(id: try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000A")))
        let jumeauB = try Self.fiche(id: try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000B")))

        let trie = ScanLibrary.sortedNewestFirst([ancien, jumeauB, recent, jumeauA])
        #expect(trie.map(\.id) == [recent.id, jumeauA.id, jumeauB.id, ancien.id])
    }
}
