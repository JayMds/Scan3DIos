import SwiftUI
import Scan3DCore

/// Écran 5 de la tranche 2 : recaler l'échelle d'un scan sur une cote connue.
///
/// Principe : la mesure A-B donne ce que le modèle **croit** ; la cote réelle
/// (pied à coulisse, ou carte bancaire posée à côté de l'objet) donne la
/// vérité. Le rapport des deux devient le facteur du scan. Rien n'est appliqué
/// sans que l'utilisateur ait vu le facteur **et** les nouvelles cotes.
struct CalibrageView: View {
    /// Mesure A-B brute, en millimètres.
    let mesureMM: Double
    /// Cotes brutes du modèle, pour l'aperçu.
    let dimensions: Dimensions
    let calibrationActuelle: ScaleCalibration?
    /// `nil` = réinitialiser.
    let appliquer: (ScaleCalibration?) -> Void

    @State private var choix: Choix = .saisie
    @State private var saisie = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var champActif: Bool

    /// Cote de référence : saisie au clavier, ou objet de dimensions connues.
    private enum Choix: Hashable {
        case saisie
        case objet(CalibrationReference)
    }

    /// Ce que l'écran peut proposer, à chaque frappe.
    private enum Etat {
        case aCompleter
        case pret(ScaleCalibration)
        case probleme(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Mesuré sur le modèle",
                                   value: DimensionsFormatter.millimeters(mesureMM))
                        .monospacedDigit()
                } footer: {
                    Text("Le calibrage corrige une **échelle**. Si l'écart vient d'arêtes arrondies par la reconstruction (quelques millimètres, quelle que soit la taille), il ne le corrigera pas entièrement.")
                }

                Section("Cote réelle") {
                    Picker("Référence", selection: $choix) {
                        Text("Cote mesurée à la main").tag(Choix.saisie)
                        ForEach(CalibrationReference.allCases) { reference in
                            Text("\(reference.label) (\(DimensionsFormatter.millimeters(reference.actualMM)))")
                                .tag(Choix.objet(reference))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if choix == .saisie {
                        TextField("Cote réelle", text: $saisie)
                            .keyboardType(.decimalPad)
                            .focused($champActif)
                            .monospacedDigit()
                            .accessibilityLabel("Cote réelle en millimètres")
                    }
                }

                apercu

                if calibrationActuelle != nil {
                    Section {
                        Button("Réinitialiser le calibrage", role: .destructive) {
                            appliquer(nil)
                            dismiss()
                        }
                    } footer: {
                        Text("Les cotes brutes sont conservées : réinitialiser les rétablit telles quelles.")
                    }
                }
            }
            .navigationTitle("Calibrer le scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") {
                        if case .pret(let calibration) = etat {
                            appliquer(calibration)
                            dismiss()
                        }
                    }
                    .disabled(!estApplicable)
                }
            }
            .onAppear { champActif = choix == .saisie }
        }
    }

    @ViewBuilder
    private var apercu: some View {
        switch etat {
        case .aCompleter:
            EmptyView()
        case .probleme(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        case .pret(let calibration):
            let corrigees = dimensions.scaled(by: calibration.factor)
            Section {
                LabeledContent("Facteur", value: facteurTexte(calibration.factor))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 4) {
                    Text(DimensionsFormatter.compact(dimensions))
                        .foregroundStyle(.secondary)
                        .strikethrough()
                    Text(DimensionsFormatter.compact(corrigees))
                        .font(.headline)
                }
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Nouvelles cotes : \(DimensionsFormatter.spoken(corrigees))")
            } header: {
                Text("Aperçu")
            } footer: {
                Text("Ces cotes seront celles de la bibliothèque, des mesures et du fichier STL exporté.")
            }
        }
    }

    // MARK: Logique

    /// Cote réelle retenue : la saisie analysée, ou celle de l'objet choisi.
    private var coteReelle: Double? {
        switch choix {
        case .saisie: MillimeterInput.parse(saisie)
        case .objet(let reference): reference.actualMM
        }
    }

    private var etat: Etat {
        guard let coteReelle else {
            // Tant que rien n'est tapé, pas de reproche : l'écran attend.
            return saisie.isEmpty ? .aCompleter
                : .probleme("Saisissez une cote en millimètres, par exemple 184,0.")
        }
        do {
            return .pret(try ScaleCalibration(measuredMM: mesureMM, actualMM: coteReelle))
        } catch {
            switch error {
            case .invalidMeasurement:
                return .probleme("La mesure sur le modèle est inutilisable : reprenez les deux points.")
            case .implausibleFactor(let facteur):
                return .probleme("Écart de \(pourcentage(facteur)) entre la mesure et la cote saisie : au-delà de 20 %, c'est presque toujours la mauvaise cote ou la mauvaise unité.")
            }
        }
    }

    private var estApplicable: Bool {
        if case .pret = etat { return true }
        return false
    }

    private func facteurTexte(_ facteur: Double) -> String {
        facteur.formatted(.number.precision(.fractionLength(3)).locale(DimensionsFormatter.french))
    }

    private func pourcentage(_ facteur: Double) -> String {
        let ecart = abs(facteur - 1) * 100
        return "\(ecart.formatted(.number.precision(.fractionLength(0)).locale(DimensionsFormatter.french))) %"
    }
}

#Preview {
    CalibrageView(
        mesureMM: 177.9,
        dimensions: Dimensions(lengthMM: 189.2, widthMM: 163, heightMM: 56.8),
        calibrationActuelle: nil
    ) { _ in }
}
