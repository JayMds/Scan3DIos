import SwiftUI
import RealityKit
import Scan3DCore

/// Écran racine : vérifie que l'appareil sait scanner, puis héberge la
/// bibliothèque, la navigation vers le détail d'un scan et le parcours de
/// scan en plein écran.
struct AccueilView: View {
    @State private var bibliotheque = BibliothequeModel()
    /// Pile de navigation pilotée par l'état (≈ `router.push` d'expo-router,
    /// mais c'est un tableau qu'on modifie) : ouvrir un détail = y ajouter un scan.
    @State private var chemin: [ScanLayout] = []
    @State private var nouveauScan = false
    /// Renseigné par le parcours juste avant sa fermeture.
    @State private var scanTermine: ScanLayout?

    var body: some View {
        NavigationStack(path: $chemin) {
            Group {
                if appareilCompatible {
                    BibliothequeView(model: bibliotheque) {
                        nouveauScan = true
                    }
                    .navigationTitle("Mes scans")
                } else {
                    ContentUnavailableView(
                        "Appareil non compatible",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Le scan 3D nécessite un iPhone ou un iPad équipé du capteur LiDAR.")
                    )
                    .navigationTitle("Scan3D")
                }
            }
            .navigationDestination(for: ScanLayout.self) { layout in
                DetailScanView(bibliotheque: bibliotheque, layout: layout)
            }
            // Plein écran : le parcours est immersif (caméra) et a son propre
            // bouton Annuler ; pas de retour arrière par glissement.
            // `onDismiss` : appelé une fois l'animation de fermeture finie,
            // moment sûr pour naviguer vers le détail du nouveau scan.
            .fullScreenCover(isPresented: $nouveauScan, onDismiss: apresParcours) {
                ScanFlowView(store: bibliotheque.store) { layout in
                    scanTermine = layout
                }
            }
        }
        // Premier inventaire : récupère les scans de la tranche 1 et purge les
        // dossiers de captures interrompues.
        .task {
            if appareilCompatible { await bibliotheque.charger() }
        }
    }

    /// Relit la bibliothèque (le nouveau scan arrive en tête), puis ouvre son
    /// détail s'il a été enregistré.
    private func apresParcours() {
        Task {
            await bibliotheque.charger()
            guard let layout = scanTermine else { return }
            scanTermine = nil
            chemin = [layout]
            AccessibilityNotification.Announcement("Scan enregistré dans la bibliothèque").post()
        }
    }

    /// Le simulateur n'a ni caméra ni LiDAR : on court-circuite la vérification
    /// pour que l'app compile et s'affiche quand même dans le simulateur.
    private var appareilCompatible: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ObjectCaptureSession.isSupported
        #endif
    }
}

#Preview {
    AccueilView()
}
