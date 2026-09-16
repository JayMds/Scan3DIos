import SwiftUI

/// Écran 2 : checklist des conditions qui font réussir un scan.
/// Cocher est facultatif (« coche / passe ») : le but est de prévenir la
/// cause n° 1 d'échec, les surfaces noires, brillantes ou transparentes.
struct PreparationView: View {
    let model: ScanFlowModel
    @State private var coches: Set<Conseil> = []

    var body: some View {
        List {
            Section {
                ForEach(Conseil.allCases) { conseil in
                    ligne(conseil)
                }
            } header: {
                Text("Avant de scanner")
            } footer: {
                Text("Astuce : un objet noir, brillant ou transparent se scanne mal. Un spray matifiant temporaire (ou un voile de talc) règle le problème.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await model.demarrer() }
            } label: {
                Group {
                    if model.demarrageEnCours {
                        ProgressView()
                    } else {
                        Label("Commencer le scan", systemImage: "camera.viewfinder")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.demarrageEnCours)
            .padding()
            .background(.bar)
        }
    }

    private func ligne(_ conseil: Conseil) -> some View {
        let coche = coches.contains(conseil)
        return Button {
            if coche { coches.remove(conseil) } else { coches.insert(conseil) }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conseil.titre)
                    Text(conseil.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: coche ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(coche ? Color.accentColor : Color.secondary)
            }
        }
        // Le texte reste de la couleur du texte, pas bleu comme un lien.
        .foregroundStyle(.primary)
        .accessibilityValue(coche ? "Coché" : "Non coché")
        .accessibilityHint("Touchez deux fois pour cocher ou décocher")
    }

    /// Les conditions qui font réussir un scan, par ordre d'importance.
    enum Conseil: CaseIterable, Identifiable {
        case fond, lumiere, surface, dessous

        var id: Self { self }

        var titre: String {
            switch self {
            case .fond: "Fond uni et contrasté"
            case .lumiere: "Lumière diffuse"
            case .surface: "Objet mat et immobile"
            case .dessous: "Prévoir de retourner l'objet"
            }
        }

        var detail: String {
            switch self {
            case .fond: "Une table claire pour un objet sombre, ou l'inverse. Pas de motifs."
            case .lumiere: "Lumière du jour indirecte ou plafonnier. Ni soleil direct, ni flash."
            case .surface: "Les surfaces brillantes, noires ou transparentes trompent la caméra."
            // Mesuré le 16/09/2026 : sans retournement, le dessous est inventé
            // et la hauteur part de 4 à 7 mm à côté ; avec, elle tombe juste.
            case .dessous: "Le dessous n'est jamais photographié : à la fin d'une passe, retournez l'objet sur le dessus. Sur une surface unie, collez d'abord quelques repères (adhésif de couleur, marqueur), sinon les deux passes se recollent mal."
            }
        }
    }
}

#Preview {
    NavigationStack {
        PreparationView(model: ScanFlowModel(store: ScanStore()))
    }
}
