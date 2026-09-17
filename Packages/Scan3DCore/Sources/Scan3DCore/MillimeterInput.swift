import Foundation

/// Analyse d'une cote saisie au clavier, en millimètres.
///
/// La saisie vient de l'utilisateur : on ne lui fait aucune confiance. Plutôt
/// que d'accepter tout ce que `Double(_:)` sait lire (« 1e3 », « -0 », « inf »),
/// on n'autorise qu'une forme : des chiffres, au plus un séparateur décimal —
/// virgule française ou point —, et une valeur dans une plage d'objet réel.
public enum MillimeterInput {
    /// De 0,1 mm (un dixième, la résolution d'un pied à coulisse) à 10 m.
    public static let plausibleRange: ClosedRange<Double> = 0.1...10_000

    /// Renvoie la cote en millimètres, ou `nil` si la saisie est refusée.
    public static func parse(_ texte: String) -> Double? {
        // Les espaces (y compris insécables, ceux que produit le formatage des
        // nombres) sont retirés ; la virgule devient un point.
        let nettoye = texte
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")

        guard !nettoye.isEmpty,
              // `isASCII` exclut les chiffres d'autres écritures et les
              // caractères « numériques » comme ½, que `Double` ne lit pas.
              nettoye.allSatisfy({ ($0.isASCII && $0.isWholeNumber) || $0 == "." }),
              nettoye.filter({ $0 == "." }).count <= 1,
              let valeur = Double(nettoye),
              valeur.isFinite,
              plausibleRange.contains(valeur)
        else { return nil }
        return valeur
    }
}
