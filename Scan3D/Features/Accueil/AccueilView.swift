import SwiftUI
import RealityKit

/// Écran d'accueil : vérifie que l'appareil sait scanner et lance le parcours.
struct AccueilView: View {
    @State private var nouveauScan = false

    var body: some View {
        NavigationStack {
            Group {
                if appareilCompatible {
                    ContentUnavailableView {
                        Label("Prêt à scanner", systemImage: "cube.transparent")
                    } description: {
                        Text("Posez l'objet sur une table dégagée, puis lancez un nouveau scan.")
                    } actions: {
                        Button {
                            nouveauScan = true
                        } label: {
                            Label("Nouveau scan", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    ContentUnavailableView(
                        "Appareil non compatible",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Le scan 3D nécessite un iPhone ou un iPad équipé du capteur LiDAR.")
                    )
                }
            }
            .navigationTitle("Scan3D")
            // Plein écran : le parcours est immersif (caméra) et a son propre
            // bouton Annuler ; pas de retour arrière par glissement.
            .fullScreenCover(isPresented: $nouveauScan) {
                ScanFlowView()
            }
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
