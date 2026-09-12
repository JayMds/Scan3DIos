import SwiftUI

/// Permission caméra refusée : on explique, on rassure sur l'usage des
/// images, et on mène aux Réglages — l'app ne plante jamais pour ça.
struct CameraRefuseeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Caméra non autorisée", systemImage: "video.slash")
        } description: {
            Text("Scan3D a besoin de la caméra pour photographier l'objet sous tous les angles. Les images restent sur votre iPhone et ne sont jamais envoyées.")
        } actions: {
            if let reglages = URL(string: UIApplication.openSettingsURLString) {
                Link("Ouvrir les Réglages", destination: reglages)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

#Preview {
    CameraRefuseeView()
}
