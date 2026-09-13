import SwiftUI
import Scan3DCore

/// Écran 6 : progression réelle, étape en cours, temps restant estimé.
/// Jamais d'attente muette : la barre avance, le texte change.
struct ReconstructionView: View {
    let model: ScanFlowModel

    var body: some View {
        let fraction = ReconstructionProgress.clampedFraction(model.progression)
        let restant = ReconstructionProgress.remainingTime(seconds: model.tempsRestant)

        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cube.transparent")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Reconstruction du modèle")
                .font(.title2.bold())
            if let bilan = model.bilanCapture {
                Text(bilan)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: fraction) {
                Text(model.etapeReconstruction ?? "Démarrage…")
            } currentValueLabel: {
                Text(ReconstructionProgress.percentText(fraction: model.progression))
                    .monospacedDigit()
            }
            .accessibilityLabel("Reconstruction, \(model.etapeReconstruction ?? "démarrage")")
            .accessibilityValue(ReconstructionProgress.spokenText(fraction: fraction, remainingSeconds: model.tempsRestant))

            if let restant {
                Text("Temps restant : \(restant.text)")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true) // déjà dans la valeur de la barre
            }
            Spacer()
            Label("Gardez l'app ouverte jusqu'à la fin.", systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}
