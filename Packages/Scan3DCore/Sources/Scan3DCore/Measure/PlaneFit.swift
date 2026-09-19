import simd

/// Plan ajusté sur un morceau de surface, autour du point touché.
///
/// L'idée qui rend la mesure fiable : au lieu de viser **un** point — ce qui
/// se paie d'une dispersion de 2 mm mesurée en tranche 2 —, on désigne une
/// **face**. Le plan s'appuie sur des dizaines de triangles ; déplacer le doigt
/// d'un millimètre ne le bouge presque pas, et l'arrondi des arêtes sort de
/// l'équation puisqu'on s'ajuste au cœur de la face.
public struct PlaneFit: Equatable, Sendable {
    /// Barycentre du morceau retenu, pondéré par l'aire : un point du plan.
    public let point: SIMD3<Float>
    /// Normale unitaire, orientée comme les faces du maillage.
    public let normal: SIMD3<Float>
    /// Rayon du voisinage retenu, en mètres (sert aussi à dessiner le repère).
    public let radius: Float
    /// Écart quadratique moyen des sommets au plan, en mètres : la « platitude ».
    public let residual: Float
    public let triangleCount: Int

    /// Distance **signée** d'un point au plan (positive du côté de la normale).
    public func distance(to autre: SIMD3<Float>) -> Float {
        simd_dot(autre - point, normal)
    }

    /// Projection d'un point sur le plan : c'est elle qu'on affiche, pour que
    /// le repère se pose exactement sur la surface visée.
    public func projection(of autre: SIMD3<Float>) -> SIMD3<Float> {
        autre - normal * distance(to: autre)
    }

    /// Vrai si les deux plans sont parallèles (même orientation ou opposée) à
    /// la tolérance donnée : seule condition pour qu'une « épaisseur » ait un sens.
    public func isParallel(to autre: PlaneFit, toleranceDegrees: Float = 10) -> Bool {
        abs(simd_dot(normal, autre.normal)) >= cos(toleranceDegrees * .pi / 180)
    }
}

extension Mesh {
    /// Un morceau de surface plan doit rassembler au moins ce nombre de triangles.
    public static let minimumPlaneTriangles = 3
    /// Cohérence des normales : `|Σ n| / Σ |n|`. À 0,98, un pli de plus de ~11°
    /// dans le voisinage fait échouer l'ajustement — c'est ce qui écarte
    /// automatiquement les arêtes et les coins.
    public static let defaultPlaneCoherence: Float = 0.98
    /// Platitude acceptée, en fraction du rayon : 6 % veut dire qu'un creux de
    /// 0,5 mm est toléré sur un voisinage de 8 mm. Au-delà, la surface est
    /// courbe et un plan mentirait.
    public static let defaultPlaneResidualRatio: Float = 0.06

    /// Rayon d'ajustement proportionné à l'objet : 4 % de sa plus grande cote,
    /// au moins 3 mm. Sur la boîte de 19 cm, cela fait 7,6 mm.
    public var planeFitRadius: Float {
        max(0.003, boundingBox.size.max() * 0.04)
    }

    /// Essaie plusieurs rayons, du plus large au plus étroit, et garde le
    /// premier qui donne un plan.
    ///
    /// Un ajustement refuse de travailler à moins d'un rayon d'une arête — ce
    /// qui est exactement ce qui protège la mesure des congés de reconstruction.
    /// Mais cela rendrait impossible de désigner un petit méplat : d'où cette
    /// recherche, qui accorde un plan plus modeste plutôt que rien.
    public func fitPlane(around center: SIMD3<Float>, searchingRadii rayons: [Float]? = nil) -> PlaneFit? {
        let depart = planeFitRadius
        for rayon in rayons ?? [depart, depart / 2, depart / 4] {
            if let ajustement = fitPlane(around: center, radius: rayon) {
                return ajustement
            }
        }
        return nil
    }

    /// Ajuste un plan sur la surface autour de `center`, ou renvoie `nil` si
    /// l'endroit n'est pas plan (arête, coin, forte courbure, trop peu de matière).
    ///
    /// La normale est la somme des produits vectoriels des triangles retenus :
    /// chacun vaut deux fois l'aire du triangle, donc la somme **pondère
    /// naturellement par l'aire**, sans calcul supplémentaire. Sa longueur
    /// comparée à la somme des aires donne la cohérence — un pli fait
    /// s'annuler les normales, et l'ajustement est refusé.
    public func fitPlane(
        around center: SIMD3<Float>,
        radius: Float? = nil,
        minimumCoherence: Float = Mesh.defaultPlaneCoherence,
        residualRatio: Float = Mesh.defaultPlaneResidualRatio
    ) -> PlaneFit? {
        let rayon = radius ?? planeFitRadius
        guard rayon > 0, center.x.isFinite, center.y.isFinite, center.z.isFinite else { return nil }

        var retenus: [Int] = []
        var sommeNormales = SIMD3<Float>.zero
        var sommeAires: Float = 0
        var barycentre = SIMD3<Float>.zero

        // Indices déjà validés par `Mesh.init` : lecture sans re-vérification.
        positions.withUnsafeBufferPointer { sommets in
            indices.withUnsafeBufferPointer { faces in
                var position = 0
                while position < faces.count {
                    let a = sommets[Int(faces[position])]
                    let b = sommets[Int(faces[position + 1])]
                    let c = sommets[Int(faces[position + 2])]

                    let proche = TriangleGeometry.closestPoint(on: a, b, c, to: center)
                    if simd_distance_squared(proche, center) <= rayon * rayon {
                        let croise = simd_cross(b - a, c - a)
                        let aire = simd_length(croise) * 0.5
                        if aire > 0 {
                            sommeNormales += croise
                            sommeAires += aire
                            barycentre += (a + b + c) / 3 * aire
                            retenus.append(position)
                        }
                    }
                    position += 3
                }
            }
        }

        guard retenus.count >= Self.minimumPlaneTriangles, sommeAires > 0 else { return nil }
        let longueur = simd_length(sommeNormales)
        guard longueur > 0, longueur / (2 * sommeAires) >= minimumCoherence else { return nil }

        let normale = sommeNormales / longueur
        let point = barycentre / sommeAires

        var sommeCarres: Float = 0
        var nombreSommets = 0
        for debut in retenus {
            for decalage in 0..<3 {
                let ecart = simd_dot(positions[Int(indices[debut + decalage])] - point, normale)
                sommeCarres += ecart * ecart
                nombreSommets += 1
            }
        }
        let residu = (sommeCarres / Float(nombreSommets)).squareRoot()
        guard residu <= residualRatio * rayon else { return nil }

        return PlaneFit(
            point: point, normal: normale, radius: rayon,
            residual: residu, triangleCount: retenus.count
        )
    }
}
