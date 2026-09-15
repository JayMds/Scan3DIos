import Foundation

/// Noms des fichiers exportés.
public enum ExportFilename {
    /// « Scan3D-2026-09-15-14h32.stl » : se trie par date dans Fichiers ou le
    /// Finder, et ne contient ni « : » ni « / » (interdits ou mal gérés selon
    /// le système de fichiers de destination).
    public static func stl(date: Date, timeZone: TimeZone = .current) -> String {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = timeZone
        let c = calendrier.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let jour = "\(c.year ?? 0)-\(deuxChiffres(c.month))-\(deuxChiffres(c.day))"
        return "Scan3D-\(jour)-\(deuxChiffres(c.hour))h\(deuxChiffres(c.minute)).stl"
    }

    private static func deuxChiffres(_ valeur: Int?) -> String {
        let valeur = valeur ?? 0
        return valeur < 10 ? "0\(valeur)" : "\(valeur)"
    }
}
