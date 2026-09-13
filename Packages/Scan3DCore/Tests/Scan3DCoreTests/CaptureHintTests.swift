import Testing
@testable import Scan3DCore

@Suite("Conseils de capture")
struct CaptureHintTests {

    @Test("Aucun conseil actif → rien à annoncer")
    func vide() {
        #expect(CaptureHint.mostUrgent(in: []) == nil)
    }

    @Test("Un seul conseil actif → c'est lui")
    func unique() {
        #expect(CaptureHint.mostUrgent(in: [.movingTooFast]) == .movingTooFast)
    }

    @Test("Le problème bloquant passe avant l'avertissement")
    func priorite() {
        #expect(CaptureHint.mostUrgent(in: [.objectTooClose, .environmentTooDark, .movingTooFast]) == .environmentTooDark)
        #expect(CaptureHint.mostUrgent(in: [.environmentLowLight, .objectTooFar]) == .objectTooFar)
        #expect(CaptureHint.mostUrgent(in: [.objectNotFlippable, .overCapturing]) == .overCapturing)
    }

    @Test("Chaque conseil a une priorité unique et croissante dans l'ordre de déclaration")
    func prioritesUniques() {
        let priorites = CaptureHint.allCases.map(\.priority)
        #expect(priorites == Array(0..<CaptureHint.allCases.count))
    }

    @Test("Seuls l'obscurité et le hors-champ bloquent la capture")
    func bloquants() {
        let bloquants = Set(CaptureHint.allCases.filter(\.blocksCapture))
        #expect(bloquants == [.environmentTooDark, .outOfFieldOfView])
    }
}
