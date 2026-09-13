import SwiftUI

/// Écran 7 provisoire : prouve que `modele.usdz` existe. L'étape 4 le
/// remplace par les dimensions et la visionneuse 3D.
struct ApercuPlaceholderView: View {
    /// « 9,8 Mo », ou nil tant que la mesure n'est pas faite.
    let tailleModele: String?
    let terminer: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Modèle prêt", systemImage: "checkmark.circle")
        } description: {
            Text(description)
        } actions: {
            Button("Terminer", action: terminer)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var description: String {
        let taille = tailleModele.map { " (\($0))" } ?? ""
        return "Le fichier modele.usdz\(taille) est enregistré ; les photos ont été supprimées. Les dimensions et l'aperçu 3D arrivent à l'étape 4."
    }
}

#Preview {
    ApercuPlaceholderView(tailleModele: "9,8 Mo") {}
}
