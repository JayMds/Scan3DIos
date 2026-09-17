// swift-tools-version: 6.0
// Paquet de logique pure : aucune dépendance à l'UI ni au matériel.
// Il compile pour iOS (l'app) ET macOS (tests rapides + futur compagnon Mac).
import PackageDescription

let package = Package(
    name: "Scan3DCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Scan3DCore", targets: ["Scan3DCore"]),
        // Outil de développement (macOS) : écrit le cube étalon de la campagne
        // de mesure. L'app iOS ne dépend que de la bibliothèque.
        .executable(name: "etalon", targets: ["Etalon"]),
    ],
    targets: [
        .target(name: "Scan3DCore"),
        .executableTarget(name: "Etalon", dependencies: ["Scan3DCore"]),
        .testTarget(name: "Scan3DCoreTests", dependencies: ["Scan3DCore"]),
    ]
)
