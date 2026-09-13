import SwiftUI

/// Écran 6 provisoire : prouve que les photos sont enregistrées et donne
/// leur poids réel, pour calibrer le seuil d'espace disque. L'étape 3 le
/// remplace par la vraie reconstruction.
struct ReconstructionPlaceholderView: View {
    /// « 214 photos, 830 Mo », ou nil tant que la mesure n'est pas faite.
    let bilan: String?

    var body: some View {
        ContentUnavailableView {
            Label("Capture terminée", systemImage: "photo.stack")
        } description: {
            Text(description)
        }
    }

    private var description: String {
        let photos = bilan.map { "\($0) enregistrées dans le dossier du scan. " } ?? ""
        return photos + "La reconstruction du modèle 3D arrive à l'étape 3. « Annuler » supprime les photos."
    }
}

#Preview {
    ReconstructionPlaceholderView(bilan: "214 photos, 830 Mo")
}
