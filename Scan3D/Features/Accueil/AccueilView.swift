import SwiftUI
import RealityKit

/// Écran d'accueil provisoire : vérifie que l'appareil sait scanner.
/// La tranche 1 remplacera le contenu par le parcours de scan guidé.
struct AccueilView: View {
    var body: some View {
        NavigationStack {
            Group {
                if appareilCompatible {
                    ContentUnavailableView(
                        "Prêt à scanner",
                        systemImage: "cube.transparent",
                        description: Text("Le scan guidé arrive avec la tranche 1.")
                    )
                } else {
                    ContentUnavailableView(
                        "Appareil non compatible",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Le scan 3D nécessite un iPhone ou un iPad équipé du capteur LiDAR.")
                    )
                }
            }
            .navigationTitle("Scan3D")
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
