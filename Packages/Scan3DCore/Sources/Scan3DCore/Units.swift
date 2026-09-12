/// Conversions d'unités entre le monde du scan et le monde de l'impression.
///
/// RealityKit et Object Capture expriment tout en **mètres**, alors que les
/// slicers (Bambu Studio, PrusaSlicer…) lisent STL et 3MF en **millimètres**.
/// Centraliser la conversion ici évite l'erreur classique de la pièce
/// imprimée 1000 fois trop petite.
public enum Units {
    public static let metersToMillimeters: Double = 1000

    public static func millimeters(fromMeters meters: Double) -> Double {
        meters * metersToMillimeters
    }

    public static func meters(fromMillimeters millimeters: Double) -> Double {
        millimeters / metersToMillimeters
    }
}
