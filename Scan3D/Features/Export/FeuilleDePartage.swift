import UIKit

/// Feuille de partage iOS (AirDrop, Fichiers, Bambu Handy…) avec un rappel à
/// sa fermeture. `ShareLink` (SwiftUI) ouvre la même feuille mais ne prévient
/// pas quand elle se ferme — or il faut supprimer le fichier juste après.
@MainActor
enum FeuilleDePartage {
    /// Renvoie `false` si aucun écran n'a pu présenter la feuille (le rappel
    /// ne sera alors jamais appelé : à l'appelant de nettoyer).
    static func presenter(
        _ fichier: URL,
        fermeture: @escaping @MainActor (_ partage: Bool) -> Void
    ) -> Bool {
        guard let presentateur = ecranVisible() else { return false }

        let feuille = UIActivityViewController(activityItems: [fichier], applicationActivities: nil)
        feuille.completionWithItemsHandler = { _, partage, _, _ in
            // Le type du rappel n'est pas marqué @MainActor par UIKit : on y
            // revient explicitement plutôt que de parier sur le fil d'appel.
            Task { @MainActor in fermeture(partage) }
        }
        // App iPhone ouverte sur un iPad : la feuille devient un popover, qui
        // exige une ancre sous peine de plantage.
        if let popover = feuille.popoverPresentationController {
            popover.sourceView = presentateur.view
            popover.sourceRect = CGRect(x: presentateur.view.bounds.midX, y: presentateur.view.bounds.maxY, width: 0, height: 0)
        }
        presentateur.present(feuille, animated: true)
        return true
    }

    /// L'écran au premier plan : ici, la pile de navigation qui affiche le
    /// détail du scan.
    private static func ecranVisible() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var courant = scene?.keyWindow?.rootViewController
        while let presente = courant?.presentedViewController {
            courant = presente
        }
        return courant
    }
}
