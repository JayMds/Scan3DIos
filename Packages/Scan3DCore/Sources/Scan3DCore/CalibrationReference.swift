/// Cotes de référence proposées à l'utilisateur pour calibrer un scan.
///
/// Une carte bancaire est la règle que tout le monde a dans la poche : posée à
/// côté de l'objet pendant le scan, elle donne une cote connue au dixième.
public enum CalibrationReference: String, CaseIterable, Identifiable, Sendable {
    case creditCardWidth
    case creditCardHeight

    public var id: String { rawValue }

    public var actualMM: Double {
        switch self {
        case .creditCardWidth: ReferenceObject.creditCard.widthMM
        case .creditCardHeight: ReferenceObject.creditCard.heightMM
        }
    }

    public var label: String {
        switch self {
        case .creditCardWidth: "Carte bancaire, grand côté"
        case .creditCardHeight: "Carte bancaire, petit côté"
        }
    }
}
