import SwiftUI
// `.quickLookPreview` est fourni par QuickLook, pas par SwiftUI.
import QuickLook
import Scan3DCore

/// Écran de détail d'un scan (ex-écrans 7 et 8 de la tranche 1) : cotes en
/// millimètres, visionneuse 3D d'Apple, export STL, renommer, supprimer.
/// Ouvert depuis la bibliothèque, ou automatiquement à la fin d'un scan.
struct DetailScanView: View {
    let bibliotheque: BibliothequeModel
    @State private var model: DetailScanModel
    /// Non nil → Quick Look est affiché ; il remet la valeur à nil en se fermant.
    @State private var modeleAffiche: URL?
    @State private var renommageAffiche = false
    @State private var nomSaisi = ""
    @State private var confirmerSuppression = false
    @State private var erreur: BibliothequeErreur?
    /// Fiche figée pendant la suppression : l'écran garde son contenu durant
    /// l'animation de retour, au lieu d'afficher « scan illisible ».
    @State private var ficheFigee: ScanRecord?
    @Environment(\.dismiss) private var dismiss

    /// `_model = State(initialValue:)` : un `@State` qui dépend d'un paramètre
    /// s'initialise ainsi. SwiftUI ne garde que la première valeur, même si
    /// la vue est recréée (≈ `useState(() => …)` en React).
    init(bibliotheque: BibliothequeModel, layout: ScanLayout) {
        self.bibliotheque = bibliotheque
        _model = State(initialValue: DetailScanModel(layout: layout, store: bibliotheque.store))
    }

    /// Lue dans la bibliothèque à chaque rendu : un renommage s'affiche ici et
    /// dans la liste en même temps.
    private var fiche: ScanRecord? {
        ficheFigee ?? bibliotheque.element(model.layout.id)?.fiche
    }

    var body: some View {
        List {
            if let fiche {
                sectionDimensions(fiche)
            } else {
                Section {
                    Label("Ce scan n'a pas pu être mesuré : son modèle 3D est peut-être endommagé. Vous pouvez l'afficher en 3D ou le supprimer.",
                          systemImage: "exclamationmark.triangle")
                }
            }
            if model.lectureEchouee {
                Section {
                    Label("Le modèle n'a pas pu être lu : l'export STL est indisponible.",
                          systemImage: "exclamationmark.triangle")
                }
            }

            Section {
                Button {
                    modeleAffiche = model.layout.modelFile
                } label: {
                    Label("Voir en 3D", systemImage: "cube.transparent")
                }
                .accessibilityHint("Ouvre la visionneuse 3D, avec un mode réalité augmentée à l'échelle réelle.")
            }

            Section {
                Button(role: .destructive) {
                    confirmerSuppression = true
                } label: {
                    Label("Supprimer le scan", systemImage: "trash")
                }
            }
        }
        .navigationTitle(fiche?.name ?? "Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let fiche {
                ToolbarItem(placement: .primaryAction) {
                    Button("Renommer") {
                        nomSaisi = fiche.name
                        renommageAffiche = true
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { boutonExport }
        // Visionneuse système : rotation, zoom, VoiceOver et mode AR à l'échelle
        // réelle fournis par iOS (décision D3 de la tranche 1).
        .quickLookPreview($modeleAffiche)
        .task { await model.charger() }
        .alert("Renommer le scan", isPresented: $renommageAffiche) {
            TextField("Nom du scan", text: $nomSaisi)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") {
                Task { await renommer() }
            }
            .disabled(ScanRecord.sanitizedName(nomSaisi) == nil)
        } message: {
            Text("\(ScanRecord.maximumNameLength) caractères au plus.")
        }
        // Le champ ne peut pas dépasser la limite : mieux que de refuser après coup.
        .onChange(of: nomSaisi) { _, nom in
            if nom.count > ScanRecord.maximumNameLength {
                nomSaisi = String(nom.prefix(ScanRecord.maximumNameLength))
            }
        }
        .confirmationDialog("Supprimer ce scan ?", isPresented: $confirmerSuppression, titleVisibility: .visible) {
            Button("Supprimer le scan", role: .destructive) {
                Task { await supprimer() }
            }
        } message: {
            Text(BibliothequeModel.messageSuppression)
        }
        .alert("Action impossible", isPresented: erreurPresente, presenting: erreur) { _ in
            Button("OK") {}
        } message: { erreur in
            Text(erreur.localizedDescription)
        }
        .alert("Export impossible", isPresented: erreurExportPresente) {
            Button("OK") {}
        } message: {
            Text(model.erreurExport ?? "")
        }
    }

    private func sectionDimensions(_ fiche: ScanRecord) -> some View {
        let dimensions = fiche.dimensions
        return Section {
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
            Text(piedDePage(fiche))
        }
    }

    private func ligne(_ titre: String, _ millimetres: Double) -> some View {
        LabeledContent(titre, value: DimensionsFormatter.millimeters(millimetres))
            .monospacedDigit()
            .accessibilityValue(DimensionsFormatter.spokenCentimeters(millimetres))
    }

    private func piedDePage(_ fiche: ScanRecord) -> String {
        let nombre = fiche.triangleCount.formatted(.number.locale(DimensionsFormatter.french))
        let taille = model.tailleModele.map { ", \($0)" } ?? ""
        return "Enregistré le \(fiche.dateCourte). Cotes de la boîte englobante du modèle (\(nombre) triangles\(taille)). Contrôlez au pied à coulisse avant d'imprimer une pièce ajustée."
    }

    private var boutonExport: some View {
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
        .controlSize(.large)
        .disabled(!model.exportPossible || model.exportEnCours)
        .accessibilityHint("Crée un fichier STL en millimètres et ouvre la feuille de partage : AirDrop, Fichiers, application de votre imprimante.")
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

    private func renommer() async {
        do {
            try await bibliotheque.renommer(model.layout.id, en: nomSaisi)
            AccessibilityNotification.Announcement("Scan renommé").post()
        } catch {
            self.erreur = error
        }
    }

    /// Le scan n'existe plus : retour à la bibliothèque.
    private func supprimer() async {
        ficheFigee = fiche
        do {
            try await bibliotheque.supprimer(model.layout.id)
            AccessibilityNotification.Announcement("Scan supprimé").post()
            dismiss()
        } catch {
            ficheFigee = nil
            self.erreur = error
        }
    }

    private var erreurPresente: Binding<Bool> {
        Binding(
            get: { erreur != nil },
            set: { visible in if !visible { erreur = nil } }
        )
    }

    private var erreurExportPresente: Binding<Bool> {
        Binding(
            get: { model.erreurExport != nil },
            set: { visible in if !visible { model.effacerErreurExport() } }
        )
    }
}
