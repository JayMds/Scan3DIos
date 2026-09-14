import Testing
@testable import Scan3DCore

@Suite("Dimensions")
struct DimensionsTests {

    @Test("Y est la hauteur ; la plus grande cote horizontale est la longueur")
    func axes() {
        let boite = BoundingBox(min: [0, 0, 0], max: [0.03, 0.2, 0.12])
        let dimensions = Dimensions(boundingBox: boite)
        #expect(abs(dimensions.lengthMM - 120) < 1e-3)
        #expect(abs(dimensions.widthMM - 30) < 1e-3)
        #expect(abs(dimensions.heightMM - 200) < 1e-3)
    }

    @Test("Une taille hors de 1 mm – 5 m signale une probable erreur d'unité", arguments: [
        (0.5, false), (1.0, true), (50.0, true), (5_000.0, true), (5_001.0, false),
    ])
    func plausibilite(plusGrandeCote: Double, attendu: Bool) {
        let dimensions = Dimensions(lengthMM: plusGrandeCote, widthMM: 0.2, heightMM: 0.2)
        #expect(dimensions.isPlausible == attendu)
    }

    @Test("Millimètres à une décimale, virgule française, sans séparateur de milliers")
    func millimetres() {
        #expect(DimensionsFormatter.millimeters(124) == "124,0\u{00A0}mm")
        #expect(DimensionsFormatter.millimeters(85.56) == "85,6\u{00A0}mm")
        #expect(DimensionsFormatter.millimeters(12_345.6) == "12345,6\u{00A0}mm")
    }

    @Test("Format compact longueur × largeur × hauteur")
    func compact() {
        let dimensions = Dimensions(lengthMM: 124, widthMM: 85.6, heightMM: 40.2)
        #expect(DimensionsFormatter.compact(dimensions) == "124,0 × 85,6 × 40,2\u{00A0}mm")
    }

    @Test("Phrase VoiceOver en centimètres, avec accord du pluriel")
    func phrase() {
        let dimensions = Dimensions(lengthMM: 124, widthMM: 85.6, heightMM: 15)
        #expect(DimensionsFormatter.spoken(dimensions)
                == "12,4 centimètres de long, 8,6 centimètres de large et 1,5 centimètre de haut")
    }
}
