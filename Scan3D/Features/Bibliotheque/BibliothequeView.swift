import SwiftUI
import Scan3DCore

/// Écran 1 de la tranche 2 : la liste des scans, du plus récent au plus
/// ancien. Vide, elle redevient l'invitation « Prêt à scanner » de la tranche 1.
struct BibliothequeView: View {
    let model: BibliothequeModel
    let nouveauScan: () -> Void
    /// Non nil → confirmation de suppression affichée.
    @State private var aSupprimer: BibliothequeModel.Element?
    @State private var erreur: BibliothequeErreur?

    var body: some View {
        Group {
            switch model.etat {
            case .chargement:
                ProgressView("Chargement des scans…")
            case .echec:
                ContentUnavailableView {
                    Label("Bibliothèque indisponible", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Les scans enregistrés n'ont pas pu être lus.")
                } actions: {
                    Button("Réessayer") {
                        Task { await model.charger() }
                    }
                    .buttonStyle(.bordered)
                }
            case .pret:
                if model.elements.isEmpty {
                    vide
                } else {
                    liste
                }
            }
        }
        .confirmationDialog(
            "Supprimer ce scan ?",
            isPresented: suppressionDemandee,
            titleVisibility: .visible,
            presenting: aSupprimer
        ) { element in
            Button("Supprimer le scan", role: .destructive) {
                Task { await supprimer(element) }
            }
        } message: { _ in
            Text(BibliothequeModel.messageSuppression)
        }
        .alert("Action impossible", isPresented: erreurPresente, presenting: erreur) { _ in
            Button("OK") {}
        } message: { erreur in
            Text(erreur.localizedDescription)
        }
    }

    private var vide: some View {
        ContentUnavailableView {
            Label("Prêt à scanner", systemImage: "cube.transparent")
        } description: {
            Text("Posez l'objet sur une table dégagée, puis lancez un nouveau scan. Vos scans apparaîtront ici.")
        } actions: {
            boutonNouveauScan
        }
    }

    private var liste: some View {
        List {
            ForEach(model.elements) { element in
                NavigationLink(value: element.layout) {
                    LigneScan(element: element)
                }
                // Glisser vers la gauche. SwiftUI expose aussi ces actions à
                // VoiceOver (rotor « Actions »), sans code supplémentaire.
                // Pas de `role: .destructive` : il ferait disparaître la ligne
                // avant même la confirmation.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        aSupprimer = element
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            boutonNouveauScan
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
        }
    }

    private var boutonNouveauScan: some View {
        Button(action: nouveauScan) {
            Label("Nouveau scan", systemImage: "camera.viewfinder")
                .frame(maxWidth: model.elements.isEmpty ? nil : .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func supprimer(_ element: BibliothequeModel.Element) async {
        do {
            try await model.supprimer(element.id)
            AccessibilityNotification.Announcement("Scan supprimé").post()
        } catch {
            self.erreur = error
        }
    }

    private var suppressionDemandee: Binding<Bool> {
        Binding(
            get: { aSupprimer != nil },
            set: { visible in if !visible { aSupprimer = nil } }
        )
    }

    private var erreurPresente: Binding<Bool> {
        Binding(
            get: { erreur != nil },
            set: { visible in if !visible { erreur = nil } }
        )
    }
}

/// Une ligne : nom, cotes, date (et « Calibré »). Lue en une phrase par VoiceOver.
private struct LigneScan: View {
    let element: BibliothequeModel.Element

    var body: some View {
        if let fiche = element.fiche {
            VStack(alignment: .leading, spacing: 4) {
                Text(fiche.name)
                    .font(.headline)
                Text(DimensionsFormatter.compact(fiche.dimensions))
                    .monospacedDigit()
                Text(fiche.sousTitre)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fiche.phraseAccessible)
        } else {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan illisible")
                        .font(.headline)
                    Text("Le modèle 3D n'a pas pu être mesuré.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}
