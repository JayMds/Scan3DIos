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

### Étape 1 — Mesure de face à face

Core (`Measure/`) :
- `PlaneFit.swift` — `Mesh.fitPlane(around:radius:) -> PlaneFit?` : triangles
  dont le centre est dans le rayon, normale moyenne **pondérée par l'aire**,
  puis résidu quadratique des sommets au plan. Refus si le résidu dépasse le
  seuil, si les triangles sont trop peu nombreux ou trop alignés — ce qui écarte
  naturellement les coins et les arêtes. Rayon proportionné à l'objet.
- `SurfaceMeasurement.swift` — trois mesures bien définies selon ce qui a été
  touché : **épaisseur** entre deux plans parallèles (à moins de ~10° l'un de
  l'autre), **distance point-plan**, et point-point en dernier recours. Chaque
  cas porte son libellé : l'écran dira ce qu'il a mesuré.
- Tests : sur le cube, ajustement au centre d'une face → normale exacte, résidu
  nul ; au coin → refus ; **épaisseur entre deux faces opposées = 50,000 mm quel
  que soit l'endroit touché** (le test qui prouve que la dispersion de visée a
  disparu) ; deux faces adjacentes → pas d'épaisseur.

App : `MesureModel` pose une **face** (petit disque) ou un **point** (bille)
selon le résultat de l'ajustement ; `VisionneuseView` affiche le libellé
correspondant. Aucun sélecteur de mode.

Test iPhone : mesurer la hauteur de la boîte en touchant le dessus puis le
dessous, trois fois à des endroits différents → les trois valeurs coïncident au
dixième, et tombent près de 50 mm sans calibrage.

### Étape 2 — Silhouette de l'objet (Core, `Geometry2D/`)

- `Polygon.swift` — polygone 2D : aire signée, orientation, périmètre,
  simplification Douglas-Peucker, test de point intérieur.
- `Silhouette.swift` — de `Mesh` + direction du mur + jeu vers un polygone :
  rastérisation (pas 0,1 mm), plus grande composante connexe, transformée de
  distance, marching squares sur l'isoligne `jeu`, simplification à 0,05 mm.
- Tests : disque de 20 mm dilaté de 1 mm → rayon 11 mm à 0,05 près ; carré →
  carré à coins arrondis du rayon du jeu ; forme en U dont l'entaille fait moins
  de deux fois le jeu → entaille refermée ; deux composantes → seule la plus
  grande survit ; aire et orientation conservées.

Risque : le coût de la grille. 150 mm au pas de 0,1 mm = 1500 × 1500 cellules,
soit 9 Mo en `Float` — maîtrisé, calcul sous la seconde. Pas et étendue bornés.

### Étape 3 — Solides et générateur (Core, `Solid/` et `Support/`)

- `PolygonTriangulator.swift` — triangulation par **oreilles avec ponts** pour
  les contours à trous : la brique qui permet la face avant (rectangle moins la
  poche moins les trous de vis). Pièges connus : points alignés, points doublés,
  trou tangent au contour → filtrés en amont par la simplification.
- `MeshBuilder.swift` — accumule des triangles et rend un `Mesh` ;
  `isWatertight` (chaque arête partagée par exactement deux triangles,
  orientations opposées) et volume signé.
- `WallMount.swift` — paramètres → `Mesh` : plaque, poche extrudée depuis la
  silhouette, parois, fond, trous cylindriques, hauteur de tranche d'essai.
- Tests : **toute pièce générée est étanche, orientée vers l'extérieur et de
  volume positif** (invariant vérifié sur une dizaine de jeux de paramètres) ;
  cotes attendues au dixième ; la poche contient la silhouette dilatée et rien
  de plus ; la tranche d'essai est la même pièce tronquée en hauteur.

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
