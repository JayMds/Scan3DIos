import Foundation
import Testing
@testable import Scan3DCore

@Suite("Phases du parcours de scan")
struct ScanPhaseTests {
    static let modele = URL(filePath: "/tmp/modele.usdz")

    /// Un échantillon de sauts qui violent le parcours de `TRANCHE-1.md`.
    static let sautsInterdits: [(ScanPhase, ScanPhase)] = [
        (.preparation, .capture),
        (.preparation, .failed(message: "x")),
        (.detection, .reconstruction(progress: 0)),
        (.capture, .reconstruction(progress: 0)),   // il faut d'abord finir la passe
        (.capture, .preview(model: modele)),
        (.passComplete, .preview(model: modele)),
        (.passComplete, .failed(message: "x")),
        (.reconstruction(progress: 0.5), .capture),
        (.preview(model: modele), .capture),
        (.preview(model: modele), .failed(message: "x")),
        (.failed(message: "x"), .capture),
    ]

    static let confirmations: [(ScanPhase, Bool)] = [
        (.preparation, false),
        (.detection, false),
        (.capture, true),
        (.passComplete, true),
        (.reconstruction(progress: 0.3), true),
        (.preview(model: modele), false),
        (.failed(message: "x"), false),
    ]

    @Test("Suit le parcours nominal de bout en bout, deuxième passe comprise")
    func parcoursNominal() throws {
        var phase = ScanPhase.preparation
        phase = try phase.transition(to: .detection)
        phase = try phase.transition(to: .capture)
        phase = try phase.transition(to: .passComplete)
        phase = try phase.transition(to: .capture)                    // on retourne l'objet
        phase = try phase.transition(to: .passComplete)
        phase = try phase.transition(to: .reconstruction(progress: 0))
        phase = try phase.transition(to: .reconstruction(progress: 0.5))
        phase = try phase.transition(to: .preview(model: Self.modele))
        #expect(phase == .preview(model: Self.modele))
    }

    @Test("Refuse les sauts interdits", arguments: ScanPhaseTests.sautsInterdits)
    func refuseLesSautsInterdits(origine: ScanPhase, cible: ScanPhase) {
        #expect(!origine.canTransition(to: cible))
        #expect(throws: ScanPhaseError.invalidTransition(from: origine, to: cible)) {
            _ = try origine.transition(to: cible)
        }
    }

    @Test("L'échec n'est possible que depuis la détection, la capture ou la reconstruction")
    func sourcesDEchec() {
        let echec = ScanPhase.failed(message: "Session interrompue")
        #expect(ScanPhase.detection.canTransition(to: echec))
        #expect(ScanPhase.capture.canTransition(to: echec))
        #expect(ScanPhase.reconstruction(progress: 0.2).canTransition(to: echec))
        #expect(!ScanPhase.preparation.canTransition(to: echec))
        #expect(!ScanPhase.passComplete.canTransition(to: echec))
    }

    @Test("« Reprendre » relance la reconstruction depuis un échec")
    func reprise() throws {
        let phase = try ScanPhase.failed(message: "x").transition(to: .reconstruction(progress: 0))
        #expect(phase == .reconstruction(progress: 0))
    }

    @Test("Annuler demande confirmation seulement si des photos ou un calcul seraient perdus",
          arguments: ScanPhaseTests.confirmations)
    func confirmationAnnulation(phase: ScanPhase, attendu: Bool) {
        #expect(phase.cancellationNeedsConfirmation == attendu)
    }
}
