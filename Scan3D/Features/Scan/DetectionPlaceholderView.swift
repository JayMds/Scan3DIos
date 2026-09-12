import SwiftUI

/// Écran 3 provisoire : prouve que le dossier du scan existe. L'étape 2 le
/// remplace par la caméra et la boîte englobante (`ObjectCaptureView`).
struct DetectionPlaceholderView: View {
    let identifiant: UUID?

    var body: some View {
        ContentUnavailableView {
            Label("Détection de l'objet", systemImage: "viewfinder")
        } description: {
            Text("Le dossier de ce scan est prêt et protégé. La caméra et la boîte englobante arrivent à l'étape 2.")
        } actions: {
            if let identifiant {
                // Les 8 premiers caractères suffisent pour retrouver le scan
                // dans Console (journal « Scan <UUID> créé »).
                Text("Scan \(identifiant.uuidString.prefix(8))")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    DetectionPlaceholderView(identifiant: UUID())
}
