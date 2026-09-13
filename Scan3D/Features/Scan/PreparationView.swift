import SwiftUI
import Scan3DCore

/// Écran 2 : choix du mode et checklist des conditions qui font réussir un
/// scan. Cocher est facultatif (« coche / passe ») : le but est de prévenir
/// la cause n° 1 d'échec, les surfaces noires, brillantes ou transparentes.
struct PreparationView: View {
    let model: ScanFlowModel
    /// Préférence (pas une donnée) : autorisée dans UserDefaults.
    @AppStorage("modeCapture") private var mode: CaptureMode = .orbit
    @State private var coches: Set<Conseil> = []

    var body: some View {
        List {
            Section {
                Picker("Mode de capture", selection: $mode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.titre).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(mode.explication)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Comment scanner ?")
            }

            Section {
                ForEach(Conseil.pour(mode)) { conseil in
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
                Task { await model.demarrer(mode: mode) }
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

    /// Les conditions, par ordre d'importance ; certaines ne valent que pour
    /// le plateau tournant.
    enum Conseil: CaseIterable, Identifiable {
        case fond, lumiere, surface
        case support, fondPlateau

        var id: Self { self }

        static func pour(_ mode: CaptureMode) -> [Conseil] {
            switch mode {
            case .orbit: [.fond, .lumiere, .surface]
            case .turntable: [.support, .fondPlateau, .lumiere, .surface]
            }
        }

        var titre: String {
            switch self {
            case .fond: "Fond uni et contrasté"
            case .lumiere: "Lumière diffuse"
            case .surface: "Objet mat et immobile"
            case .support: "iPhone posé sur un support"
            case .fondPlateau: "Fond uni derrière le plateau"
            }
        }

        var detail: String {
            switch self {
            case .fond: "Une table claire pour un objet sombre, ou l'inverse. Pas de motifs."
            case .lumiere: "Lumière du jour indirecte ou plafonnier. Ni soleil direct, ni flash."
            case .surface: "Les surfaces brillantes, noires ou transparentes trompent la caméra."
            case .support: "Trépied ou pile de livres, légèrement en plongée, cadré sur le plateau. Il ne doit plus bouger."
            case .fondPlateau: "Mur ou carton sans motif : le fond est fixe, seul l'objet doit changer d'une photo à l'autre."
            }
        }
    }
}

#Preview {
    NavigationStack {
        PreparationView(model: ScanFlowModel())
    }
}
