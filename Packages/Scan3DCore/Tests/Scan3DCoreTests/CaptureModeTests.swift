import Testing
@testable import Scan3DCore

@Suite("Modes de capture")
struct CaptureModeTests {

    @Test("En orbite, RealityKit déclenche les photos et le checkpoint sert")
    func orbite() {
        #expect(CaptureMode.orbit.usesAutomaticCapture)
        #expect(CaptureMode.orbit.usesCheckpoint)
    }

    @Test("Sur plateau, ni capture automatique ni checkpoint (iPhone immobile)")
    func plateau() {
        #expect(!CaptureMode.turntable.usesAutomaticCapture)
        #expect(!CaptureMode.turntable.usesCheckpoint)
    }

    @Test("Un tour = 36 photos, soit 10° entre deux")
    func objectifParTour() {
        #expect(CaptureMode.turntableShotsPerTurn == 36)
        #expect(CaptureMode.turntableDegreesPerShot == 10)
        #expect(CaptureMode.turntableMinimumShotsPerTurn < CaptureMode.turntableShotsPerTurn)
    }

    @Test("La progression du tour est bornée entre 0 et 1",
          arguments: [(0, 0.0), (18, 0.5), (36, 1.0), (50, 1.0), (-3, 0.0)])
    func progression(photos: Int, attendu: Double) {
        #expect(abs(CaptureMode.turntableTurnProgress(shotsThisTurn: photos) - attendu) < 1e-9)
    }
}
