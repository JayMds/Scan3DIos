import Scan3DCore

/// Textes affichés et annoncés pour chaque conseil. Courts et impératifs :
/// l'utilisateur tourne autour d'un objet, il n'a pas le temps de lire.
/// Les textes vivent dans l'app (pas dans Scan3DCore) : c'est de l'UI.
extension CaptureHint {
    var texte: String {
        switch self {
        case .environmentTooDark: "Trop sombre : allumez la lumière"
        case .objectNotDetected: "Objet non détecté : ajustez la boîte à la main"
        case .outOfFieldOfView: "Cadrez l'objet dans l'écran"
        case .objectTooClose: "Trop près : reculez un peu"
        case .objectTooFar: "Trop loin : rapprochez-vous"
        case .movingTooFast: "Plus lentement"
        case .environmentLowLight: "Lumière faible : le résultat sera moins net"
        case .overCapturing: "Maximum de photos atteint pour l'iPhone"
        case .objectNotFlippable: "Objet difficile à retourner : préférez une autre hauteur"
        }
    }
}
