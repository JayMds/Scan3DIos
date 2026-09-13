import SwiftUI

/// Phase `failed`. Si l'échec vient de la reconstruction, les photos sont
/// encore là : « Reprendre » relance (le checkpoint accélère la reprise).
/// « Abandonner » / « Fermer » supprime le dossier du scan.
struct EchecView: View {
    let message: String
    var reprendre: (() -> Void)? = nil
    let fermer: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Le scan a échoué", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let reprendre {
                Button("Reprendre la reconstruction", action: reprendre)
                    .buttonStyle(.borderedProminent)
                Button("Abandonner", role: .destructive, action: fermer)
                    .buttonStyle(.bordered)
            } else {
                Button("Fermer", action: fermer)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
    }
}

#Preview {
    EchecView(message: "Session interrompue.", reprendre: {}) {}
}
