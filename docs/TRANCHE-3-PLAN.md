# Plan — Tranche 3 « Générer un support »

## Contexte

La tranche 2 a livré ses quatre étapes de code (bibliothèque, mesure point à
point, calibrage, diagnostic de hauteur), toutes poussées. Seule la **campagne
de mesure** reste ouverte : le cube étalon ne peut pas être imprimé tout de
suite. Écart assumé à la règle « on ne commence pas la tranche N+1 avant la
validation de la N » : la campagne se poursuit en parallèle, et l'étape 1 de
cette tranche rendra ses relevés **définitifs** plutôt que de les périmer.

Objectif (`ROADMAP.md`) : un support mural **imprimé et monté** pour
l'interphone Wi-Fi. Spec : `TRANCHE-3.md`.

Ce que les mesures de la tranche 2 imposent au dessin :

- l'erreur du scan est **additive** — les surfaces rentrent de 2 à 3 mm, les
  arêtes s'arrondissent. La silhouette extraite du maillage est donc **plus
  petite que l'objet réel** : c'est le jeu qui doit absorber cet écart ;
- un scan porte des artefacts (voiles, miettes de table) qui ne doivent pas
  entrer dans la cavité ;
- imprimer trois heures pour découvrir que ça ne rentre pas est inacceptable :
  le générateur doit savoir produire une **tranche d'essai** de 15 à 20 mm.

---

## A. Faits vérifiés (18/09/2026)

- **Manifold** : licence **Apache-2.0**, build CMake, aucune dépendance
  obligatoire (TBB optionnel), exige un maillage *manifold* en entrée, bindings
  C disponibles, utilisé par des apps iOS. Écarté pour cette tranche (décision
  G1), pas condamné.
- **Foundation n'expose aucune API ZIP** (seulement le deflate brut de
  `compression.h`) : un 3MF suppose d'écrire le conteneur nous-mêmes.
- **3MF** = paquet OPC : `[Content_Types].xml`, `_rels/.rels`,
  `3D/3dmodel.model` (XML, `unit="millimeter"`).
- Swift 6.3.3 ; l'interop C++ de SwiftPM (`.interoperabilityMode(.Cxx)`) existe
  mais devient inutile avec G1.
- Déjà dans le dépôt, à réutiliser : `Mesh` (validation, boîte englobante),
  `MeshLoader`, `STLWriter.binaryData(for:scale:)`, `STLExporter` +
  `FeuilleDePartage`, `OrbitCamera` + `Ray` + `Mesh.firstIntersection`,
  `ScanRecord.calibratedDimensions`, `MillimeterInput`.

## B. Décisions validées par Jinkuro (18/09/2026)

| Décision | Choix | Conséquence |
|----------|-------|-------------|
| G1 Moteur géométrique | **Construction directe en Swift** | Faces planes exactes et trous ronds, zéro dépendance tierce, tout testable sur Mac. En échange, la pièce doit rester décomposable : pas de booléen général. |
| G2 Cavité | **Silhouette fidèle**, concavités comprises | Passe par une **grille 2D** : rastérisation, transformée de distance, marching squares. C'est ce qui rend la dilatation d'un contour concave robuste — aucune auto-intersection à résoudre, et les entailles plus étroites que deux fois le jeu se referment d'elles-mêmes, ce qui est le comportement voulu. |
| G3 Export | **STL d'abord**, 3MF en dernière étape | L'écrivain STL est déjà validé dans Bambu Studio ; le 3MF peut glisser à la tranche 4 sans bloquer l'impression. |
| G4 Mesure de face à face | **Étape 1** de cette tranche | Clôt la piste retenue de la tranche 2 et fiabilise la campagne en cours. |

Options écartées, pour mémoire :

- **Manifold (C++)** : booléens robustes et éprouvés, mais une à deux étapes de
  plomberie (CMake → SwiftPM/Xcode, iOS arm64 et simulateur), une dépendance
  tierce à suivre, et **pas d'offset natif** — le jeu serait resté à notre
  charge. À reconsidérer le jour où un booléen général devient nécessaire.
- **Champ de distance 3D + marching cubes** : tout devient min/max et le jeu
  n'est qu'une soustraction, mais une plaque échantillonnée a des faces en
  escalier (±0,25 mm à 0,5 mm de résolution) — rédhibitoire pour une pièce qui
  s'appuie contre un mur.
- **Silhouette convexe** : un tiers du code, mais une poche trop large partout
  où l'objet est creux, et surtout une sensibilité totale aux valeurs
  aberrantes — un seul voile détaché élargirait l'enveloppe.

## C. Étapes

Convention : « Core » = `Packages/Scan3DCore/Sources/Scan3DCore/`, « App » =
`Scan3D/`. Chaque étape : `make test-core` + `make build-check` (+ build
simulateur), explication fichier par fichier, revue sécurité / accessibilité,
scénario iPhone, commit local ; push après le test de Jinkuro.

### Étape 0 — Spec et plan ✅ (19/09/2026)

`docs/TRANCHE-3.md`, `docs/TRANCHE-3-PLAN.md`, mise à jour de `ROADMAP.md`
(décisions G1-G4, sort des trois pistes de précision) et de `CLAUDE.md`
(tranche en cours, moteur géométrique).

### Étape 1 — Mesure de face à face — livrée le 19/09/2026, test iPhone en attente

Core (`Measure/`) :
- `TriangleGeometry.swift` — point d'un triangle le plus proche d'un point
  (algorithme d'Ericson). Sert à décider quels triangles sont « autour » du
  doigt : juger par le centre d'un triangle exclurait une grande face dont on
  touche le bord.
- `PlaneFit.swift` — `Mesh.fitPlane(around:radius:)` : la normale est la
  **somme des produits vectoriels** des triangles retenus, ce qui pondère par
  l'aire sans calcul supplémentaire. Trois refus possibles : cohérence
  `|Σn| / Σ|n|` sous 0,98 (un pli — donc une arête ou un coin), résidu au-delà
  de 6 % du rayon (une surface courbe), moins de trois triangles. Rayon = 4 %
  de la plus grande cote, au moins 3 mm. Variante
  `fitPlane(around:searchingRadii:)` qui dégrade le rayon (r, r/2, r/4) : sans
  elle, impossible de désigner un méplat proche d'une arête.
- `SurfaceMeasurement.swift` — `MeasurementTarget` (un point, ou une face avec
  l'ancre du toucher projetée dessus) et les trois sémantiques : **épaisseur**
  entre deux plans parallèles (moins de 10° d'écart) et **non confondus**,
  **distance point-plan**, point-point sinon. La coplanarité est traitée : deux
  touchers sur la même face mesurent la distance qui les sépare, et non une
  épaisseur nulle.
- Tests (`PlaneFitTests.swift`, 2 suites, 13 tests) : face du cube → normale
  exacte et résidu nul ; arête et coin → refus ; sphère → refus dès que le plan
  mentirait ; rayon dégressif près d'une arête ; distances signées et
  projection ; **épaisseur = 50,00 mm pour trois couples de touchers très
  différents** — le test qui prouve que la dispersion de visée a disparu ;
  faces adjacentes, même face, point-face, calibrage.

App :
- `MesureModel` — ajustement à chaque toucher ; **disque** posé à plat pour une
  face, **bille** pour un point ; annonces « Face A posée » ou « Point A posé » ;
  le journal nomme la mesure.
- `SurfaceMeasurement+Texte.swift` — les libellés (les mots sont à l'app, la
  géométrie à `Scan3DCore`).
- `VisionneuseView` — libellé sous la distance, « Effacer la mesure », et un
  texte d'aide qui invite à viser une surface plutôt qu'un point.

**Banc d'essai (simulateur, 19/09/2026)** : boîte de 190 × 57 × 160 mm,
subdivisée à 5 mm comme un scan réel ; séquence automatique — toucher du
dessus, rotation sous l'objet, toucher du dessous. Résultat affiché :
**« 57,0 mm — Épaisseur entre deux faces »**, disque posé à plat sur la face.

Deux limites, découvertes au banc et assumées :
- l'ajustement **refuse à moins d'un rayon d'une arête**. C'est précisément ce
  qui protège la mesure des congés de reconstruction ; la recherche dégressive
  rattrape les petits méplats.
- il lui faut **plusieurs triangles sous le rayon** : sur un maillage grossier
  (triangles de 30 mm), aucune face n'est reconnue et l'app retombe sur des
  points. Un scan d'iPhone, avec ses triangles de 2 à 3 mm, est largement assez
  dense.

Test iPhone : mesurer la hauteur de la boîte en touchant le dessus puis le
dessous, **trois fois à des endroits différents** → les trois valeurs doivent
coïncider au dixième et tomber près de 50 mm sans calibrage ; le libellé doit
indiquer « Épaisseur entre deux faces ». Viser ensuite un coin : le repère doit
redevenir une bille et le libellé « Entre deux points ».

### Étape 2 — Silhouette de l'objet — livrée le 20/09/2026

Core (`Geometry2D/`) :
- `Polygon.swift` — contour fermé : aire signée (donc orientation : sens
  trigonométrique pour un extérieur, horaire pour un trou), périmètre, boîte
  englobante, test d'appartenance par lancer de rayon, simplification
  Douglas-Peucker adaptée aux contours **fermés** (coupés au point le plus
  éloigné du premier, pour ne pas déformer un bout).
- `ProjectionPlane.swift` — les six directions de projection, avec des axes
  choisis pour que le repère (u, v, normale) reste **direct** : sans cette
  précaution, la silhouette serait le miroir de l'objet et la pièce ne
  s'emboîterait que dans son reflet.
- `Silhouette.swift` — `Mesh` + direction + jeu → contour extérieur et trous :
  1. rastérisation des triangles projetés (pas 0,1 mm par défaut) ;
  2. **plus grande composante connexe** — les miettes de table et les voiles
     détachés d'un scan disparaissent ici, sans toucher au maillage mesuré ;
  3. **champ de distance signé** (Felzenszwalb, exact, deux passes linéaires) ;
  4. **marching squares** sur l'isoligne `jeu`, avec les cas ambigus tranchés
     par la valeur au centre, et recollage des segments par identifiant d'arête
     — aucune comparaison de flottants ;
  5. simplification, tri du contour extérieur et des trous.
- Tests (`Geometry2DTests.swift`, 3 suites, 12 tests) : disque de 10 mm dilaté
  de 1 mm → rayon 11 mm à 0,4 mm près ; carré → coins arrondis du rayon du jeu,
  aire = carré + quatre bandes + un disque ; entaille de 3 mm **refermée** par
  un jeu de 2 mm, conservée par un jeu de 0,3 mm ; miette ignorée ; anneau →
  un trou, orienté à l'envers, rétréci du jeu ; plafond mémoire respecté.

**Deux limites, chiffrées** :
- le contour est échantillonné au centre des cellules : il porte un biais
  d'environ une demi-cellule, soit 0,05 mm au pas par défaut. Les tolérances
  des tests le disent explicitement (`toleranceAire`), au lieu de le cacher ;
- la grille est plafonnée à 4 millions de cellules (16 Mo) ; au-delà, le pas
  s'élargit tout seul plutôt que de faire tomber l'app. Sur un objet de 19 cm au
  pas de 0,1 mm, on est à 3,6 millions de cellules — environ 8 s **en debug**
  sur Mac, donc quelques secondes en release : la génération devra tourner hors
  du fil principal (étape 4).

Aucun changement visible dans l'app à cette étape : la vérification est la
suite de tests.

### Étape 3 — Solides et générateur — livrée le 20/09/2026

Core (`Solid/` et `Support/`) :
- `PolygonTriangulator.swift` — triangulation par **oreilles**, avec des
  **ponts** vers les trous : deux sommets dupliqués transforment un contour
  troué en contour simple. Le pont vise le sommet visible le plus à droite,
  affiné par le test d'Eberly (un sommet rentrant dans le triangle de visée
  l'emporte), sans quoi le pont traverserait la matière.
- `MeshBuilder.swift` — assemble des triangles en **soudant** les sommets
  (1 µm). La soudure n'est pas une optimisation : sans elle, aucune arête ne
  serait partagée et le contrôle d'étanchéité n'aurait rien à mesurer.
  Fournit aussi `addWall` (paroi verticale le long d'un contour, normales
  dedans ou dehors) et la pose d'une triangulation à plat.
- `Mesh.isWatertight`, `Mesh.openEdgeCount`, `Mesh.signedVolume`,
  `Mesh.scaled(by:)` — les invariants d'une pièce imprimable.
- `WallMount.swift` — réglages (jeu, marge, épaisseur du fond, hauteur des
  parois, diamètre et entraxe des vis) → `Mesh`. Six faces assemblées : dessous
  percé, fond de poche percé, couronne du dessus, paroi extérieure, paroi de
  poche, parois des trous. La **tranche d'essai** n'est qu'un réglage de hauteur.
- Tests (`SolidTests.swift` et `WallMountTests.swift`, 3 suites, 20 tests) :
  aires conservées par la triangulation (carré, L concave, trou carré, deux
  trous ronds, points alignés, trou hors contour refusé) ; cube étanche, face
  manquante détectée, cube retourné de volume négatif ; **invariant sur cinq
  jeux de réglages et sur les six orientations** ; volume déduit des aires des
  contours à 2 % près ; cotes ; tranche d'essai ; trous trop gros refusés.

**Deux défauts que seul l'invariant pouvait attraper** — invisibles à l'œil,
fatals à l'usage :
1. la simplification d'un contour fermé conservait ses deux **points de
   coupure**, même alignés ; le triangulateur, lui, supprime un sommet aligné.
   Face et paroi construites depuis le même contour n'avaient donc plus les
   mêmes arêtes : pièce non étanche. Corrigé à la source par
   `Polygon.removingCollinear`.
2. le recollage des segments de marching squares parcourait un **dictionnaire**,
   dont l'ordre varie d'une exécution à l'autre : la boucle démarrait à un
   endroit différent, et la simplification rendait un contour légèrement
   différent. Deux appels identiques donnent maintenant la même pièce, et un
   test le vérifie.

Aucun changement visible dans l'app à cette étape.

### Étape 4 — L'écran « Créer un support » (App, `Features/Support/`)

- `SupportModel.swift` — choix de la **face contre le mur** (les six directions
  de la boîte englobante), paramètres, génération hors du fil principal,
  mémorisation dans `scan.json` (nouveau champ optionnel, décodage validé).
- `SupportView.swift` — paramètres en formulaire, **aperçu 3D** (support opaque,
  objet en transparence), « Exporter le support » et « Exporter une tranche
  d'essai ».
- Refactor : extraire de `VisionneuseView` la partie caméra et gestes
  (`SceneOrbite`) pour la partager avec l'aperçu du support.
- `DetailScanView` : nouvelle action « Créer un support ».

### Étape 5 — Impression, réglage du jeu, montage

1. Générer le support de l'interphone, exporter la **tranche d'essai**,
   l'imprimer (~15 min).
2. Essayer l'emboîtement ; ajuster le jeu ; réimprimer la tranche si besoin.
3. Imprimer le support entier, monter au mur, consigner dans
   `docs/MESURES-TRANCHE-3.md` : jeu retenu, écart entre cote scannée et cote
   réelle, temps d'impression, verdict.

### Étape 6 — Export 3MF (si le temps le permet)

Core : écriture du conteneur ZIP (entrées **stockées**, sans compression, comme
USDZ) puis du XML `3dmodel.model` en millimètres. Tests : archive relue par
`unzip`, XML validé, fichier ouvert dans Bambu Studio. Peut glisser à la
tranche 4 sans rien bloquer.

## D. Vérification

1. `make test-core` et `make build-check` verts à chaque étape, plus le build
   simulateur.
2. Invariant central : **toute pièce générée est étanche et de volume positif**,
   vérifié par test automatique à chaque jeu de paramètres.
3. Scénario iPhone par étape, résultats consignés ici.
4. Critère ROADMAP : le support de l'interphone est **imprimé et monté**.

## Réutilisation

`Mesh`, `MeshLoader`, `Dimensions`, `Units`, `STLWriter` (avec son paramètre
d'échelle), `STLExporter`, `FeuilleDePartage`, `OrbitCamera`, `Ray`,
`Mesh.firstIntersection`, `ScanRecord` (+ `calibratedDimensions`),
`ScanLibrary`, `MillimeterInput`, et le banc d'essai du simulateur (argument de
lancement + capture d'écran) pour vérifier l'aperçu 3D sans iPhone.
