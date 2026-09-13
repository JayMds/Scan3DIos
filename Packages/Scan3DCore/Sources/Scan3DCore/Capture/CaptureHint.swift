/// Conseil de capture à donner à l'utilisateur, miroir neutre des neuf
/// `ObjectCaptureSession.Feedback` de RealityKit.
///
/// Pourquoi un miroir ? RealityKit est interdit dans `Scan3DCore` ; ce type
/// permet de tester la logique de priorité sur Mac, et l'app ne fait que
/// convertir `Feedback → CaptureHint` (un `switch` exhaustif).
///
/// **L'ordre de déclaration est l'ordre d'urgence** : quand plusieurs
/// conseils sont actifs en même temps, on annonce le premier de la liste.
/// Un problème qui stoppe la capture passe avant un simple avertissement.
public enum CaptureHint: CaseIterable, Sendable, Hashable {
    /// Trop sombre : la capture automatique s'arrête.
    case environmentTooDark
    /// La détection automatique a échoué, une boîte manuelle est proposée.
    case objectNotDetected
    /// La boîte de l'objet est hors du champ : la capture automatique ne tourne pas.
    case outOfFieldOfView
    case objectTooClose
    case objectTooFar
    /// Le mouvement est trop rapide pour des photos nettes.
    case movingTooFast
    /// Lumière faible : la capture continue, la qualité baisse.
    case environmentLowLight
    /// Le maximum de photos de l'iPhone est atteint (les suivantes sont ignorées).
    case overCapturing
    /// Objet peu texturé : retourner l'objet risque d'échouer, préférer une autre hauteur.
    case objectNotFlippable

    /// 0 = le plus urgent.
    public var priority: Int {
        Self.allCases.firstIndex(of: self) ?? Int.max
    }

    /// Vrai si la capture automatique n'avance plus tant que le problème persiste.
    public var blocksCapture: Bool {
        switch self {
        case .environmentTooDark, .outOfFieldOfView:
            true
        case .objectNotDetected, .objectTooClose, .objectTooFar, .movingTooFast,
             .environmentLowLight, .overCapturing, .objectNotFlippable:
            false
        }
    }

    /// Le conseil à afficher/annoncer parmi ceux actifs, `nil` si tout va bien.
    public static func mostUrgent(in hints: Set<CaptureHint>) -> CaptureHint? {
        hints.min { $0.priority < $1.priority }
    }
}
