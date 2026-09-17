import Foundation

/// Cotes d'un objet en millimètres, telles qu'un utilisateur d'imprimante 3D
/// les attend : longueur ≥ largeur à l'horizontale, hauteur à la verticale.
///
/// Calculées sur la boîte englobante alignée sur les axes du modèle : si
/// l'objet est tourné autour de la verticale dans le fichier, longueur et
/// largeur sont surestimées (la diagonale compte). À surveiller au test à la
/// règle ; un rectangle d'aire minimale corrigerait ce cas si besoin.
///
/// `Codable` : les cotes brutes (avant calibrage) sont enregistrées dans
/// `scan.json` pour afficher la bibliothèque sans relire chaque modèle.
public struct Dimensions: Equatable, Sendable, Codable {
    /// Plus grande cote horizontale.
    public let lengthMM: Double
    /// Plus petite cote horizontale.
    public let widthMM: Double
    /// Cote verticale.
    public let heightMM: Double

    /// Plage dans laquelle un scan d'objet a du sens. En dehors, c'est très
    /// probablement une erreur d'unité (fichier en cm, en mm…) : l'app
    /// avertit au lieu de laisser imprimer une pièce 10× ou 1000× fausse.
    public static let plausibleLargestSideMM: ClosedRange<Double> = 1...5_000

    public init(lengthMM: Double, widthMM: Double, heightMM: Double) {
        self.lengthMM = lengthMM
        self.widthMM = widthMM
        self.heightMM = heightMM
    }

    /// RealityKit : axe Y vertical (Model I/O ignore l'`upAxis` du fichier).
    public init(boundingBox: BoundingBox) {
        let taille = boundingBox.size
        let horizontalA = Units.millimeters(fromMeters: Double(taille.x))
        let horizontalB = Units.millimeters(fromMeters: Double(taille.z))
        self.init(
            lengthMM: max(horizontalA, horizontalB),
            widthMM: min(horizontalA, horizontalB),
            heightMM: Units.millimeters(fromMeters: Double(taille.y))
        )
    }

    public var largestSideMM: Double { max(lengthMM, widthMM, heightMM) }

    public var isPlausible: Bool { Self.plausibleLargestSideMM.contains(largestSideMM) }

    /// Cotes corrigées par un facteur de calibrage (décision E2).
    public func scaled(by factor: Double) -> Dimensions {
        Dimensions(lengthMM: lengthMM * factor, widthMM: widthMM * factor, heightMM: heightMM * factor)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case lengthMM, widthMM, heightMM
    }

    /// `scan.json` est une entrée non fiable : une cote négative ou non finie
    /// ferait afficher (ou exporter) n'importe quoi. On refuse le fichier.
    /// Une cote invraisemblable mais finie reste acceptée : l'écran avertit
    /// déjà via `isPlausible`.
    public init(from decoder: any Decoder) throws {
        let conteneur = try decoder.container(keyedBy: CodingKeys.self)
        let longueur = try conteneur.decode(Double.self, forKey: .lengthMM)
        let largeur = try conteneur.decode(Double.self, forKey: .widthMM)
        let hauteur = try conteneur.decode(Double.self, forKey: .heightMM)
        guard [longueur, largeur, hauteur].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .lengthMM, in: conteneur,
                debugDescription: "Cote négative ou non finie"
            )
        }
        self.init(lengthMM: longueur, widthMM: largeur, heightMM: hauteur)
    }
}

/// Textes des dimensions : à l'écran en millimètres (l'unité des slicers),
/// à l'oral en centimètres (plus facile à entendre et à retenir).
public enum DimensionsFormatter {
    /// L'interface est en français : la virgule décimale doit suivre le texte.
    public static let french = Locale(identifier: "fr_FR")

    /// « 124,0 mm » — une décimale, sans séparateur de milliers, espace insécable.
    public static func millimeters(_ valeur: Double, locale: Locale = french) -> String {
        "\(nombre(valeur, locale: locale))\u{00A0}mm"
    }

    /// « 124,0 × 85,6 × 40,2 mm » (longueur × largeur × hauteur).
    public static func compact(_ dimensions: Dimensions, locale: Locale = french) -> String {
        let cotes = [dimensions.lengthMM, dimensions.widthMM, dimensions.heightMM]
            .map { nombre($0, locale: locale) }
            .joined(separator: " × ")
        return "\(cotes)\u{00A0}mm"
    }

    /// « 12,4 centimètres » ; singulier en dessous de 2, comme en français.
    public static func spokenCentimeters(_ millimetres: Double, locale: Locale = french) -> String {
        let centimetres = millimetres / 10
        return "\(nombre(centimetres, locale: locale)) centimètre\(abs(centimetres) < 2 ? "" : "s")"
    }

    /// Phrase complète pour VoiceOver :
    /// « 12,4 centimètres de long, 8,6 centimètres de large et 4,0 centimètres de haut ».
    public static func spoken(_ dimensions: Dimensions, locale: Locale = french) -> String {
        "\(spokenCentimeters(dimensions.lengthMM, locale: locale)) de long, "
            + "\(spokenCentimeters(dimensions.widthMM, locale: locale)) de large et "
            + "\(spokenCentimeters(dimensions.heightMM, locale: locale)) de haut"
    }

    private static func nombre(_ valeur: Double, locale: Locale) -> String {
        valeur.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    }
}
