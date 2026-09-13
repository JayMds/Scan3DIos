import Foundation

/// Mise en forme de l'avancement d'une reconstruction (écran 6).
/// Logique pure : la source des valeurs (RealityKit) reste dans l'app, ici on
/// ne fait que transformer des nombres en textes stables et testables.
public enum ReconstructionProgress {

    /// Temps restant, déjà arrondi pour l'affichage.
    public enum RemainingTime: Equatable, Sendable {
        case lessThanAMinute
        case minutes(Int)
        case hours(Int, minutes: Int)

        /// Texte court pour l'écran : « environ 2 min ».
        public var text: String {
            switch self {
            case .lessThanAMinute: "moins d'une minute"
            case .minutes(let minutes): "environ \(minutes) min"
            case .hours(let hours, let minutes): "environ \(hours) h \(String(format: "%02d", minutes))"
            }
        }

        /// Texte pour VoiceOver, sans abréviation : « environ 2 minutes ».
        public var spokenText: String {
            // `return` explicite partout : un cas qui déclare une variable fait
            // du `switch` une instruction, plus une expression.
            switch self {
            case .lessThanAMinute:
                return "moins d'une minute"
            case .minutes(let minutes):
                return "environ \(minutes) minute\(minutes > 1 ? "s" : "")"
            case .hours(let hours, let minutes):
                let heures = "\(hours) heure\(hours > 1 ? "s" : "")"
                return minutes > 0 ? "environ \(heures) \(minutes)" : "environ \(heures)"
            }
        }
    }

    /// Fraction ramenée dans 0…1 ; une valeur absurde (NaN, négative) vaut 0.
    public static func clampedFraction(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(1, max(0, fraction))
    }

    /// Pourcentage entier, 0…100.
    public static func percent(fraction: Double) -> Int {
        Int((clampedFraction(fraction) * 100).rounded())
    }

    /// « 42 % » (espace insécable : le nombre et son signe ne se séparent pas).
    public static func percentText(fraction: Double) -> String {
        "\(percent(fraction: fraction))\u{00A0}%"
    }

    /// Arrondi à la minute supérieure : mieux vaut annoncer un peu trop que
    /// promettre une fin qui n'arrive pas. `nil` si l'estimation est inconnue.
    public static func remainingTime(seconds: TimeInterval?) -> RemainingTime? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        if seconds < 60 { return .lessThanAMinute }
        let totalMinutes = Int((seconds / 60).rounded(.up))
        if totalMinutes < 60 { return .minutes(totalMinutes) }
        return .hours(totalMinutes / 60, minutes: totalMinutes % 60)
    }

    /// Phrase complète pour VoiceOver : « 42 pour cent, environ 2 minutes restantes ».
    public static func spokenText(fraction: Double, remainingSeconds: TimeInterval?) -> String {
        let base = "\(percent(fraction: fraction)) pour cent"
        guard let restant = remainingTime(seconds: remainingSeconds) else { return base }
        return "\(base), \(restant.spokenText) restantes"
    }
}
