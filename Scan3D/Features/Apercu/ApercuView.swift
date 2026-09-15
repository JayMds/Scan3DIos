import SwiftUI
// `.quickLookPreview` est fourni par QuickLook, pas par SwiftUI.
import QuickLook
import Scan3DCore

/// Écrans 7 et 8 : les cotes en millimètres d'abord — c'est ce qui intéresse
/// un utilisateur d'imprimante 3D —, la visionneuse 3D d'Apple, puis l'export
/// STL par la feuille de partage.
struct ApercuView: View {
    let model: ScanFlowModel
    let modele: URL
    let terminer: () -> Void
    /// Non nil → Quick Look est affiché ; il remet la valeur à nil en se fermant.
    @State private var modeleAffiche: URL?

    var body: some View {
        List {
            switch model.mesure {
            case .enCours:
                Section {
                    ProgressView("Mesure du modèle…")
                        .frame(maxWidth: .infinity)
                }
            case .reussie(let dimensions, let triangles):
                sectionDimensions(dimensions, triangles: triangles)
            case .echec:
                Section {
                    Label("Le modèle n'a pas pu être mesuré ni exporté. Vous pouvez tout de même l'afficher en 3D.",
                          systemImage: "exclamationmark.triangle")
                }
            }

            Section {
                Button {
                    modeleAffiche = modele
                } label: {
                    Label("Voir en 3D", systemImage: "cube.transparent")
                }
                .accessibilityHint("Ouvre la visionneuse 3D, avec un mode réalité augmentée à l'échelle réelle.")
            }
        }
        .safeAreaInset(edge: .bottom) { boutons }
        // Visionneuse système : rotation, zoom, VoiceOver et mode AR à l'échelle
        // réelle fournis par iOS (décision D3).
        .quickLookPreview($modeleAffiche)
        // `initial: true` : la mesure peut finir avant même que l'écran s'affiche.
        .onChange(of: model.mesure, initial: true) { _, mesure in
            if case .reussie(let dimensions, _) = mesure {
                AccessibilityNotification.Announcement("Modèle prêt : \(DimensionsFormatter.spoken(dimensions))").post()
            }
        }
        .alert("Export impossible", isPresented: erreurExportPresente) {
            Button("OK") {}
        } message: {
            Text(model.erreurExport ?? "")
        }
    }

    private func sectionDimensions(_ dimensions: Dimensions, triangles: Int) -> some View {
        Section {
            Text(DimensionsFormatter.compact(dimensions))
                .font(.title.bold())
                .monospacedDigit()
                .accessibilityLabel(DimensionsFormatter.spoken(dimensions))
            ligne("Longueur", dimensions.lengthMM)
            ligne("Largeur", dimensions.widthMM)
            ligne("Hauteur", dimensions.heightMM)
            if !dimensions.isPlausible {
                Label {
                    Text("Dimensions inhabituelles : l'échelle du modèle est peut-être fausse. Vérifiez avant d'imprimer.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Dimensions")
        } footer: {
            Text(piedDePage(triangles: triangles))
        }
    }

    private func ligne(_ titre: String, _ millimetres: Double) -> some View {
        LabeledContent(titre, value: DimensionsFormatter.millimeters(millimetres))
            .monospacedDigit()
            .accessibilityValue(DimensionsFormatter.spokenCentimeters(millimetres))
    }

    private func piedDePage(triangles: Int) -> String {
        let nombre = triangles.formatted(.number.locale(DimensionsFormatter.french))
        let taille = model.tailleModele.map { ", \($0)" } ?? ""
        return "Cotes de la boîte englobante du modèle (\(nombre) triangles\(taille)). Contrôlez au pied à coulisse avant d'imprimer une pièce ajustée."
    }

    private var boutons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await exporter() }
            } label: {
                Group {
                    if model.exportEnCours {
                        ProgressView()
                            .accessibilityLabel("Préparation du fichier STL")
                    } else {
                        Label("Exporter en STL", systemImage: "square.and.arrow.up")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.exportPossible || model.exportEnCours)
            .accessibilityHint("Crée un fichier STL en millimètres et ouvre la feuille de partage : AirDrop, Fichiers, application de votre imprimante.")

            Button(action: terminer) {
                Text("Terminer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    /// Écrit le fichier, ouvre la feuille de partage, et supprime le fichier à
    /// sa fermeture — que l'utilisateur ait partagé ou annulé.
    private func exporter() async {
        guard let fichier = await model.preparerExportSTL() else { return }
        let ouverte = FeuilleDePartage.presenter(fichier) { partage in
            if partage {
                AccessibilityNotification.Announcement("Fichier STL partagé").post()
            }
            Task { await model.exportTermine(fichier, partage: partage) }
        }
        if !ouverte {
            await model.exportTermine(fichier, partage: false)
        }
    }

    private var erreurExportPresente: Binding<Bool> {
        Binding(
            get: { model.erreurExport != nil },
            set: { visible in if !visible { model.effacerErreurExport() } }
        )
    }
}
