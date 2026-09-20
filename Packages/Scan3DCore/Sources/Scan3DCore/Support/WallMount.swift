import simd

/// Réglages d'un support mural. Toutes les cotes sont en mètres.
public struct WallMountParameters: Equatable, Sendable {
    /// Jeu autour de l'objet. Il doit absorber l'écart du scan — les surfaces
    /// rentrent de 2 à 3 mm (tranche 2) —, d'où un défaut généreux.
    public var clearance: Float
    /// Matière autour de la poche : c'est elle qui tient l'objet.
    public var margin: Float
    /// Épaisseur du fond, contre le mur.
    public var plateThickness: Float
    /// Hauteur des parois autour de l'objet (profondeur d'emboîtement).
    public var wallHeight: Float
    public var holeDiameter: Float
    /// Entraxe des deux trous ; 0 pour le déduire de la taille de l'objet.
    public var holeSpacing: Float
    /// Découpage des cercles de vis.
    public var holeSegments: Int

    public init(
        clearance: Float = 0.001,
        margin: Float = 0.008,
        plateThickness: Float = 0.004,
        wallHeight: Float = 0.012,
        holeDiameter: Float = 0.0045,
        holeSpacing: Float = 0,
        holeSegments: Int = 32
    ) {
        self.clearance = clearance
        self.margin = margin
        self.plateThickness = plateThickness
        self.wallHeight = wallHeight
        self.holeDiameter = holeDiameter
        self.holeSpacing = holeSpacing
        self.holeSegments = holeSegments
    }

    public var totalHeight: Float { plateThickness + wallHeight }

    /// Même pièce, tronquée en hauteur : de quoi essayer l'emboîtement en un
    /// quart d'heure d'impression au lieu de trois heures. L'ajustement se joue
    /// dans le plan, la hauteur n'y change rien.
    public func testSlice(height: Float) -> WallMountParameters {
        var reduit = self
        reduit.wallHeight = max(0.002, height - plateThickness)
        return reduit
    }

    var isValid: Bool {
        [clearance, margin, plateThickness, wallHeight, holeDiameter].allSatisfy { $0.isFinite && $0 >= 0 }
            && margin > 0 && plateThickness > 0 && wallHeight > 0 && holeDiameter > 0
            && holeSegments >= 8 && holeSpacing >= 0 && holeSpacing.isFinite
    }
}

public enum WallMountError: Error, Equatable, Sendable {
    case invalidParameters
    case silhouette(SilhouetteError)
    case triangulation(TriangulationError)
    case mesh(MeshError)
    /// Les trous de vis ne tiennent pas dans le fond de la poche.
    case holesDoNotFit
}

/// Support mural paramétrique : une plaque percée, surmontée de parois qui
/// épousent le contour de l'objet.
///
/// ```
///    vue de face                        coupe
///  ┌──────────────────────┐        ┌────────────┐  ┐
///  │   ╭──────────────╮   │        │  ╔══════╗  │  │ parois
///  │   │  ○  poche ○  │   │        │  ║      ║  │  ┘
///  │   ╰──────────────╯   │        └──╨──────╨──┘  ─ fond
///  └──────────────────────┘
/// ```
///
/// La pièce est **décomposable** : un fond, des parois, des trous. C'est ce qui
/// permet de la construire directement, sans booléen général (décision G1) — et
/// donc sans dépendance tierce.
public struct WallMount: Sendable {
    public let mesh: Mesh
    /// Contour de la poche : l'objet dilaté du jeu.
    public let pocket: Polygon
    /// Contour extérieur : la poche dilatée de la marge.
    public let outline: Polygon
    /// Trous de vis, pour l'aperçu.
    public let holes: [Polygon]
    public let parameters: WallMountParameters
    /// Plan dans lequel la pièce a été construite.
    public let plane: ProjectionPlane

    public var height: Float { parameters.totalHeight }

    public static func generate(
        for objet: Mesh,
        facing direction: ProjectionDirection,
        parameters: WallMountParameters = .init(),
        step: Float = Silhouette.defaultStep
    ) throws(WallMountError) -> WallMount {
        guard parameters.isValid else { throw .invalidParameters }
        let plan = ProjectionPlane(direction)

        // Une seule machinerie pour les deux contours : la poche est l'objet
        // dilaté du jeu, l'extérieur le même objet dilaté du jeu et de la marge.
        let poche: Polygon, exterieur: Polygon
        do {
            poche = try Silhouette.outline(of: objet, onto: plan,
                                           clearance: parameters.clearance, step: step).outer
            exterieur = try Silhouette.outline(of: objet, onto: plan,
                                               clearance: parameters.clearance + parameters.margin,
                                               step: step).outer
        } catch {
            throw .silhouette(error)
        }

        let vis = try trousDeVis(dans: poche, parameters: parameters)
        let maillage = try assembler(poche: poche, exterieur: exterieur, vis: vis,
                                     plan: plan, parameters: parameters)
        return WallMount(mesh: maillage, pocket: poche, outline: exterieur,
                         holes: vis, parameters: parameters, plane: plan)
    }

    // MARK: Trous de vis

    /// Deux trous sur l'axe vertical de la poche, assez loin des parois pour
    /// qu'il reste de la matière autour.
    private static func trousDeVis(
        dans poche: Polygon, parameters: WallMountParameters
    ) throws(WallMountError) -> [Polygon] {
        let boite = poche.boundingBox
        let centre = (boite.min + boite.max) / 2
        let hauteur = boite.max.y - boite.min.y
        let entraxe = parameters.holeSpacing > 0 ? parameters.holeSpacing : hauteur * 0.5
        let rayon = parameters.holeDiameter / 2

        var trous: [Polygon] = []
        for signe in [Float(1), -1] {
            let position = centre + SIMD2(0, signe * entraxe / 2)
            // Marge de sécurité : on vérifie un cercle deux fois plus grand.
            let controle = cercle(centre: position, rayon: rayon * 2, segments: parameters.holeSegments)
            guard controle.points.allSatisfy({ poche.contains($0) }) else { throw .holesDoNotFit }
            trous.append(cercle(centre: position, rayon: rayon, segments: parameters.holeSegments)
                .oriented(counterClockwise: false))
        }
        return trous
    }

    private static func cercle(centre: SIMD2<Float>, rayon: Float, segments: Int) -> Polygon {
        let points = (0..<segments).map { index -> SIMD2<Float> in
            let angle = 2 * Float.pi * Float(index) / Float(segments)
            return centre + SIMD2(cos(angle), sin(angle)) * rayon
        }
        // Un cercle de rayon positif décrit toujours un contour valide.
        return Polygon(points: points) ?? Polygon(points: [[0, 0], [rayon, 0], [0, rayon]])!
    }

    // MARK: Assemblage

    private static func assembler(
        poche: Polygon, exterieur: Polygon, vis: [Polygon],
        plan: ProjectionPlane, parameters: WallMountParameters
    ) throws(WallMountError) -> Mesh {
        let fond = parameters.plateThickness
        let sommet = parameters.totalHeight
        var constructeur = MeshBuilder()

        do {
            // Dessous, contre le mur : tout l'extérieur, percé des vis.
            constructeur.add(try PolygonTriangulator.triangulate(exterieur, holes: vis),
                             on: plan, depth: 0, flipped: true)
            // Fond de la poche, percé des mêmes vis.
            constructeur.add(try PolygonTriangulator.triangulate(poche, holes: vis),
                             on: plan, depth: fond)
            // Dessus des parois : la couronne entre les deux contours.
            constructeur.add(try PolygonTriangulator.triangulate(exterieur, holes: [poche]),
                             on: plan, depth: sommet)
        } catch {
            throw .triangulation(error)
        }

        constructeur.addWall(exterieur, on: plan, from: 0, to: sommet, outward: true)
        constructeur.addWall(poche, on: plan, from: fond, to: sommet, outward: false)
        for trou in vis {
            constructeur.addWall(trou, on: plan, from: 0, to: fond, outward: false)
        }

        do {
            return try constructeur.build()
        } catch {
            throw .mesh(error)
        }
    }
}

extension Mesh {
    /// Maillage mis à l'échelle — le calibrage d'un scan, appliqué à la
    /// géométrie avant d'en tirer une pièce.
    public func scaled(by factor: Float) throws(MeshError) -> Mesh {
        guard factor.isFinite, factor > 0 else { throw .nonFinitePosition }
        return try Mesh(positions: positions.map { $0 * factor }, indices: indices)
    }
}
