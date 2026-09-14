import SwiftUI
// `.quickLookPreview` est fourni par QuickLook, pas par SwiftUI.
import QuickLook
import Scan3DCore

/// Écran 7 : les cotes en millimètres d'abord — c'est ce qui intéresse un
/// utilisateur d'imprimante 3D —, puis la visionneuse 3D native d'Apple.
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
                    Label("Le modèle n'a pas pu être mesuré. Vous pouvez tout de même l'afficher en 3D.",
                          systemImage: "exclamationmark.triangle")
                }
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
                modeleAffiche = modele
            } label: {
                Label("Voir en 3D", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Ouvre la visionneuse 3D, avec un mode réalité augmentée à l'échelle réelle.")

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
}
