#if !targetEnvironment(simulator)
import SwiftUI
import RealityKit

/// Écran 5 : la passe est complète. On montre le nuage de points capturé
/// jusqu'ici et on propose la suite : autre hauteur, retourner, ou terminer.
struct FinDePasseView: View {
    let model: ScanFlowModel
    let controller: CaptureController

    var body: some View {
        VStack(spacing: 0) {
            if let session = controller.session {
                ObjectCapturePointCloudView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Aperçu des points capturés, \(controller.nombrePhotos) photos")
            }
            VStack(spacing: 12) {
                Text("\(controller.nombrePhotos) photos prises")
                    .font(.headline)
                Text("Une passe à une autre hauteur ne déplace pas l'objet : elle est sans risque. Le retournement, lui, capte le dessous mais demande des repères visuels pour se recoller.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Nouvelle passe à une autre hauteur") { model.nouvellePasse() }
                    .buttonStyle(.bordered)
                if controller.objetRetournable {
                    Button("Retourner l'objet, puis continuer") { model.nouvellePasseApresRetournement() }
                        .buttonStyle(.bordered)
                } else {
                    Text("Objet peu texturé : évitez de le retourner, changez plutôt de hauteur.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Terminer et reconstruire") { model.terminerCapture() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}
#endif
