/// Règle d'espace disque à respecter avant de démarrer une capture.
///
/// Un scan pèse de quelques centaines de Mo à ~2 Go : photos HEIC avec
/// profondeur, checkpoint, puis fichiers de travail de la reconstruction.
/// Apple ne publie aucun chiffre : ce seuil est une marge prudente, à
/// recalibrer d'après la taille réelle des dossiers `Images/` mesurée sur
/// iPhone (journalisée à l'étape 2).
public enum DiskSpacePolicy {
    /// 2 Gio.
    public static let requiredFreeBytes: Int64 = 2 * 1024 * 1024 * 1024

    public static func isSufficient(available: Int64) -> Bool {
        available >= requiredFreeBytes
    }

    /// Octets manquants pour atteindre le seuil (0 si suffisant), pour le message.
    public static func missingBytes(available: Int64) -> Int64 {
        max(0, requiredFreeBytes - available)
    }
}
