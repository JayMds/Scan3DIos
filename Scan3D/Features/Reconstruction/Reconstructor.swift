import Foundation
import os
import Scan3DCore

#if !targetEnvironment(simulator)
import RealityKit

/// Possède l'unique `PhotogrammetrySession` et traduit ses sorties pour
/// `ScanFlowModel`.
///
/// `@MainActor` : la session n'est pas `Sendable`, elle reste donc dans une
/// seule isolation. Ses sorties (`Output`) sont `Sendable` (vérifié dans
/// l'interface du SDK) : la boucle `for try await` peut tourner ici sans
/// bloquer l'interface — chaque `next()` s'exécute hors du fil principal,
/// seul son résultat y revient. Le calcul lourd, lui, vit dans les threads
/// internes de RealityKit.
@MainActor @Observable
final class Reconstructor {
    enum Evenement: Equatable {
        case progression(Double)
        case info(tempsRestant: TimeInterval?, etape: String?)
        case terminee(URL)
        case echec(String)
        case annulee
    }

    private var session: PhotogrammetrySession?
    private var boucle: Task<Void, Never>?
    private let onEvenement: @MainActor (Evenement) -> Void

    init(onEvenement: @escaping @MainActor (Evenement) -> Void) {
        self.onEvenement = onEvenement
    }

    /// `checkpoint` : le dossier rempli par `ObjectCaptureSession` ; il accélère
    /// la reconstruction et permet de reprendre après un échec.
    func lancer(images: URL, checkpoint: URL, modele: URL) {
        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = checkpoint
            let session = try PhotogrammetrySession(input: images, configuration: configuration)
            // `.reduced` est le seul niveau disponible sur iOS : c'est la valeur par défaut.
            try session.process(requests: [.modelFile(url: modele)])
            self.session = session
            surveiller(session)
            Logger.reconstruction.info("Reconstruction lancée")
        } catch {
            Logger.reconstruction.error("Reconstruction impossible : \(error.localizedDescription, privacy: .private)")
            onEvenement(.echec(Self.message(pour: error)))
        }
    }

    /// Demande l'arrêt, puis attend (au plus 3 s) que la session ait fini :
    /// la suppression du dossier ne doit pas croiser une écriture en cours.
    func annuler() async {
        guard let session else { return }
        session.cancel()
        for _ in 0..<12 {
            if !session.isProcessing { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        liberer()
    }

    // MARK: Interne

    private func surveiller(_ session: PhotogrammetrySession) {
        boucle = Task { [weak self] in
            do {
                for try await sortie in session.outputs {
                    guard let self else { return }
                    switch sortie {
                    case .requestProgress(_, let fraction):
                        onEvenement(.progression(fraction))
                    case .requestProgressInfo(_, let info):
                        onEvenement(.info(tempsRestant: info.estimatedRemainingTime,
                                          etape: info.processingStage.map(Self.texte)))
                    case .requestComplete(_, let resultat):
                        if case .modelFile(let url) = resultat {
                            onEvenement(.terminee(url))
                        }
                    case .requestError(_, let erreur):
                        Logger.reconstruction.error("Requête en échec : \(erreur.localizedDescription, privacy: .private)")
                        onEvenement(.echec(Self.message(pour: erreur)))
                        liberer()
                        return
                    case .processingCancelled:
                        onEvenement(.annulee)
                        liberer()
                        return
                    case .processingComplete:
                        liberer()
                        return
                    case .inputComplete:
                        Logger.reconstruction.info("Photos chargées")
                    case .invalidSample(let id, let raison):
                        Logger.reconstruction.notice("Photo \(id, privacy: .public) invalide : \(raison, privacy: .public)")
                    case .skippedSample(let id):
                        Logger.reconstruction.notice("Photo \(id, privacy: .public) sautée")
                    case .automaticDownsampling:
                        Logger.reconstruction.notice("Images réduites automatiquement (mémoire limitée)")
                    case .stitchingIncomplete:
                        Logger.reconstruction.notice("Raccord incomplet : certaines vues n'ont pas pu être assemblées")
                    @unknown default:
                        break
                    }
                }
            } catch {
                Logger.reconstruction.error("Flux de sortie interrompu : \(error.localizedDescription, privacy: .private)")
                self?.onEvenement(.echec(Self.message(pour: error)))
            }
            self?.liberer()
        }
    }

    /// Libère la session (mémoire) ; une seule à la fois.
    private func liberer() {
        boucle = nil
        session = nil
    }

    /// Messages en français pour les erreurs connues, sinon celui du système.
    private static func message(pour erreur: any Error) -> String {
        guard let erreur = erreur as? PhotogrammetrySession.Error else {
            return erreur.localizedDescription
        }
        switch erreur {
        case .insufficientStorage(let octets):
            let taille = ByteCountFormatter.string(fromByteCount: octets, countStyle: .file)
            return "Espace insuffisant pour reconstruire : il faut environ \(taille) libres."
        case .invalidImages:
            return "Le dossier des photos est illisible ou vide."
        case .invalidOutput:
            return "Impossible d'écrire le fichier du modèle."
        @unknown default:
            return erreur.localizedDescription
        }
    }

    private static func texte(_ etape: PhotogrammetrySession.Output.ProcessingStage) -> String {
        switch etape {
        case .preProcessing: "Préparation des photos"
        case .imageAlignment: "Alignement des photos"
        case .pointCloudGeneration: "Nuage de points"
        case .meshGeneration: "Maillage"
        case .textureMapping: "Textures"
        case .optimization: "Optimisation"
        @unknown default: "Traitement"
        }
    }
}

#else

/// Doublure simulateur : même interface, échec immédiat.
@MainActor @Observable
final class Reconstructor {
    enum Evenement: Equatable {
        case progression(Double)
        case info(tempsRestant: TimeInterval?, etape: String?)
        case terminee(URL)
        case echec(String)
        case annulee
    }

    private let onEvenement: @MainActor (Evenement) -> Void

    init(onEvenement: @escaping @MainActor (Evenement) -> Void) {
        self.onEvenement = onEvenement
    }

    func lancer(images: URL, checkpoint: URL, modele: URL) {
        onEvenement(.echec("La reconstruction nécessite un iPhone réel."))
    }

    func annuler() async {}
}
#endif
