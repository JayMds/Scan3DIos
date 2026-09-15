import Foundation
import Scan3DCore

/// Textes d'une fiche pour l'interface : date affichée et phrase VoiceOver.
/// Côté app, car ils dépendent du fuseau et du format de l'appareil.
extension ScanRecord {
    /// « 15 sept. 2026 à 14:32 ».
    var dateCourte: String {
        createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: DimensionsFormatter.french))
    }

    /// « 15 septembre 2026 à 14:32 » : les abréviations se lisent mal à voix haute.
    var dateLongue: String {
        createdAt.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: DimensionsFormatter.french))
    }

    /// Ligne secondaire de la liste : date, et rappel si les cotes sont corrigées.
    var sousTitre: String {
        calibration == nil ? dateCourte : "\(dateCourte) · Calibré"
    }

    /// Une ligne de bibliothèque lue d'une traite par VoiceOver.
    var phraseAccessible: String {
        let calibrage = calibration == nil ? "" : ", calibré"
        return "\(name), enregistré le \(dateLongue), \(DimensionsFormatter.spoken(dimensions))\(calibrage)"
    }
}
