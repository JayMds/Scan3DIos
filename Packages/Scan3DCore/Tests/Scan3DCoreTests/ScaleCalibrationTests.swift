import Foundation
import Testing
@testable import Scan3DCore

@Suite("Calibrage d'échelle")
struct ScaleCalibrationTests {

    @Test("Recale une cote mesurée sur la cote réelle")
    func recaleLaCote() throws {
        let calibration = try ScaleCalibration(measuredMM: 84.0, actualMM: 85.60)
        #expect(abs(calibration.apply(toMM: 84.0) - 85.60) < 1e-9)
    }

    @Test("Refuse les mesures nulles, négatives ou non finies",
          arguments: [0.0, -12.0, .infinity, .nan])
    func refuseMesuresInvalides(valeur: Double) {
        #expect(throws: CalibrationError.invalidMeasurement) {
            _ = try ScaleCalibration(measuredMM: valeur, actualMM: 85.60)
        }
    }

    @Test("Refuse un facteur aberrant (ex. saisie en cm au lieu de mm)")
    func refuseFacteurAberrant() {
        #expect(throws: CalibrationError.self) {
            _ = try ScaleCalibration(measuredMM: 85.60, actualMM: 8.56)
        }
    }
}

@Suite("Unités")
struct UnitsTests {

    @Test("Mètres (RealityKit) vers millimètres (slicer)")
    func metresVersMillimetres() {
        // Jamais de `==` sur des Double calculés : en virgule flottante,
        // 0.1234 × 1000 donne 123.39999999999999. On compare avec une tolérance.
        #expect(abs(Units.millimeters(fromMeters: 0.1234) - 123.4) < 1e-9)
    }

    @Test("La carte bancaire respecte le format ID-1")
    func carteBancaire() {
        #expect(ReferenceObject.creditCard.widthMM == 85.60)
        #expect(ReferenceObject.creditCard.heightMM == 53.98)
    }
}

@Suite("Saisie d'une cote en millimètres")
struct MillimeterInputTests {

    @Test("Accepte la virgule française, le point, et les espaces du formatage", arguments: [
        ("184", 184.0), ("184,0", 184.0), ("184.0", 184.0), ("  184,0  ", 184.0),
        ("1 234,5", 1234.5), ("1\u{00A0}234,5", 1234.5), ("0,1", 0.1), (".5", 0.5),
    ])
    func saisiesValides(texte: String, attendu: Double) {
        #expect(MillimeterInput.parse(texte) == attendu)
    }

    @Test("Refuse tout le reste", arguments: [
        "", "   ", "abc", "-3", "0", "0,05", "12000", "1e3", "184,0,0", "18,4mm", "½", "٧",
    ])
    func saisiesRefusees(texte: String) {
        #expect(MillimeterInput.parse(texte) == nil)
    }
}

@Suite("Application du calibrage")
struct CalibrationApplicationTests {
    static let brutes = Dimensions(lengthMM: 189.2, widthMM: 163, heightMM: 56.8)

    @Test("Les cotes affichées suivent le facteur, les cotes brutes ne bougent pas")
    func cotesCalibrees() throws {
        let calibration = try ScaleCalibration(measuredMM: 177.9, actualMM: 184)
        var fiche = try ScanRecord(id: UUID(), name: "Boîte", createdAt: .now,
                                   triangleCount: 1_000, dimensions: Self.brutes)
        #expect(fiche.calibratedDimensions == Self.brutes)

        fiche.calibration = calibration
        let corrigees = fiche.calibratedDimensions
        #expect(abs(corrigees.lengthMM - 189.2 * calibration.factor) < 1e-9)
        #expect(fiche.dimensions == Self.brutes)
        // Facteur 184 / 177,9 ≈ 1,034 : la longueur affichée gagne ~6,5 mm.
        #expect(abs(corrigees.lengthMM - 195.7) < 0.1)
    }

    @Test("Une mesure point à point se corrige du même facteur")
    func mesureCalibree() throws {
        let calibration = try ScaleCalibration(measuredMM: 177.9, actualMM: 184)
        let mesure = SegmentMeasurement(start: [0, 0, 0], end: [0.1779, 0, 0])
        // Tolérance au micron : les sommets sont des `Float`, pas des `Double`.
        #expect(abs(mesure.lengthMM - 177.9) < 1e-3)
        #expect(abs(mesure.lengthMM(calibratedBy: calibration) - 184) < 1e-3)
        #expect(mesure.lengthMM(calibratedBy: nil) == mesure.lengthMM)
    }

    @Test("Les références proposées sont celles de la carte bancaire")
    func references() {
        #expect(CalibrationReference.creditCardWidth.actualMM == 85.60)
        #expect(CalibrationReference.creditCardHeight.actualMM == 53.98)
        #expect(CalibrationReference.allCases.count == 2)
    }
}
