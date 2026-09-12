import Foundation

/// Erreur levée quand l'UI demande une transition que le parcours n'autorise
/// pas. C'est un bug de séquencement dans l'app, jamais une erreur de
/// l'utilisateur : on la journalise, on ne l'affiche pas.
public enum ScanPhaseError: Error, Equatable, Sendable {
    case invalidTransition(from: ScanPhase, to: ScanPhase)
}

/// Phase courante du parcours de scan (écrans 2 à 8 de `docs/TRANCHE-1.md`).
///
/// Une seule source de vérité : l'UI ne fait qu'afficher la phase, et tout
/// changement passe par `transition(to:)`, qui refuse les sauts interdits.
/// Analogue : une machine XState dont les états sont une union discriminée.
///
/// ```
/// preparation → detection → capture ⇄ passComplete → reconstruction → preview
///                   ↘ failed(message) depuis detection, capture, reconstruction
///                     failed → reconstruction (« Reprendre » depuis le checkpoint)
/// ```
///
/// L'annulation n'est pas une phase : elle sort du parcours depuis n'importe
/// où. La spec ne prévoit l'échec que depuis capture/reconstruction ; on
/// l'accepte aussi depuis la détection car `ObjectCaptureSession` peut
/// passer en `.failed` avant la première photo (ex. dossier checkpoint non vide).
public enum ScanPhase: Equatable, Sendable {
    /// Écran 2 : checklist des bonnes conditions.
    case preparation
    /// Écran 3 : caméra + boîte englobante autour de l'objet.
    case detection
    /// Écran 4 : prises de vue automatiques en tournant autour de l'objet.
    case capture
    /// Écran 5 : passe terminée — nouvelle passe, retourner l'objet ou terminer.
    case passComplete
    /// Écran 6 : reconstruction en cours, `progress` entre 0 et 1.
    case reconstruction(progress: Double)
    /// Écran 7 : modèle prêt (fichier `.usdz`).
    case preview(model: URL)
    /// Erreur affichée à l'utilisateur ; « Reprendre » ramène en reconstruction.
    case failed(message: String)

    /// Vrai si passer de `self` à `target` respecte le parcours.
    public func canTransition(to target: ScanPhase) -> Bool {
        switch (self, target) {
        case (.preparation, .detection),
             (.detection, .capture),
             (.capture, .passComplete),
             (.passComplete, .capture),           // nouvelle passe
             (.passComplete, .reconstruction),
             (.reconstruction, .reconstruction),  // mise à jour de la progression
             (.reconstruction, .preview),
             (.detection, .failed),
             (.capture, .failed),
             (.reconstruction, .failed),
             (.failed, .reconstruction):          // « Reprendre »
            true
        default:
            false
        }
    }

    /// Renvoie la nouvelle phase, ou lève `invalidTransition`.
    public func transition(to target: ScanPhase) throws(ScanPhaseError) -> ScanPhase {
        guard canTransition(to: target) else {
            throw .invalidTransition(from: self, to: target)
        }
        return target
    }

    /// Annuler détruirait-il un travail en cours (photos, calcul) ?
    /// Si oui, l'UI doit demander confirmation avant de sortir du parcours.
    public var cancellationNeedsConfirmation: Bool {
        switch self {
        case .capture, .passComplete, .reconstruction: true
        case .preparation, .detection, .preview, .failed: false
        }
    }
}
