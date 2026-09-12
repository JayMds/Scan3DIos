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
