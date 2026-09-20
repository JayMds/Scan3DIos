import simd

public enum SilhouetteError: Error, Equatable, Sendable {
    /// Rien à projeter : maillage vide ou entièrement vu par la tranche.
    case emptyProjection
    /// Aucun contour fermé trouvé (ne devrait pas arriver : la grille déborde
    /// toujours de l'objet).
    case outlineNotFound
}

/// Contour de l'objet vu depuis le mur, **dilaté du jeu**.
///
/// Pourquoi passer par une grille plutôt que de dilater un polygone ? Parce que
/// dilater un contour **concave** en déplaçant ses sommets crée des
/// auto-intersections qu'il faut ensuite démêler — le problème classique de
/// l'offset de polygone. Par la distance, il n'existe pas : on prend l'isoligne
/// à `jeu` du champ de distance, et deux bords qui se rejoignent fusionnent
/// d'eux-mêmes. Une entaille plus étroite que deux fois le jeu se referme, ce
/// qui est exactement ce qu'il faut : l'objet n'y entrerait pas.
///
/// Trois nettoyages tombent gratuitement du même passage :
/// la plus grande composante connexe (les miettes de table et les voiles
/// détachés d'un scan disparaissent), le bruit sous la taille d'une cellule, et
/// la fermeture des boucles.
public struct Silhouette: Equatable, Sendable {
    /// Contour extérieur, sens trigonométrique.
    public let outer: Polygon
    /// Trous éventuels (objet percé de part en part), sens horaire.
    public let holes: [Polygon]
    /// Pas de grille réellement employé : il peut être élargi pour tenir dans
    /// le plafond mémoire.
    public let step: Float

    /// 0,1 mm : dix fois plus fin que le jeu typique.
    public static let defaultStep: Float = 0.0001
    /// 4 millions de cellules, soit 16 Mo de distances : au-delà, on élargit le
    /// pas plutôt que de faire tomber l'app.
    public static let maximumCells = 4_000_000

    /// Contour de `mesh` projeté sur `plane`, dilaté de `clearance`.
    public static func outline(
        of mesh: Mesh,
        onto plane: ProjectionPlane,
        clearance: Float = 0,
        step pasDemande: Float = defaultStep,
        simplification: Float? = nil,
        maximumCells plafond: Int = maximumCells
    ) throws(SilhouetteError) -> Silhouette {
        let jeu = max(0, clearance)

        // 1. Projection et emprise, élargie du jeu et de quelques cellules pour
        //    que le contour dilaté tienne entièrement dans la grille.
        var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = -minimum
        for sommet in mesh.positions {
            let plat = plane.project(sommet)
            minimum = simd_min(minimum, plat)
            maximum = simd_max(maximum, plat)
        }
        guard minimum.x <= maximum.x else { throw .emptyProjection }

        let pas = adaptedStep(pasDemande, extent: maximum - minimum + SIMD2(repeating: 2 * jeu), cap: plafond)
        let marge = jeu + 3 * pas
        let origine = minimum - SIMD2(repeating: marge)
        let etendue = (maximum + SIMD2(repeating: marge)) - origine
        let largeur = max(3, Int((etendue.x / pas).rounded(.up)) + 1)
        let hauteur = max(3, Int((etendue.y / pas).rounded(.up)) + 1)

        // 2. Rastérisation : une cellule est pleine si son centre est dans un
        //    triangle projeté. Les faces avant et arrière se superposent, ce qui
        //    est voulu — une silhouette est une union.
        var pleines = [Bool](repeating: false, count: largeur * hauteur)
        rasterize(mesh: mesh, plane: plane, origin: origine, step: pas,
                  width: largeur, height: hauteur, into: &pleines)

        // 3. Une seule région : la plus grande.
        guard keepLargestComponent(&pleines, width: largeur, height: hauteur) else {
            throw .emptyProjection
        }

        // 4. Champ de distance signé (négatif dedans), puis isoligne à `jeu`.
        let distances = signedDistance(pleines, width: largeur, height: hauteur, step: pas)
        let champ = distances.map { $0 - jeu }

        // 5. Marching squares, puis retour aux mètres.
        let boucles = marchingSquares(champ, width: largeur, height: hauteur)
        guard !boucles.isEmpty else { throw .outlineNotFound }

        let tolerance = simplification ?? (pas * 0.5)
        let aireMinimale = (3 * pas) * (3 * pas)
        var contours: [Polygon] = []
        for boucle in boucles {
            let points = boucle.map { origine + ($0 + SIMD2(repeating: 0.5)) * pas }
            guard let polygone = Polygon(points: points)?.simplified(tolerance: tolerance),
                  polygone.area >= aireMinimale
            else { continue }
            contours.append(polygone)
        }
        guard let index = contours.indices.max(by: { contours[$0].area < contours[$1].area }) else {
            throw .outlineNotFound
        }

        let exterieur = contours[index].oriented(counterClockwise: true)
        let trous = contours.enumerated()
            .filter { $0.offset != index }
            .map { $0.element.oriented(counterClockwise: false) }
        return Silhouette(outer: exterieur, holes: trous, step: pas)
    }

    // MARK: Étapes

    /// Élargit le pas si la grille dépasse le plafond : mieux vaut un contour
    /// un peu moins fin qu'un arrêt pour mémoire.
    private static func adaptedStep(_ demande: Float, extent: SIMD2<Float>, cap: Int) -> Float {
        let pas = max(demande, 1e-6)
        let cellules = (extent.x / pas) * (extent.y / pas)
        guard cellules > Float(cap) else { return pas }
        return pas * (cellules / Float(cap)).squareRoot()
    }

    private static func rasterize(
        mesh: Mesh, plane: ProjectionPlane, origin: SIMD2<Float>, step: Float,
        width: Int, height: Int, into pleines: inout [Bool]
    ) {
        for debut in stride(from: 0, to: mesh.indices.count, by: 3) {
            // Sommets en coordonnées de grille.
            let a = (plane.project(mesh.positions[Int(mesh.indices[debut])]) - origin) / step
            let b = (plane.project(mesh.positions[Int(mesh.indices[debut + 1])]) - origin) / step
            let c = (plane.project(mesh.positions[Int(mesh.indices[debut + 2])]) - origin) / step

            let aire = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
            guard abs(aire) > 1e-9 else { continue }   // triangle vu par la tranche
            let signe: Float = aire > 0 ? 1 : -1

            let bas = simd_min(simd_min(a, b), c)
            let haut = simd_max(simd_max(a, b), c)
            let i0 = max(0, Int(bas.x - 0.5)), i1 = min(width - 1, Int(haut.x + 0.5))
            let j0 = max(0, Int(bas.y - 0.5)), j1 = min(height - 1, Int(haut.y + 0.5))
            guard i0 <= i1, j0 <= j1 else { continue }

            for j in j0...j1 {
                for i in i0...i1 {
                    let centre = SIMD2(Float(i) + 0.5, Float(j) + 0.5)
                    let e0 = ((b.x - a.x) * (centre.y - a.y) - (b.y - a.y) * (centre.x - a.x)) * signe
                    let e1 = ((c.x - b.x) * (centre.y - b.y) - (c.y - b.y) * (centre.x - b.x)) * signe
                    let e2 = ((a.x - c.x) * (centre.y - c.y) - (a.y - c.y) * (centre.x - c.x)) * signe
                    if e0 >= 0, e1 >= 0, e2 >= 0 {
                        pleines[j * width + i] = true
                    }
                }
            }
        }
    }

    /// Ne garde que la plus grande région connexe (voisinage à quatre).
    /// Renvoie `false` si la grille est vide.
    private static func keepLargestComponent(_ pleines: inout [Bool], width: Int, height: Int) -> Bool {
        var etiquettes = [Int32](repeating: -1, count: pleines.count)
        var tailles: [Int] = []
        var pile: [Int] = []

        for depart in pleines.indices where pleines[depart] && etiquettes[depart] < 0 {
            let etiquette = Int32(tailles.count)
            var taille = 0
            pile.append(depart)
            etiquettes[depart] = etiquette

            while let index = pile.popLast() {
                taille += 1
                let i = index % width, j = index / width
                if i > 0 { visiter(index - 1, &pile, &etiquettes, pleines, etiquette) }
                if i < width - 1 { visiter(index + 1, &pile, &etiquettes, pleines, etiquette) }
                if j > 0 { visiter(index - width, &pile, &etiquettes, pleines, etiquette) }
                if j < height - 1 { visiter(index + width, &pile, &etiquettes, pleines, etiquette) }
            }
            tailles.append(taille)
        }

        guard let plusGrande = tailles.indices.max(by: { tailles[$0] < tailles[$1] }) else { return false }
        for index in pleines.indices {
            pleines[index] = etiquettes[index] == Int32(plusGrande)
        }
        return true
    }

    private static func visiter(
        _ voisin: Int, _ pile: inout [Int], _ etiquettes: inout [Int32],
        _ pleines: [Bool], _ etiquette: Int32
    ) {
        guard pleines[voisin], etiquettes[voisin] < 0 else { return }
        etiquettes[voisin] = etiquette
        pile.append(voisin)
    }

    /// Distance signée en mètres : négative à l'intérieur de la région.
    private static func signedDistance(
        _ pleines: [Bool], width: Int, height: Int, step: Float
    ) -> [Float] {
        let dehors = euclideanDistance(pleines, width: width, height: height)
        let dedans = euclideanDistance(pleines.map { !$0 }, width: width, height: height)
        return (0..<pleines.count).map { (dehors[$0] - dedans[$0]) * step }
    }

    /// Distance euclidienne **exacte** (en cellules) à la plus proche cellule
    /// marquée, par la méthode de Felzenszwalb : deux passes de transformée 1D,
    /// chacune en temps linéaire.
    private static func euclideanDistance(_ marquees: [Bool], width: Int, height: Int) -> [Float] {
        // Grand mais **fini** : `greatestFiniteMagnitude` déborderait à
        // l'addition et produirait des NaN dans l'enveloppe des paraboles.
        let infini: Float = 1e20
        var carres = marquees.map { $0 ? Float(0) : infini }

        var colonne = [Float](repeating: 0, count: height)
        for i in 0..<width {
            for j in 0..<height { colonne[j] = carres[j * width + i] }
            let transformee = distanceTransform1D(colonne)
            for j in 0..<height { carres[j * width + i] = transformee[j] }
        }
        var ligne = [Float](repeating: 0, count: width)
        for j in 0..<height {
            for i in 0..<width { ligne[i] = carres[j * width + i] }
            let transformee = distanceTransform1D(ligne)
            for i in 0..<width { carres[j * width + i] = transformee[i] }
        }
        return carres.map { $0 >= infini ? infini : $0.squareRoot() }
    }

    /// Enveloppe inférieure des paraboles `f[p] + (q - p)²`.
    private static func distanceTransform1D(_ f: [Float]) -> [Float] {
        let n = f.count
        guard n > 0 else { return [] }
        var d = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 1)
        var k = 0
        z[0] = -.greatestFiniteMagnitude
        z[1] = .greatestFiniteMagnitude

        for q in 1..<n {
            var s: Float = 0
            while true {
                let p = v[k]
                s = ((f[q] + Float(q * q)) - (f[p] + Float(p * p))) / Float(2 * q - 2 * p)
                if k > 0, s <= z[k] { k -= 1 } else { break }
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .greatestFiniteMagnitude
        }

        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) { k += 1 }
            let p = v[k]
            d[q] = Float((q - p) * (q - p)) + f[p]
        }
        return d
    }

    // MARK: Marching squares

    /// Isoligne zéro du champ, en coordonnées de grille. Chaque boucle est
    /// fermée et orientée avec l'intérieur (champ négatif) **à gauche**, ce qui
    /// donne des contours extérieurs dans le sens trigonométrique et des trous
    /// dans le sens horaire.
    private static func marchingSquares(_ champ: [Float], width: Int, height: Int) -> [[SIMD2<Float>]] {
        /// Une arête de la grille porte au plus un passage par zéro : elle sert
        /// donc de clé pour recoller les segments, sans jamais comparer des
        /// flottants.
        func arete(horizontale: Bool, _ i: Int, _ j: Int) -> Int {
            2 * (j * width + i) + (horizontale ? 0 : 1)
        }
        func valeur(_ i: Int, _ j: Int) -> Float { champ[j * width + i] }
        func interpole(_ a: SIMD2<Float>, _ va: Float, _ b: SIMD2<Float>, _ vb: Float) -> SIMD2<Float> {
            let ecart = va - vb
            let t = abs(ecart) < 1e-12 ? 0.5 : va / ecart
            return a + (b - a) * min(max(t, 0), 1)
        }

        var suivant: [Int: (fin: Int, debut: SIMD2<Float>, arrivee: SIMD2<Float>)] = [:]

        for j in 0..<(height - 1) {
            for i in 0..<(width - 1) {
                let v0 = valeur(i, j), v1 = valeur(i + 1, j)
                let v2 = valeur(i + 1, j + 1), v3 = valeur(i, j + 1)
                var cas = 0
                if v0 < 0 { cas |= 1 }
                if v1 < 0 { cas |= 2 }
                if v2 < 0 { cas |= 4 }
                if v3 < 0 { cas |= 8 }
                guard cas != 0, cas != 15 else { continue }

                let p0 = SIMD2(Float(i), Float(j)), p1 = SIMD2(Float(i + 1), Float(j))
                let p2 = SIMD2(Float(i + 1), Float(j + 1)), p3 = SIMD2(Float(i), Float(j + 1))
                let bas = (arete(horizontale: true, i, j), interpole(p0, v0, p1, v1))
                let droite = (arete(horizontale: false, i + 1, j), interpole(p1, v1, p2, v2))
                let haut = (arete(horizontale: true, i, j + 1), interpole(p3, v3, p2, v2))
                let gauche = (arete(horizontale: false, i, j), interpole(p0, v0, p3, v3))

                func relier(_ de: (Int, SIMD2<Float>), _ vers: (Int, SIMD2<Float>)) {
                    suivant[de.0] = (fin: vers.0, debut: de.1, arrivee: vers.1)
                }

                switch cas {
                case 1: relier(bas, gauche)
                case 2: relier(droite, bas)
                case 3: relier(droite, gauche)
                case 4: relier(haut, droite)
                case 6: relier(haut, bas)
                case 7: relier(haut, gauche)
                case 8: relier(gauche, haut)
                case 9: relier(bas, haut)
                case 11: relier(droite, haut)
                case 12: relier(gauche, droite)
                case 13: relier(bas, droite)
                case 14: relier(gauche, bas)
                case 5, 10:
                    // Cas ambigus : le centre décide si les deux coins de même
                    // signe se touchent ou non.
                    let centre = (v0 + v1 + v2 + v3) / 4
                    let joints = (cas == 5) == (centre < 0)
                    if joints {
                        relier(droite, bas)
                        relier(gauche, haut)
                    } else {
                        relier(bas, gauche)
                        relier(haut, droite)
                    }
                default: break
                }
            }
        }

        var boucles: [[SIMD2<Float>]] = []
        var vues = Set<Int>()
        // `sorted()` n'est pas une coquetterie : l'ordre d'un dictionnaire varie
        // d'une exécution à l'autre, la boucle démarrerait donc à un endroit
        // différent à chaque appel — et la simplification, qui dépend du point
        // de départ, rendrait un contour légèrement différent. Deux appels
        // identiques doivent donner la même pièce.
        for depart in suivant.keys.sorted() where !vues.contains(depart) {
            var boucle: [SIMD2<Float>] = []
            var courante = depart
            while let segment = suivant[courante], !vues.contains(courante) {
                vues.insert(courante)
                boucle.append(segment.debut)
                courante = segment.fin
            }
            if boucle.count >= 3 { boucles.append(boucle) }
        }
        return boucles
    }
}
