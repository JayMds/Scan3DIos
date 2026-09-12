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
                .navigationTitle("Nouveau scan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { demanderAnnulation() }
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
                    Text("Les photos déjà prises seront supprimées.")
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
            case .detection:
                DetectionPlaceholderView(identifiant: model.layout?.id)
            case .capture, .passComplete, .reconstruction, .preview, .failed:
                // Écrans livrés par les étapes 2 à 4 du plan.
                ContentUnavailableView(
                    "Étape à venir",
                    systemImage: "hammer",
                    description: Text("Cet écran arrive dans une prochaine étape.")
                )
            }
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
