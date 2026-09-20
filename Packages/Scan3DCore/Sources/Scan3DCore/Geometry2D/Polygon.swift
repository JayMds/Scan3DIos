import simd

/// Contour fermé dans le plan, en mètres.
///
/// Le dernier point est relié au premier sans qu'on le répète. L'orientation
/// porte un sens : **sens trigonométrique** (aire signée positive) pour un
/// contour extérieur, **sens horaire** pour un trou. C'est la convention des
/// triangulateurs, et celle que produit la silhouette.
public struct Polygon: Equatable, Sendable {
    public let points: [SIMD2<Float>]

    /// `init?` : moins de trois points, ou une coordonnée non finie, ne décrit
    /// aucun contour.
    public init?(points: [SIMD2<Float>]) {
        guard points.count >= 3,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return nil }
        self.points = points
    }

    /// Aire signée (formule du lacet) : positive dans le sens trigonométrique.
    public var signedArea: Float {
        var somme: Float = 0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            somme += a.x * b.y - b.x * a.y
        }
        return somme / 2
    }

    public var area: Float { abs(signedArea) }

    public var isCounterClockwise: Bool { signedArea > 0 }

    public var perimeter: Float {
        var somme: Float = 0
        for index in points.indices {
            somme += simd_distance(points[index], points[(index + 1) % points.count])
        }
        return somme
    }

    public var boundingBox: (min: SIMD2<Float>, max: SIMD2<Float>) {
        var minimum = points[0], maximum = points[0]
        for point in points.dropFirst() {
            minimum = simd_min(minimum, point)
            maximum = simd_max(maximum, point)
        }
        return (minimum, maximum)
    }

    /// Même contour, parcouru dans l'autre sens.
    public func reversed() -> Polygon {
        Polygon(points: points.reversed()) ?? self
    }

    /// Même contour, orienté comme demandé.
    public func oriented(counterClockwise: Bool) -> Polygon {
        isCounterClockwise == counterClockwise ? self : reversed()
    }

    /// Point à l'intérieur ? Lancer de rayon horizontal : on compte les arêtes
    /// traversées à droite du point ; un nombre impair signifie « dedans ».
    public func contains(_ point: SIMD2<Float>) -> Bool {
        var dedans = false
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            guard (a.y > point.y) != (b.y > point.y) else { continue }
            let traversee = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
            if point.x < traversee { dedans.toggle() }
        }
        return dedans
    }

    /// Contour allégé par l'algorithme de Douglas-Peucker : on ne garde que les
    /// points qui s'écartent de plus de `tolerance` de la corde. Un contour de
    /// marching squares compte des milliers de points pour une forme simple ;
    /// après simplification, il en reste quelques dizaines.
    public func simplified(tolerance: Float) -> Polygon {
        guard tolerance > 0, points.count > 3 else { return self }
        // Un contour fermé n'a pas d'extrémités : on le coupe au point le plus
        // éloigné du premier, pour que la simplification ne déforme pas un bout.
        var indexOppose = 0
        var distanceMax: Float = -1
        for index in points.indices {
            let distance = simd_distance(points[0], points[index])
            if distance > distanceMax {
                distanceMax = distance
                indexOppose = index
            }
        }
        let premiere = Array(points[0...indexOppose])
        let seconde = Array(points[indexOppose...]) + [points[0]]

        var resultat = Self.douglasPeucker(premiere, tolerance: tolerance)
        resultat.removeLast()
        resultat += Self.douglasPeucker(seconde, tolerance: tolerance).dropLast()
        return (Polygon(points: resultat) ?? self).removingCollinear(tolerance: tolerance)
    }

    /// Retire les sommets qui n'apportent rien : deux points confondus, ou un
    /// point posé sur la droite qui joint ses voisins.
    ///
    /// Ce n'est pas de la coquetterie. Les deux points de coupure du parcours
    /// survivent toujours à la simplification, même alignés ; le triangulateur,
    /// lui, supprime un sommet aligné. La face et la paroi construites depuis le
    /// même contour n'auraient alors plus les mêmes arêtes, et la pièce ne
    /// serait **pas étanche** — invisible à l'œil, fatal au slicer.
    public func removingCollinear(tolerance: Float) -> Polygon {
        var restants = points
        var aRetirer = true
        while aRetirer, restants.count > 3 {
            aRetirer = false
            for index in restants.indices {
                let nombre = restants.count
                let avant = restants[(index + nombre - 1) % nombre]
                let apres = restants[(index + 1) % nombre]
                guard Self.distanceAuSegment(restants[index], avant, apres) <= tolerance else { continue }
                restants.remove(at: index)
                aRetirer = true
                break
            }
        }
        return Polygon(points: restants) ?? self
    }

    private static func douglasPeucker(_ chaine: [SIMD2<Float>], tolerance: Float) -> [SIMD2<Float>] {
        guard chaine.count > 2 else { return chaine }
        let premier = chaine[0], dernier = chaine[chaine.count - 1]

        var indexMax = 0
        var ecartMax: Float = 0
        for index in 1..<(chaine.count - 1) {
            let ecart = distanceAuSegment(chaine[index], premier, dernier)
            if ecart > ecartMax {
                ecartMax = ecart
                indexMax = index
            }
        }
        guard ecartMax > tolerance else { return [premier, dernier] }

        let gauche = douglasPeucker(Array(chaine[0...indexMax]), tolerance: tolerance)
        let droite = douglasPeucker(Array(chaine[indexMax...]), tolerance: tolerance)
        return gauche.dropLast() + droite
    }

    private static func distanceAuSegment(
        _ point: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>
    ) -> Float {
        let ab = b - a
        let longueurCarree = simd_length_squared(ab)
        guard longueurCarree > 0 else { return simd_distance(point, a) }
        let t = min(max(simd_dot(point - a, ab) / longueurCarree, 0), 1)
        return simd_distance(point, a + ab * t)
    }
}
