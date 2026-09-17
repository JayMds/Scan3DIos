import Foundation
import Scan3DCore

// Écrit le cube étalon de la campagne de mesure (tranche 2, étape 5).
//
// Pourquoi le fabriquer nous-mêmes plutôt que télécharger un cube de
// calibration : le fichier sort du `STLWriter` de l'app. Si la pièce imprimée
// mesure 50,0 mm au pied à coulisse, toute la chaîne est prouvée d'un coup —
// maillage en mètres, conversion en millimètres, format STL, lecture du slicer.
//
// Usage : make etalon   (ou `swift run etalon chemin/cube.stl`)

let cote = 0.050  // mètres : l'unité de `Mesh`
let demi = Float(cote / 2)
let haut = Float(cote)

// Base posée sur Y = 0 : le cube arrive à plat sur le plateau du slicer.
let sommets: [SIMD3<Float>] = [
    [-demi, 0, -demi], [demi, 0, -demi], [demi, haut, -demi], [-demi, haut, -demi],
    [-demi, 0, demi], [demi, 0, demi], [demi, haut, demi], [-demi, haut, demi],
]

// Sens trigonométrique vu de l'extérieur : les normales pointent vers le dehors.
let faces: [UInt32] = [
    4, 5, 6,  4, 6, 7,   // avant (+Z)
    1, 0, 3,  1, 3, 2,   // arrière (−Z)
    0, 4, 7,  0, 7, 3,   // gauche (−X)
    5, 1, 2,  5, 2, 6,   // droite (+X)
    7, 6, 2,  7, 2, 3,   // dessus (+Y)
    0, 1, 5,  0, 5, 4,   // dessous (−Y)
]

let destination = CommandLine.arguments.count > 1
    ? URL(filePath: CommandLine.arguments[1])
    : URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "etalon-cube-50mm.stl")

do {
    let cube = try Mesh(positions: sommets, indices: faces)
    let dimensions = Dimensions(boundingBox: cube.boundingBox)
    let donnees = try STLWriter.binaryData(for: cube)

    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try donnees.write(to: destination, options: .atomic)

    print("Cube étalon écrit : \(destination.path(percentEncoded: false))")
    print("  \(DimensionsFormatter.compact(dimensions)), \(cube.triangleCount) triangles, \(donnees.count) octets")
    print("  À imprimer à 100 %, sans mise à l'échelle, puis à mesurer au pied à coulisse :")
    print("  c'est la cote mesurée — pas les 50 mm nominaux — qui sert de référence.")
} catch {
    print("Échec : \(error)")
    exit(1)
}
