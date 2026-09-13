import UIKit

/// Empêche l'écran de se verrouiller pendant la capture (et, à l'étape 3,
/// la reconstruction). À remettre à `false` sur TOUS les chemins de sortie ;
/// `ScanFlowView` le fait aussi à sa disparition, en filet de sécurité.
@MainActor
enum VeilleEcran {
    static func empecher(_ actif: Bool) {
        UIApplication.shared.isIdleTimerDisabled = actif
    }
}
