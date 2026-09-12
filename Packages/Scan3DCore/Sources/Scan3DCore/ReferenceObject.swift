/// Objet de dimensions connues que l'utilisateur pose à côté de l'objet scanné
/// pour recaler l'échelle du modèle.
public enum ReferenceObject: String, Sendable, CaseIterable, Identifiable {
    /// Format ID-1 (norme ISO/IEC 7810) : cartes bancaires, carte Vitale, etc.
    case creditCard

    public var id: String { rawValue }

    /// Largeur réelle en millimètres.
    public var widthMM: Double {
        switch self {
        case .creditCard: 85.60
        }
    }

    /// Hauteur réelle en millimètres.
    public var heightMM: Double {
        switch self {
        case .creditCard: 53.98
        }
    }
}
