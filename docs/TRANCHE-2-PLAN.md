# Tranche 2 — Plan d'implémentation

Complète `TRANCHE-2.md` (la spec). Référence des sessions « Implémente
l'étape N du plan de la tranche 2 ». Établi le 15/09/2026 après vérification
des API dans la documentation Apple (Xcode 26.6, SDK iOS 26.5, cible iOS 18)
et validé par Jinkuro.

## A. API vérifiées dans la documentation Apple (15/09/2026)

- `RealityView(make:update:placeholder:)` — iOS 18. `make` est `async` (chargement sans figer l'UI).
- `RealityViewCameraContent` — iOS 18 : `camera`, `cameraTarget` (cible de l'orbite), `entities`.
  Conforme à `RealityCoordinateSpaceProjecting` : `ray(through:in:to:) -> (origin:, direction:)?`,
  `hitTest(point:in:query:mask:)`, `entity(at:in:)`, `project`, `unproject` — iOS 18.
- `.realityViewCameraControls(_:)` — iOS 18 : `.orbit`, `.pan`, `.tilt`, `.dolly`.
- `Entity(contentsOf:withName:) async throws` — iOS 18, USD/USDZ.
- `SpatialTapGesture.Value.location` et `.location3D` — iOS 16 ; `.targetedToAnyEntity()` — iOS 18.
- `ShapeResource.generateStaticMesh(from:) async throws` — iOS 18 (repli seulement).
- `.accessibilityDirectTouch(_:options:)` — iOS 17 (`.requiresActivation` pour VoiceOver).
- SwiftData `ModelConfiguration` : **aucune option de protection de fichiers ni d'exclusion de
  sauvegarde** dans l'API → pèse dans la décision E1.
- SceneKit : **déprécié (soft) depuis iOS 26** (WWDC25) → écarté.
- `QLThumbnailGenerator` — iOS 13, support USDZ non documenté → vignettes hors périmètre.

### Incertitudes et mitigations

| # | Incertitude | Mitigation |
|---|-------------|------------|
| 1 | Obtenir un rayon depuis un toucher : `ray(through:in:to:)` n'est accessible que via `content` (dans `make`/`update`), pas dans le geste. | Essai en début d'étape 2 : le geste mémorise le point 2D, `update` calcule le rayon. Repli : `targetedToAnyEntity()` + `location3D` sur une collision `generateStaticMesh`. |
| 2 | Même repère entre l'entité chargée par RealityKit et `MeshLoader` (Model I/O ignore `metersPerUnit`/`upAxis`, RealityKit peut les appliquer). | Racine du modèle laissée à l'identité ; test terrain : distance entre deux coins ≈ cotes de la boîte englobante. |
| 3 | `realityViewCameraControls(.orbit)` exige-t-il une caméra virtuelle et une `cameraTarget` ? | Essai d'étape 2 ; `cameraTarget` = entité au centre de la boîte englobante. |
| 4 | Temps d'intersection rayon / 50 k triangles en force brute. | Test de performance dans `Scan3DCore` (objectif < 20 ms) ; structure accélératrice seulement si nécessaire. |
| 5 | Cause de l'écart de hauteur (fond bouché trop bas ? dessus bombé ?). | Étape 4 : diagnostic chiffré avec l'outil de mesure avant toute correction. |
| 6 | `scan.json` venu d'ailleurs (tranche 4) ou d'une ancienne version. | Champ `schemaVersion`, décodage validé, taille maximale. |

---

## B. Décisions validées par Jinkuro (15/09/2026)

| Décision | Choix | Conséquence |
|----------|-------|-------------|
| E1 Stockage de la bibliothèque | **`scan.json` dans chaque dossier `Scans/<UUID>/`** (pas SwiftData) | Supprimer le dossier = supprimer le scan ; protection `.complete` héritée (D2) ; testable dans `Scan3DCore` ; dossier = unité de transfert vers le Mac. `CLAUDE.md` (stack) à mettre à jour. |
| E2 Portée du calibrage | **Par scan** | Facteur stocké dans `scan.json`, appliqué aux cotes, mesures et export du scan ; annulable. |
| E3 Visionneuse et mesure | **`RealityView` + intersection calculée dans `Scan3DCore`** | Modèle texturé affiché ; point touché calculé sur le même `Mesh` que cotes, calibrage et export ; testable sur Mac. |
| E4 Hauteur | **Diagnostic d'abord**, plan de coupe seulement si mesuré | Étape 4 conditionnelle. |

---

## C. Étapes

Convention inchangée : « Core » = `Packages/Scan3DCore/Sources/Scan3DCore/`, « App » = `Scan3D/`.
Chaque étape : `make test-core` + `make build-check` (+ build simulateur), explication fichier par
fichier, revue sécurité / accessibilité, scénario iPhone, commit local ; push après le test de
Jinkuro.

### Étape 0 — Spec, plan et vérifications en attente ✅ (15/09/2026 ; tests iPhone de la tranche 1 à faire par Jinkuro)

- `docs/TRANCHE-2.md` — spec au format de `TRANCHE-1.md` : parcours (bibliothèque → détail →
  visionneuse / mesure → calibrage → export), principes UX, spec technique, sécurité, accessibilité,
  scénario de test, protocole des 3 objets.
- `docs/TRANCHE-2-PLAN.md` — sections A à D de ce plan.
- `docs/MESURES-TRANCHE-2.md` — gabarit de campagne (tableau par objet : référence physique, boîte
  englobante, point à point, après calibrage).
- `CLAUDE.md` — stack : « bibliothèque en `scan.json` par dossier (tranche 2) » au lieu de SwiftData ;
  tranche en cours → `docs/TRANCHE-2.md`. `ROADMAP.md` — décisions E1-E4.
- Jinkuro : tests iPhone non rapportés de la tranche 1 (point ouvert 4 du bilan).

### Étape 1 — Bibliothèque des scans (et découpage de `ScanFlowModel`) — livrée le 15/09/2026, test iPhone en attente

Core (`Sources/Scan3DCore/Library/`) :
- `ScanRecord.swift` — `struct ScanRecord: Codable, Equatable, Sendable,
  Identifiable` : `id`, `name`, `createdAt` (arrondie à la seconde),
  `triangleCount`, `dimensions` (brutes), `calibration?`. `schemaVersion`
  n'est pas une propriété : écrit à 1, lu **avant** le reste (une version
  future a peut-être une autre structure). Décodage validé : nom 1-80
  caractères visibles après nettoyage (`sanitizedName` : contrôles et
  retours à la ligne → espaces fusionnés), triangles 1…2 M, date ISO 8601
  écrite par le type lui-même, cotes et calibrage revalidés. Erreurs
  `ScanRecordError` ; `rename(to:)` ; `defaultName(date:)` → « Scan du
  15/09/2026 à 14:32 » ; `recoveredName` → « Scan récupéré ».
- `ScanLibrary.swift` — `inspect(scansDirectory:)` classe chaque dossier :
  `complete`, `missingRecord`, `invalidRecord` (corrompu, trop gros,
  identifiant incohérent), `unreadableRecord` (lecture refusée → jamais
  réécrite), `newerRecord(version:)` (jamais touchée), `incomplete` (pas de
  modèle) ; `shouldPurge`, `shouldRemoveCaptureData` (photos restées à côté
  d'un modèle). Seuls les dossiers nommés par un UUID en majuscules sont
  considérés. `readRecord` lit au plus 64 Ko + 1 octet ; `write` atomique,
  protection `.complete` par défaut ; `sortedNewestFirst` (ordre stable à
  date égale).
- `ScanLayout` : `recordFile`, `Hashable` ; `Dimensions` et
  `ScaleCalibration` `Codable` (le calibrage stocke ses deux cotes, le
  facteur est recalculé et revalidé).
- Tests (`ScanLibraryTests.swift`, 2 suites, 22 tests) : aller-retour JSON,
  date à la seconde, format du fichier, fiche manuelle, 4 non-fiches,
  version future / nulle, 10 champs hors limites, nettoyage et longueur du
  nom (émoji), renommage, nom par défaut, fiche depuis un maillage ;
  classement de vrais dossiers temporaires, décisions de purge, dossier vide,
  entrées inconnues (dont UUID en minuscules), `Scans/` absent, écriture puis
  lecture, identifiant incohérent, fiche de 10 Mo, fiche absente, tri.

App :
- `Features/Bibliotheque/BibliothequeModel.swift` — liste et actions
  (`charger`, `renommer`, `supprimer`, erreurs `BibliothequeErreur`) ; détient
  l'unique `ScanStore`. **Premier inventaire de la session seulement** :
  purge des dossiers incomplets et retrait des photos restées (plus tard, un
  dossier sans modèle pourrait être un scan en cours). Scans sans fiche ou à
  fiche invalide → fiche recréée d'après le modèle (« Scan récupéré », date
  du jour : lire la date d'un fichier est une API à raison requise) ; modèle
  illisible → ligne « Scan illisible », supprimable.
- `Features/Bibliotheque/BibliothequeView.swift` — liste (nom, cotes, date,
  « Calibré »), glisser pour supprimer + confirmation, bouton « Nouveau
  scan » en bas ; vide → « Prêt à scanner ». `ScanRecord+Texte.swift` —
  dates en français, phrase VoiceOver.
- `Features/DetailScan/DetailScanModel.swift` (maillage, taille, export repris
  de `ScanFlowModel`) et `DetailScanView.swift` (ex-`ApercuView` : cotes lues
  dans la fiche, « Voir en 3D », « Exporter en STL », « Renommer » dans la
  barre, « Supprimer le scan » + confirmation ; « Terminer » disparaît au
  profit du retour).
- `Features/Accueil/AccueilView.swift` — `NavigationStack(path:)` sur
  `[ScanLayout]` ; à la fermeture du parcours : rechargement, puis ouverture
  du détail du nouveau scan.
- `Features/Scan/ScanFlowModel.swift` (312 lignes, contre 359) — s'arrête à
  `enregistrer()` : fiche (nom daté du début du scan) **puis** suppression
  des photos ; `ScanFlowView` affiche « Enregistrement du scan… » sans bouton
  Annuler et se ferme seul.
- `Features/Scan/ScanStore.swift` — `inventaire`, `purger`, `lireMaillage`,
  `creerFiche`, `ecrireFiche`.

Écarts au plan : le nom par défaut porte « à » (« Scan du 15/09/2026 à
14:32 ») ; `ScanLibrary.write` prend ses options d'écriture en paramètre
(macOS refuse la classe de protection dans `swift test`) ; les scans sans
fiche lisible restent listés (« Scan illisible ») pour pouvoir les supprimer.
Sécurité : `scan.json` = entrée non fiable (taille bornée, version, champs
validés, identifiant = dossier) ; le nom n'entre jamais dans un chemin ni
dans un journal ; purge des captures interrompues et des photos restées ;
suppression = dossier entier ; aucune nouvelle permission ni API à raison
requise.
Accessibilité : ligne lue en une phrase (nom, date longue, cotes en
centimètres, « calibré ») ; glisser pour supprimer exposé au rotor
VoiceOver, doublé d'un bouton dans le détail ; champ de renommage étiqueté,
longueur bornée pendant la frappe ; annonces « Scan enregistré dans la
bibliothèque », « Scan renommé », « Scan supprimé » ; Dynamic Type (textes
sur plusieurs lignes, pas de largeur fixe).

Test iPhone :
1. Installer par-dessus la version de la tranche 1 → les anciens scans
   apparaissent, nommés « Scan récupéré », avec leurs cotes (dont la boîte
   189,2 × 163,0 × 56,8 mm) ; Console (`stockage`) : « récupéré
   (missingRecord) », « fiche écrite ».
2. Ouvrir un scan → cotes, « Voir en 3D », « Exporter en STL » fonctionnent
   comme en tranche 1.
3. « Renommer » → « Boîte carton » → titre et liste mis à jour ; tuer l'app,
   relancer → nom conservé. Essayer un nom vide → « Enregistrer » inactif
   (à défaut, message « Le nom doit contenir entre 1 et 80 caractères »).
4. Glisser un scan vers la gauche → « Supprimer » → confirmation → la ligne
   disparaît ; Console : « Scan … supprimé ». Idem depuis le détail
   (« Supprimer le scan ») → retour à la liste.
5. Nouveau scan complet → « Enregistrement du scan… » → le détail s'ouvre
   (« Scan du … ») ; retour → il est en tête ; Console : « fiche écrite »,
   « photos et checkpoint supprimés ».
6. Lancer un scan, capturer quelques secondes, **tuer l'app** (balayage dans
   le sélecteur d'apps), relancer → Console : « dossier incomplet purgé,
   photos comprises » ; aucun scan fantôme dans la liste.
7. VoiceOver : une ligne est lue en une phrase ; balayer vers le haut sur
   une ligne → action « Supprimer ». Plus grande taille de texte (Réglages →
   Accessibilité → Affichage et taille du texte) : liste et détail lisibles.

### Étape 2 — Visionneuse intégrée et mesure point à point — livrée le 16/09/2026, test iPhone en attente

**Écart au plan, assumé** : le plan passait par `ray(through:in:to:)` de RealityKit
(incertitude 1). Vérification dans le SDK : cette méthode existe bien sur
`RealityViewCameraContent` **et** sur `EntityTargetValue`, mais l'utiliser
imposait une forme de collision et un geste ciblé sur l'entité, et laissait la
caméra aux contrôles système (donc hors de portée des tests). Choix retenu :
**piloter la caméra nous-mêmes**. La même caméra sert au rendu (un
`PerspectiveCamera` RealityKit) et au calcul du rayon (`OrbitCamera` dans
`Scan3DCore`) ; tout le calcul se teste sur Mac. `.realityViewCameraControls`
n'est pas utilisé ; les gestes (tourner, zoomer) sont à nous.

Core (`Sources/Scan3DCore/Measure/`) :
- `Ray.swift` — demi-droite validée (`init?` refuse une direction nulle ou non
  finie), direction normalisée : les distances sont donc des mètres.
- `MeshPicking.swift` — `Mesh.firstIntersection(with:) -> MeshHit?`
  (Möller-Trumbore, **double face** car un scan a des triangles retournés et des
  trous ; garde le contact positif le plus proche ; lecture par pointeurs non
  vérifiés, les indices ayant déjà été validés par `Mesh.init`).
- `OrbitCamera.swift` — cible, azimut, élévation (bornée avant la verticale),
  distance (bornée) ; `init(framing:)` cadre une boîte englobante ;
  `ray(throughViewPoint:viewSize:)` et `project(_:viewSize:)`.
- `SegmentMeasurement.swift` — distance A-B en mètres et en millimètres, milieu.
- Tests (`MeasureTests.swift`, 4 suites, 22 tests) : rayon normalisé et refusé,
  face avant / à côté / vers l'arrière / depuis l'intérieur / parallèle /
  triangle dégénéré, pose de la caméra, cadrage vérifié en projetant les 8 coins,
  rayon central, ouverture verticale, aller-retour projection → rayon, bornes,
  valeurs non finies, 70,7 mm et 50 mm sur le cube, et une mesure **de bout en
  bout** (caméra → rayon → intersection → 50,0 mm).

App (`Features/Visionneuse/`) :
- `MesureModel.swift` — possède la scène RealityKit : modèle chargé par
  `Entity(contentsOf:)` puis **recalé** sur la boîte englobante du maillage,
  caméra, lumière solidaire de la caméra, marqueurs A (jaune) / B (bleu) et
  trait. Toucher → rayon → intersection → point posé ; troisième toucher =
  nouvelle mesure ; annonces VoiceOver ; distance journalisée.
- `VisionneuseView.swift` — `RealityView` sur fond dégradé, glisser pour
  tourner, pincer pour zoomer, toucher pour poser, boutons « Effacer les
  points » et « Recadrer », distance en grand dans le panneau du bas.
- `DetailScanView.swift` — bouton « Mesurer » (plein écran) au-dessus de
  « Voir en 3D » ; `Journal.swift` — catégorie `mesure`.

**Banc d'essai (16/09/2026, simulateur iPhone 17 Pro)** : l'app a été lancée
avec deux touchers automatiques à des coordonnées connues de la zone 3D, puis
une capture d'écran a été comparée à ces coordonnées.

| Incertitude du plan | Résultat |
|---|---|
| 1. Obtenir un rayon depuis un toucher | ✅ Les repères A et B tombent **exactement** sous les points touchés (35 % / 52 % et 68 % / 58 % de la zone 3D), sans forme de collision ni geste ciblé. |
| 2. Même repère RealityKit / Model I/O | ✅ Facteur journalisé **1,000000** sur un USD en mètres (le cas de la reconstruction) ; **100** sur un fichier déclaré en centimètres, où le recalage aligne l'affichage sur le maillage mesuré. |
| 3. Caméra virtuelle | ✅ RealityKit rend depuis notre `PerspectiveCamera` ajoutée à la scène (`content.camera = .virtual`), lumière comprise. |
| 4. Temps d'intersection | ✅ 6,8 ms pour 51 200 triangles, pire cas, **sans optimisation** (objectif : < 20 ms). |

Découverte annexe : un `.usda` **exporté par Model I/O** se charge (géométrie et
matériau lus, mesurable) mais **ne s'affiche pas** dans RealityKit ; un USD écrit
à la main ou produit par la reconstruction s'affiche normalement. Noté dans
`CLAUDE.md` — à se rappeler si l'on écrit des fichiers 3D en tranche 3.

Sécurité : aucune donnée nouvelle, aucune permission, aucun accès à la caméra de
l'iPhone (rendu virtuel) ; le modèle affiché est celui déjà validé par
`MeshLoader` ; seule la distance mesurée est journalisée (ce n'est pas une donnée
personnelle).
Accessibilité : `accessibilityDirectTouch(options: .requiresActivation)` sur la
zone 3D (VoiceOver garde ses gestes tant que l'utilisateur n'a pas activé la
zone), annonces « Point A posé », « Point B posé. Distance : … », « Aucun point
du modèle à cet endroit », « Vue recadrée » ; distance toujours écrite en toutes
lettres dans le panneau. Limite assumée : viser un point précis reste un geste
visuel.

Test iPhone :
1. Un scan → « Mesurer » : le modèle apparaît entier, de trois quarts, sur fond
   gris. Console (`reconstruction`) : « échelle RealityKit / maillage = 1.0 »
   (toute autre valeur est à me signaler).
2. Glisser pour tourner, pincer pour zoomer, « Recadrer » pour revenir.
3. Toucher les deux coins d'une grande arête du dessus de la boîte : comparer à
   la règle (184 mm) et à la boîte englobante (189,2 mm). Console (`mesure`) :
   « Mesure A-B : … mm ».
4. Mesurer la **hauteur en 3 endroits** (bord, milieu, autre bord) : ce sont les
   chiffres du diagnostic de l'étape 4.
5. Toucher à côté de l'objet : rien ne se pose.
6. VoiceOver : la zone 3D demande une activation (double toucher) ; vérifier les
   annonces à chaque point.
7. Plus grande taille de texte : le panneau du bas reste lisible.

**Résultats (16/09/2026, boîte en carton de la tranche 1, sans retournement)** :
mesure point à point de la grande arête **177,9 mm** (règle 184), hauteur en
3 points **46,0 / 46,9 / 45,0 mm** (règle 50). Les deux méthodes encadrent la
vérité et l'écart est **additif** (−6,1 mm sur 184, −4,0 mm sur 50), ce qui
confirme qu'un facteur d'échelle seul ne suffira pas. Détail et analyse :
`MESURES-TRANCHE-2.md`. Reste à faire : scan **avec** passe « Retourner »
(diagnostic de l'étape 4), VoiceOver et grande taille de texte.

### Étape 3 — Calibrage par scan

Core :
- `ScaleCalibration` `Codable` (étape 1) ; `CalibrationReference` : cote saisie ou
  `ReferenceObject.creditCard` (85,60 / 53,98 mm) ; `Dimensions.scaled(by:)` ; échelle appliquée à
  `SegmentMeasurement` et à l'export (`STLWriter.binaryData(for:scale:)`, par défaut 1) ;
  `MillimeterInput.parse(_:locale:)` (virgule française, refus du vide, du négatif, du non fini).
- Tests : facteur appliqué aux cotes, à une distance et au STL (cube 50 mm × 1,02 → 51 mm), saisie
  « 184,0 » / « 184.0 » / « abc » / « -3 », facteur hors plage refusé au décodage.

App (`Features/Calibrage/CalibrageView.swift`) : depuis une mesure A-B, « Calibrer avec cette
mesure » → cote réelle saisie (`.decimalPad`) ou « Carte bancaire » ; aperçu avant application
(« facteur 0,973 → 184,0 × 158,6 × 55,3 mm ») ; Appliquer / Réinitialiser ; enregistré dans
`scan.json` ; badge « Calibré ».

Sécurité : saisie validée par `ScaleCalibration` (±20 %) et le parseur ; aucune valeur saisie ne
peut provoquer d'arrêt.
Accessibilité : champ étiqueté avec l'unité ; erreur annoncée ; facteur et nouvelles cotes lus en phrase.
Test iPhone : calibrer la boîte sur sa longueur (184) → cotes recalculées ; exporter → Bambu Studio
affiche 184 mm ; réinitialiser → retour aux cotes brutes ; relancer l'app → calibrage conservé.

### Étape 4 — Hauteur : diagnostic, puis plan de coupe si confirmé

Diagnostic (Jinkuro, avec l'outil d'étape 2) : scanner la boîte **sans** puis **avec** passe
« Retourner » ; mesurer la hauteur en 3 points sur chaque modèle ; comparer à 50 mm.
Décision (consignée dans `TRANCHE-2-PLAN.md`) :
- **Fond trop bas de façon systématique** → plan de coupe : Core `Mesh.clipped(belowHeightMeters:)`
  (triangles sous le plan supprimés, triangles traversants découpés ; fond laissé ouvert) + tests ;
  App : réglage « Retirer X mm en bas » visualisé par un plan translucide dans la visionneuse,
  `cutHeightMM` dans `scan.json`, appliqué aux cotes et à l'export.
- **Sinon** → conseil seulement : ligne « retournez l'objet pour scanner le dessous » dans la
  checklist de préparation ; aucun code de coupe.

### Étape 5 — Campagne de mesure (validation de la tranche)

Trois objets : **cube imprimé de 50 mm** (étalon), **boîte en carton**, **interphone Wi-Fi** (objet
cible de la tranche 3). Pour chacun, dans `docs/MESURES-TRANCHE-2.md` : cote physique (pied à
coulisse), boîte englobante, mesure point à point, après calibrage. Objectif indicatif : ≤ 2 mm sur
une mesure point à point après calibrage du cube.

---

## D. Vérification

1. `make test-core` et `make build-check` verts à chaque étape ; build simulateur (doublures).
2. Scénario iPhone de chaque étape, résultats consignés dans `TRANCHE-2-PLAN.md`.
3. Revue sécurité par fonctionnalité (`SECURITY.md`) : `scan.json` non fiable, purge des photos
   orphelines, saisies du calibrage.
4. Critère ROADMAP : `docs/MESURES-TRANCHE-2.md` rempli pour les 3 objets.

## Réutilisation (fichiers existants)

- `Mesh/Mesh.swift` (`Mesh`, `BoundingBox`), `Mesh/MeshLoader.swift`, `Mesh/Dimensions.swift`
  (`Dimensions`, `DimensionsFormatter`), `Units.swift`, `ScaleCalibration.swift`
  (+ `CalibrationError`, `plausibleRange`), `ReferenceObject.swift` (`creditCard`),
  `Scan/ScanLayout.swift`, `Export/STLWriter.swift`, `Export/ExportFilename.swift`.
- App : `Features/Scan/ScanStore.swift` (actor, protection `.complete`, `supprimer`,
  `tailleFichier`), `Features/Export/STLExporter.swift`, `Features/Export/FeuilleDePartage.swift`,
  `Features/Apercu/ApercuView.swift` (base du détail), `App/Journal.swift`.
