#if !targetEnvironment(simulator)
import Foundation
import os
import RealityKit
import Scan3DCore
// `ObjectCaptureSession` est fourni par le « cross-import overlay »
// RealityKit × SwiftUI : le type n'existe que si les DEUX modules sont importés.
import SwiftUI

/// Propriétaire de l'unique `ObjectCaptureSession` (mémoire importante) et
/// traducteur de ses événements pour `ScanFlowModel`.
///
/// La session est `@MainActor` et `Observable` : les vues lisent ses
/// propriétés (`state`, `feedback`, `numberOfShotsTaken`) à travers ce
/// contrôleur et SwiftUI se rafraîchit tout seul. Les flux `stateUpdates` /
/// `userCompletedScanPassUpdates` ne servent qu'aux effets de bord
/// (changements de phase), consommés dans des `Task`.
@MainActor @Observable
final class CaptureController {
    enum Evenement: Equatable {
        /// La session prend des photos (première fois après `startCapturing`).
        case captureCommencee
        /// Tour complet effectué : le cadran de capture est plein.
        case passeTerminee
        /// Photos enregistrées, la session a été détruite.
        case terminee
        case echec(String)
    }

    private(set) var session: ObjectCaptureSession?
    private let layout: ScanLayout
    private let onEvenement: @MainActor (Evenement) -> Void
    private var surveillances: [Task<Void, Never>] = []
    private var annule = false

    init(layout: ScanLayout, onEvenement: @escaping @MainActor (Evenement) -> Void) {
        self.layout = layout
        self.onEvenement = onEvenement
    }

    // MARK: Lecture (observée par les vues)

    var nombrePhotos: Int { session?.numberOfShotsTaken ?? 0 }
    var maximumPhotos: Int { session?.maximumNumberOfInputImages ?? 0 }

    /// Le conseil le plus urgent parmi les retours actifs de la session.
    var conseil: CaptureHint? {
        guard let session else { return nil }
        let conseils = Set(session.feedback.compactMap { CaptureHint($0) })
        return CaptureHint.mostUrgent(in: conseils)
    }

    /// RealityKit déconseille de retourner les objets peu texturés.
    var objetRetournable: Bool {
        guard let session else { return false }
        return !session.feedback.contains(.objectNotFlippable)
    }

    // MARK: Commandes

    func demarrer() {
        let session = ObjectCaptureSession()
        var configuration = ObjectCaptureSession.Configuration()
        // Doit être un dossier VIDE, sinon la session passe en .failed (doc Apple).
        configuration.checkpointDirectory = layout.checkpointDirectory
        // Tranche 1 : reconstruction sur l'iPhone, inutile de dépasser sa limite.
        configuration.isOverCaptureEnabled = false
        session.start(imagesDirectory: layout.imagesDirectory, configuration: configuration)
        self.session = session
        surveiller(session)
        Logger.scan.info("Session de capture démarrée, maximum \(session.maximumNumberOfInputImages, privacy: .public) photos")
    }

    /// `false` si la session ne trouve pas d'objet : l'UI invite à réessayer.
    func commencerDetection() -> Bool { session?.startDetecting() ?? false }
    func reinitialiserDetection() { _ = session?.resetDetection() }
    func commencerCapture() { session?.startCapturing() }
    func nouvellePasse() { session?.beginNewScanPass() }
    func nouvellePasseApresRetournement() { session?.beginNewScanPassAfterFlip() }
    func terminer() { session?.finish() }

    /// Annule, puis attend (au plus 2 s) que la session ait fini d'écrire :
    /// la suppression du dossier ne doit pas croiser une écriture en cours.
    func annuler() async {
        annule = true
        guard let session else { return }
        session.cancel()
        for _ in 0..<8 {
            if session.state.estTerminal { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        liberer()
    }

    // MARK: Interne

    private func surveiller(_ session: ObjectCaptureSession) {
        surveillances.append(Task { [weak self] in
            for await etat in session.stateUpdates {
                guard let self, !annule else { return }
                switch etat {
                case .capturing:
                    onEvenement(.captureCommencee)
                case .completed:
                    onEvenement(.terminee)
                    liberer()
                    return
                case .failed(let erreur):
                    Logger.scan.error("Session de capture en échec : \(erreur.localizedDescription, privacy: .public)")
                    onEvenement(.echec(erreur.localizedDescription))
                    liberer()
                    return
                case .initializing, .ready, .detecting, .finishing:
                    break
                @unknown default:
                    break
                }
            }
        })
        surveillances.append(Task { [weak self] in
            for await complete in session.userCompletedScanPassUpdates where complete {
                guard let self, !annule else { return }
                onEvenement(.passeTerminee)
            }
        })
    }

    /// Libère la session — donc la caméra et sa mémoire. Une seule à la fois.
    private func liberer() {
        surveillances.forEach { $0.cancel() }
        surveillances.removeAll()
        session = nil
    }
}

extension ObjectCaptureSession.CaptureState {
    /// La session ne changera plus d'état.
    var estTerminal: Bool {
        switch self {
        case .completed, .failed: true
        case .initializing, .ready, .detecting, .capturing, .finishing: false
        @unknown default: false
        }
    }
}

/// Conversion RealityKit → Scan3DCore. `nil` pour un retour inconnu d'un
/// futur iOS : mieux vaut ne rien dire que dire n'importe quoi.
extension CaptureHint {
    init?(_ feedback: ObjectCaptureSession.Feedback) {
        switch feedback {
        case .environmentTooDark: self = .environmentTooDark
        case .objectNotDetected: self = .objectNotDetected
        case .outOfFieldOfView: self = .outOfFieldOfView
        case .objectTooClose: self = .objectTooClose
        case .objectTooFar: self = .objectTooFar
        case .movingTooFast: self = .movingTooFast
        case .environmentLowLight: self = .environmentLowLight
        case .overCapturing: self = .overCapturing
        case .objectNotFlippable: self = .objectNotFlippable
        @unknown default: return nil
        }
    }
}
#endif
