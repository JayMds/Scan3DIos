import SwiftUI

/// Phase `failed` : le message vient de la session de capture (plus tard, de
/// la reconstruction). « Fermer » supprime le dossier du scan, dont les
/// photos partielles ne servent à rien.
struct EchecView: View {
    let message: String
    let fermer: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Le scan a échoué", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Fermer", action: fermer)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

#Preview {
    EchecView(message: "Session interrompue.") {}
}
