import Foundation

/// Raisons pour lesquelles une fiche de scan est refusée.
public enum ScanRecordError: Error, Equatable, Sendable {
    /// Nom vide après nettoyage, ou plus long que `ScanRecord.maximumNameLength`.
    case invalidName
    /// Nombre de triangles nul ou au-delà du plafond de `Mesh`.
    case invalidTriangleCount
    /// Fichier absent ou illisible (accès refusé, erreur disque).
    case unreadableFile
    /// Fichier plus gros que `ScanLibrary.maximumRecordBytes`.
    case tooLarge
    /// JSON invalide, champ manquant ou valeur hors limites.
    case malformed
    /// Fiche écrite par une version plus récente de l'app.
    case unsupportedVersion(Int)
    /// L'identifiant de la fiche ne correspond pas à son dossier.
    case idMismatch
}

/// Fiche d'un scan, enregistrée en `scan.json` à côté du modèle
/// (décision E1 de la tranche 2).
///
/// Tout ce que l'écran de bibliothèque affiche vient d'ici : on n'a pas à
/// relire chaque modèle 3D pour lister les scans. Le modèle reste la donnée de
/// référence ; la fiche peut être recréée à partir de lui.
///
/// Le fichier est traité comme une **entrée non fiable** (`SECURITY.md`) :
/// fichier corrompu, ancienne version, et en tranche 4 fichier reçu du Mac.
/// D'où le décodage validé champ par champ et le numéro de version.
public struct ScanRecord: Identifiable, Equatable, Sendable {
    /// À incrémenter à chaque changement incompatible du format.
    public static let currentSchemaVersion = 1
    public static let maximumNameLength = 80
    /// Nom des scans de la tranche 1, dont la date réelle est inconnue (lire
    /// la date d'un fichier est une API « à raison requise » : on s'en passe).
    public static let recoveredName = "Scan récupéré"

    public let id: UUID
    /// Nettoyé et borné : voir `sanitizedName(_:)`. Jamais utilisé dans un
    /// chemin de fichier (le dossier reste l'UUID).
    public private(set) var name: String
    public let createdAt: Date
    public let triangleCount: Int
    /// Cotes brutes, avant calibrage.
    public let dimensions: Dimensions
    /// Nil tant que l'utilisateur n'a pas calibré ce scan (étape 3).
    public var calibration: ScaleCalibration?

    public init(
        id: UUID,
        name: String,
        createdAt: Date,
        triangleCount: Int,
        dimensions: Dimensions,
        calibration: ScaleCalibration? = nil
    ) throws(ScanRecordError) {
        guard let nom = Self.sanitizedName(name) else { throw .invalidName }
        guard (1...Mesh.maximumTriangleCount).contains(triangleCount) else {
            throw .invalidTriangleCount
        }
        self.id = id
        self.name = nom
        // JSON garde la seconde, pas la milliseconde : on arrondit dès la
        // création pour qu'une fiche relue soit égale à celle écrite.
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
        self.triangleCount = triangleCount
        self.dimensions = dimensions
        self.calibration = calibration
    }

    /// Fiche d'un scan tout juste reconstruit (ou récupéré) : cotes et nombre
    /// de triangles viennent du maillage lu par `MeshLoader`.
    public init(id: UUID, name: String, createdAt: Date, mesh: Mesh) throws(ScanRecordError) {
        try self.init(
            id: id,
            name: name,
            createdAt: createdAt,
            triangleCount: mesh.triangleCount,
            dimensions: Dimensions(boundingBox: mesh.boundingBox)
        )
    }

    /// Cotes à afficher : brutes, ou corrigées si le scan a été calibré. Les
    /// cotes brutes, elles, restent intactes dans le fichier — un calibrage
    /// s'annule sans rien avoir perdu.
    public var calibratedDimensions: Dimensions {
        guard let calibration else { return dimensions }
        return dimensions.scaled(by: calibration.factor)
    }

    /// Change le nom ; refuse un nom vide ou trop long sans rien modifier.
    public mutating func rename(to nouveauNom: String) throws(ScanRecordError) {
        guard let nom = Self.sanitizedName(nouveauNom) else { throw .invalidName }
        name = nom
    }

    // MARK: Nom

    /// Nom saisi → nom enregistrable, ou nil s'il est refusé.
    ///
    /// Retours à la ligne, tabulations et caractères de contrôle deviennent
    /// des espaces, les espaces multiples sont fusionnés et les bords
    /// nettoyés : un nom tient sur une ligne de liste. La longueur se compte
    /// en caractères visibles (un émoji compte pour un), comme le perçoit
    /// l'utilisateur.
    public static func sanitizedName(_ brut: String) -> String? {
        let scalaires = brut.unicodeScalars.map { scalaire -> Unicode.Scalar in
            switch scalaire.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: " "
            default: scalaire
            }
        }
        let nom = String(String.UnicodeScalarView(scalaires))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard (1...maximumNameLength).contains(nom.count) else { return nil }
        return nom
    }

    /// « Scan du 15/09/2026 à 14:32 » — le fuseau est injectable pour des
    /// tests déterministes.
    public static func defaultName(date: Date, timeZone: TimeZone = .current) -> String {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = timeZone
        let c = calendrier.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "Scan du \(deuxChiffres(c.day))/\(deuxChiffres(c.month))/\(c.year ?? 0) "
            + "à \(deuxChiffres(c.hour)):\(deuxChiffres(c.minute))"
    }

    private static func deuxChiffres(_ valeur: Int?) -> String {
        let valeur = valeur ?? 0
        return valeur < 10 ? "0\(valeur)" : "\(valeur)"
    }
}

// MARK: - JSON

extension ScanRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, createdAt, triangleCount, dimensions, calibration
    }

    /// Lit juste la version, avant tout le reste : une fiche d'une version
    /// future peut avoir une tout autre structure.
    private struct VersionSeule: Decodable {
        let schemaVersion: Int
    }

    /// Octets JSON de la fiche (lisibles à l'œil, clés triées : un diff entre
    /// deux versions reste compréhensible).
    public func jsonData() throws -> Data {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encodeur.encode(self)
    }

    /// Décode et valide une fiche. Toute erreur de format devient `.malformed` :
    /// l'appelant n'a pas à connaître les détails de `DecodingError`.
    public static func decode(from donnees: Data) throws(ScanRecordError) -> ScanRecord {
        let decodeur = JSONDecoder()
        let version: Int
        do {
            version = try decodeur.decode(VersionSeule.self, from: donnees).schemaVersion
        } catch {
            throw .malformed
        }
        guard version == currentSchemaVersion else {
            // Une version 0 ou négative n'a jamais existé : fichier fabriqué.
            throw version > currentSchemaVersion ? .unsupportedVersion(version) : .malformed
        }
        do {
            return try decodeur.decode(ScanRecord.self, from: donnees)
        } catch {
            throw .malformed
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var conteneur = encoder.container(keyedBy: CodingKeys.self)
        try conteneur.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try conteneur.encode(id, forKey: .id)
        try conteneur.encode(name, forKey: .name)
        // Date en texte ISO 8601 écrite ici, et non via la stratégie du
        // JSONEncoder : le format du fichier ne dépend pas de qui l'encode.
        try conteneur.encode(createdAt.formatted(.iso8601), forKey: .createdAt)
        try conteneur.encode(triangleCount, forKey: .triangleCount)
        try conteneur.encode(dimensions, forKey: .dimensions)
        try conteneur.encodeIfPresent(calibration, forKey: .calibration)
    }

    public init(from decoder: any Decoder) throws {
        let conteneur = try decoder.container(keyedBy: CodingKeys.self)
        let version = try conteneur.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: conteneur, debugDescription: "Version \(version) non prise en charge"
            )
        }
        let texteDate = try conteneur.decode(String.self, forKey: .createdAt)
        guard let date = try? Date.ISO8601FormatStyle().parse(texteDate) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt, in: conteneur, debugDescription: "Date ISO 8601 attendue"
            )
        }
        do {
            // Même initialiseur que l'app : nom et nombre de triangles sont
            // revalidés ; dimensions et calibrage l'ont été à leur décodage.
            try self.init(
                id: conteneur.decode(UUID.self, forKey: .id),
                name: conteneur.decode(String.self, forKey: .name),
                createdAt: date,
                triangleCount: conteneur.decode(Int.self, forKey: .triangleCount),
                dimensions: conteneur.decode(Dimensions.self, forKey: .dimensions),
                calibration: conteneur.decodeIfPresent(ScaleCalibration.self, forKey: .calibration)
            )
        } catch let erreur as ScanRecordError {
            throw DecodingError.dataCorruptedError(
                forKey: .name, in: conteneur, debugDescription: "Fiche refusée : \(erreur)"
            )
        }
    }
}
