import SwiftUI
import RealityKit
import Scan3DCore

/// Écran 4 de la tranche 2 : le modèle qu'on fait tourner, et la distance
/// entre deux points touchés.
///
/// La `RealityView` n'affiche que la scène construite par `MesureModel` ; tous
/// les calculs (pose de la caméra, rayon du toucher, intersection) viennent de
/// `Scan3DCore` et sont testés sur Mac.
struct VisionneuseView: View {
    @State private var model: MesureModel
    /// Translation déjà appliquée : un glissement donne une position absolue,
    /// la caméra veut un déplacement relatif.
    @State private var derniereTranslation: CGSize = .zero
    @State private var derniereAmplitude: CGFloat = 1
    @State private var calibrageAffiche = false
    /// Prévient l'écran de détail du calibrage choisi (nil = réinitialiser).
    private let onCalibrage: (ScaleCalibration?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        maillage: Mesh,
        modele: URL,
        calibration: ScaleCalibration? = nil,
        onCalibrage: @escaping (ScaleCalibration?) -> Void = { _ in }
    ) {
        _model = State(initialValue: MesureModel(maillage: maillage, modele: modele, calibration: calibration))
        self.onCalibrage = onCalibrage
    }

    var body: some View {
        NavigationStack {
            contenu
                .navigationTitle("Mesure")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) { panneau }
        }
        .task { await model.charger() }
        .onChange(of: model.annonce) { _, annonce in
            if let annonce {
                AccessibilityNotification.Announcement(annonce.texte).post()
            }
        }
        .sheet(isPresented: $calibrageAffiche) {
            if let mesureMM = model.distanceBruteMM {
                CalibrageView(
                    mesureMM: mesureMM,
                    dimensions: model.dimensionsBrutes,
                    calibrationActuelle: model.calibration
                ) { calibration in
                    model.appliquerCalibrage(calibration)
                    onCalibrage(calibration)
                }
            }
        }
    }

    @ViewBuilder
    private var contenu: some View {
        switch model.etat {
        case .chargement:
            ProgressView("Ouverture du modèle…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .echec(let message):
            ContentUnavailableView {
                Label("Affichage impossible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .pret:
            scene
        }
    }

    private var scene: some View {
        GeometryReader { proxy in
            RealityView { contenu in
                // Caméra virtuelle : la scène est rendue depuis le
                // `PerspectiveCamera` que le modèle pilote (pas de réalité
                // augmentée ici, donc aucun accès à la caméra de l'iPhone).
                contenu.camera = .virtual
                contenu.entities.append(model.camera)
                contenu.entities.append(model.scene)
            }
            // Fond neutre : un modèle clair sur du blanc serait illisible, et le
            // dégradé donne un repère de profondeur quand l'objet tourne.
            .background(fond)
            .gesture(toucher(taille: proxy.size))
            // `simultaneousGesture` : faire tourner et pincer restent possibles
            // sans annuler le toucher (ils ne se déclenchent pas aux mêmes moments).
            .simultaneousGesture(rotation)
            .simultaneousGesture(zoom)
            .onChange(of: proxy.size, initial: true) { _, taille in
                model.cadrer(pour: SIMD2(Float(taille.width), Float(taille.height)))
            }
            // VoiceOver : la zone 3D reçoit les touchers directs, mais seulement
            // après activation (double toucher), pour ne pas voler ses gestes.
            .accessibilityDirectTouch(options: .requiresActivation)
            .accessibilityLabel("Modèle 3D")
            .accessibilityHint("Après activation, touchez deux points de l'objet pour mesurer la distance qui les sépare.")
        }
    }

    private var fond: some View {
        LinearGradient(
            colors: [Color(.systemGray5), Color(.systemGray3)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var panneau: some View {
        VStack(spacing: 12) {
            if let distance = model.distanceMM {
                Text(DimensionsFormatter.millimeters(distance))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .accessibilityLabel("Distance entre A et B : \(DimensionsFormatter.spokenCentimeters(distance))")
                Text(model.calibration == nil
                     ? "Entre le point A (jaune) et le point B (bleu)"
                     : "Entre A et B, cote calibrée")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Button("Calibrer avec cette mesure") {
                    calibrageAffiche = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Recale l'échelle du scan sur une cote réelle, mesurée à la main ou lue sur une carte bancaire.")
            } else {
                Text(model.pointA == nil
                     ? "Touchez un premier point sur l'objet."
                     : "Touchez le second point.")
                    .font(.headline)
                Text("Glissez pour tourner autour, pincez pour zoomer. Comptez quelques millimètres d'écart : contrôlez au pied à coulisse avant d'imprimer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Effacer les points") {
                    model.effacer()
                }
                .disabled(model.pointA == nil)

                // Filet de sécurité : à force de tourner et de zoomer, on perd
                // l'objet hors de l'écran sans savoir comment y revenir.
                Button("Recadrer") {
                    model.recadrer()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)
    }

    // MARK: Gestes

    /// Un toucher = un point posé. La position est relative à la vue 3D, comme
    /// la taille donnée au calcul du rayon.
    private func toucher(taille: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { valeur in
                model.toucher(
                    SIMD2(Float(valeur.location.x), Float(valeur.location.y)),
                    taille: SIMD2(Float(taille.width), Float(taille.height))
                )
            }
    }

    private var rotation: some Gesture {
        // 8 pt avant de tourner : en deçà, c'est un toucher, pas un glissement.
        DragGesture(minimumDistance: 8)
            .onChanged { valeur in
                model.pivoter(
                    dx: Float(valeur.translation.width - derniereTranslation.width),
                    dy: Float(valeur.translation.height - derniereTranslation.height)
                )
                derniereTranslation = valeur.translation
            }
            .onEnded { _ in derniereTranslation = .zero }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { valeur in
                model.zoomer(Float(valeur.magnification / derniereAmplitude))
                derniereAmplitude = valeur.magnification
            }
            .onEnded { _ in derniereAmplitude = 1 }
    }
}
