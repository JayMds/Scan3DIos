#if targetEnvironment(simulator)
import SwiftUI
import Scan3DCore

// Doublures pour le simulateur, qui n'a ni caméra ni Object Capture. Même
// interface que les vrais types (CaptureController.swift, CaptureView.swift,
// FinDePasseView.swift) pour que ScanFlowModel et ScanFlowView compilent à
// l'identique. L'accueil bloque de toute façon l'accès au parcours.

@MainActor @Observable
final class CaptureController {
    enum Evenement: Equatable {
        case captureCommencee
        case passeTerminee
        case terminee
        case echec(String)
    }

    private let onEvenement: @MainActor (Evenement) -> Void

    var nombrePhotos: Int { 0 }
    var maximumPhotos: Int { 0 }
    var conseil: CaptureHint? { nil }
    var objetRetournable: Bool { false }

    init(layout: ScanLayout, onEvenement: @escaping @MainActor (Evenement) -> Void) {
        self.onEvenement = onEvenement
    }

    func demarrer() {
        onEvenement(.echec("Le scan nécessite un iPhone réel : le simulateur n'a pas de caméra."))
    }

    func commencerDetection() -> Bool { false }
    func reinitialiserDetection() {}
    func commencerCapture() {}
    func nouvellePasse() {}
    func nouvellePasseApresRetournement() {}
    func terminer() {}
    func annuler() async {}
}

struct CaptureView: View {
    let model: ScanFlowModel
    let controller: CaptureController

    var body: some View {
        ContentUnavailableView(
            "Simulateur",
            systemImage: "exclamationmark.triangle",
            description: Text("La capture ne fonctionne que sur un iPhone.")
        )
    }
}

struct FinDePasseView: View {
    let model: ScanFlowModel
    let controller: CaptureController

    var body: some View {
        CaptureView(model: model, controller: controller)
    }
}
#endif
