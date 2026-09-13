import SwiftUI
import Scan3DCore

/// Conteneur du parcours de scan : affiche la sous-vue de la phase courante
/// et porte le bouton Annuler commun (≈ le `_layout.tsx` d'un groupe d'écrans
/// expo-router). Présenté en plein écran depuis l'accueil.
struct ScanFlowView: View {
    @State private var model = ScanFlowModel()
    @State private var confirmerAnnulation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            contenu
                .navigationTitle(titre)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if model.scanTermine {
                            // Le modèle reste dans Scans/<UUID>/ (bibliothèque en tranche 2).
                            Button("Fermer") { dismiss() }
                        } else {
                            Button("Annuler") { demanderAnnulation() }
                        }
                    }
                }
                .confirmationDialog(
                    "Abandonner ce scan ?",
                    isPresented: $confirmerAnnulation,
                    titleVisibility: .visible
                ) {
                    Button("Abandonner le scan", role: .destructive) {
                        Task { await annuler() }
                    }
                } message: {
                    Text(model.reprisePossible
                         ? "Les photos seront supprimées : la reconstruction ne pourra plus être reprise."
                         : "Les photos déjà prises seront supprimées.")
                }
                .alert("Impossible de démarrer", isPresented: erreurPresente, presenting: model.erreur) { _ in
                    Button("OK") {}
                } message: { erreur in
                    Text(erreur.localizedDescription)
                }
        }
        .onChange(of: scenePhase) { _, nouvelle in
            if nouvelle == .active { model.rafraichirAutorisation() }
        }
        // Filet de sécurité : quel que soit le chemin de sortie, l'écran
        // retrouve sa mise en veille.
        .onDisappear { VeilleEcran.empecher(false) }
    }

    @ViewBuilder
    private var contenu: some View {
        if model.autorisationCamera == .refusee {
            CameraRefuseeView()
        } else {
            // Le `switch` doit couvrir toutes les phases : ajouter une phase
            // dans Scan3DCore sans lui donner d'écran ne compile pas.
            switch model.phase {
            case .preparation:
                PreparationView(model: model)
            case .detection, .capture:
                if let capture = model.capture {
                    CaptureView(model: model, controller: capture)
                } else {
                    ProgressView("Ouverture de la caméra…")
                }
            case .passComplete:
                if let capture = model.capture {
                    FinDePasseView(model: model, controller: capture)
                } else {
                    ProgressView()
                }
            case .reconstruction:
                ReconstructionView(model: model)
            case .preview:
                // Le modèle reste dans Scans/<UUID>/ pour la bibliothèque (tranche 2).
                ApercuPlaceholderView(tailleModele: model.tailleModele) {
                    dismiss()
                }
            case .failed(let message):
                EchecView(message: message, reprendre: reprise) {
                    Task { await annuler() }
                }
            }
        }
    }

    /// « Reprendre » n'a de sens qu'après un échec de reconstruction.
    private var reprise: (() -> Void)? {
        guard model.reprisePossible else { return nil }
        return { Task { await model.reprendreReconstruction() } }
    }

    private var titre: String {
        switch model.phase {
        case .preparation: "Préparation"
        case .detection: "Détection"
        case .capture: "Capture"
        case .passComplete: "Passe terminée"
        case .reconstruction: "Reconstruction"
        case .preview: "Aperçu"
        case .failed: "Erreur"
        }
    }

    /// Pont entre « il y a une erreur » (optionnel) et « l'alerte est visible » (booléen).
    private var erreurPresente: Binding<Bool> {
        Binding(
            get: { model.erreur != nil },
            set: { visible in if !visible { model.erreur = nil } }
        )
    }

    private func demanderAnnulation() {
        if model.annulationDemandeConfirmation {
            confirmerAnnulation = true
        } else {
            Task { await annuler() }
        }
    }

    private func annuler() async {
        await model.annuler()
        dismiss()
    }
}

#Preview {
    ScanFlowView()
}
