#if !targetEnvironment(simulator)
import SwiftUI
import RealityKit
import Scan3DCore

/// Écrans 3 et 4 : la caméra guidée de RealityKit (viseur, boîte englobante,
/// cadran de progression) avec, par-dessus, nos conseils et nos boutons.
struct CaptureView: View {
    let model: ScanFlowModel
    let controller: CaptureController
    @State private var detectionRefusee = false

    /// En dessous, la reconstruction a peu de chances d'aboutir.
    static let minimumPhotosPourTerminer = 20

    var body: some View {
        if let session = controller.session {
            ZStack(alignment: .bottom) {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()
                commandes(session.state)
            }
            .overlay(alignment: .top) { bandeauConseil }
            // Le guidage ne repose jamais sur le visuel seul : haptique à
            // chaque nouveau conseil, et annonce VoiceOver en plus.
            .sensoryFeedback(.warning, trigger: controller.conseil) { _, nouveau in nouveau != nil }
            .onChange(of: controller.conseil) { _, nouveau in
                if let nouveau {
                    AccessibilityNotification.Announcement(nouveau.texte).post()
                }
            }
        } else {
            ProgressView("Ouverture de la caméra…")
        }
    }

    @ViewBuilder
    private var bandeauConseil: some View {
        if let conseil = controller.conseil {
            Text(conseil.texte)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(conseil.blocksCapture ? Color.red.opacity(0.85) : Color.black.opacity(0.65), in: Capsule())
                .foregroundStyle(.white)
                .padding(.top, 8)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func commandes(_ etat: ObjectCaptureSession.CaptureState) -> some View {
        VStack(spacing: 12) {
            switch etat {
            case .initializing:
                ProgressView("Initialisation de la caméra…")
            case .ready:
                Text("Centrez l'objet dans le viseur, puis continuez.")
                if detectionRefusee {
                    Text("Objet non détecté : rapprochez-vous et réessayez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Continuer") {
                    detectionRefusee = !model.commencerDetection()
                }
                .buttonStyle(.borderedProminent)
            case .detecting:
                Text("Ajustez la boîte pour qu'elle entoure tout l'objet.")
                HStack {
                    Button("Recommencer") { model.reinitialiserDetection() }
                        .buttonStyle(.bordered)
                    Button("Commencer la capture") { model.commencerCapture() }
                        .buttonStyle(.borderedProminent)
                }
            case .capturing:
                switch model.mode {
                case .orbit: commandesOrbite
                case .turntable: commandesPlateau
                }
            case .finishing:
                ProgressView("Enregistrement des photos…")
            case .completed, .failed:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
        .font(.callout)
        .multilineTextAlignment(.center)
        .controlSize(.large)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    /// Mode orbite : RealityKit prend les photos, on montre l'avancement.
    @ViewBuilder
    private var commandesOrbite: some View {
        Text("\(controller.nombrePhotos) / \(controller.maximumPhotos) photos")
            .font(.headline.monospacedDigit())
            .accessibilityLabel("\(controller.nombrePhotos) photos prises sur \(controller.maximumPhotos)")
        Text("Tournez lentement autour de l'objet jusqu'à remplir le cadran.")
        if controller.nombrePhotos >= Self.minimumPhotosPourTerminer {
            // Secours si le tour complet est impossible (objet contre un mur…).
            Button("Terminer sans finir le tour") { model.terminerCapture() }
                .buttonStyle(.bordered)
        }
    }

    /// Mode plateau : l'utilisateur déclenche chaque photo et déclare le tour fini.
    @ViewBuilder
    private var commandesPlateau: some View {
        let photos = model.photosCeTour
        ProgressView(value: CaptureMode.turntableTurnProgress(shotsThisTurn: photos)) {
            Text("\(photos) / \(CaptureMode.turntableShotsPerTurn) photos ce tour")
                .font(.headline.monospacedDigit())
        }
        .accessibilityLabel("\(photos) photos sur \(CaptureMode.turntableShotsPerTurn) pour ce tour")
        Text("Tournez le plateau d'environ \(CaptureMode.turntableDegreesPerShot)°, puis prenez une photo.")
        HStack {
            Button("Tour terminé") { model.terminerTour() }
                .buttonStyle(.bordered)
                .disabled(photos < CaptureMode.turntableMinimumShotsPerTurn)
            Button {
                model.prendrePhoto()
            } label: {
                Label("Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.photoPossible)
        }
        // Retour non visuel à chaque photo prise (VoiceOver n'a pas le compteur sous les yeux).
        .onChange(of: controller.nombrePhotos) { _, _ in
            AccessibilityNotification.Announcement("\(model.photosCeTour) photos").post()
        }
    }
}
#endif
