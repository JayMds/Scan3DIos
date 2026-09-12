import AVFoundation

/// Autorisation caméra, demandée au moment du premier scan — jamais au
/// lancement de l'app, pour que la demande ait un contexte.
enum CameraAuthorization {
    enum Statut: Equatable {
        case nonDeterminee
        case autorisee
        /// Refusée par l'utilisateur, ou bloquée par une restriction (Temps d'écran).
        case refusee
    }

    static var statut: Statut {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .nonDeterminee
        case .authorized: .autorisee
        case .denied, .restricted: .refusee
        // Une valeur ajoutée par un futur iOS : on reste prudent.
        @unknown default: .refusee
        }
    }

    /// Affiche l'alerte système (une seule fois par installation) et renvoie
    /// le statut résultant.
    static func demander() async -> Statut {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return statut
    }
}
